import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import StableTrieMap "../utils/StableTrieMap";
import Filebase "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Utils "utils";
import StorageClasses "../storageClasses";
import Commons "commons";
import Vector "mo:vector";
import BTree "mo:stableheapbtreemap/BTree";
import Allocator "allocator";

module {

    let { NTDO } = StorageClasses;

    private func evaluateRequiredPages({
        region : Region.Region;
        previousOffset : Nat64;
        fileSize : Nat64;
    }) : Nat64 {
        let currentSizeInBytes = Region.size(region) * Filebase.PAGE_SIZE;
        let requiredSizeInBytes = previousOffset + fileSize;
        if (requiredSizeInBytes <= currentSizeInBytes) { return 0 };
        let deficitInBytes = requiredSizeInBytes - currentSizeInBytes;
        let additionalPages = (deficitInBytes + Filebase.PAGE_SIZE - 1) / Filebase.PAGE_SIZE;
        return additionalPages;
    };

    private func _findAvailableSpace(
        d3 : Filebase.D3,
        requiredSize : Nat64,
    ) : ?{
        regionId : Filebase.RegionId;
        storageRegion : Filebase.StorageRegion;
        offset : Nat64;
    } {

        var bestFitOption : ?{
            regionId : Filebase.RegionId;
            storageRegion : Filebase.StorageRegion;
            offset : Nat64;
            foundSize : Nat64;
        } = null;

        var bestAppendOption : ?{
            regionId : Filebase.RegionId;
            storageRegion : Filebase.StorageRegion;
            requiredPages : Nat64;
        } = null;

        // ───────────────────────────────────────────────
        // STRATEGY 1: Combined Single-Pass Search
        // ───────────────────────────────────────────────
        let regionIdIterator = StableTrieMap.keys(d3.storageRegionMap);

        for (regionId : Filebase.RegionId in regionIdIterator) {
            let storageRegion = switch (StableTrieMap.get(d3.storageRegionMap, Utils.nat_eq, Utils.hashNat, regionId)) {
                case (?r) { r };
                case null {
                    Debug.trap("unreachable: map key disappeared during iteration");
                };
            };

            // --- Part 1: Check for a best-fit block in this region ---
            let scanResult = BTree.scanLimit<Nat64, Vector.Vector<Nat64>>(
                storageRegion.freeListBySize,
                Utils.nat64_compare,
                requiredSize, // lower bound
                0xFFFFFFFFFFFFFFFF, // upper bound (Nat64.max)
                #fwd,
                1,
            );

            if (scanResult.results.size() > 0) {
                let (foundSize, offsetsVec) = scanResult.results[0];
                // Is this fit better than the best one we've found so far?
                // A better fit is one that is smaller (less wasted space).
                let isBetterFit = switch (bestFitOption) {
                    case null { true }; // First one we've found
                    case (?bf) { foundSize < bf.foundSize };
                };

                if (isBetterFit) {
                    bestFitOption := ?{
                        regionId;
                        storageRegion;
                        offset = Vector.get(offsetsVec, 0); // Take the first available offset
                        foundSize;
                    };
                };
            };

            // --- Part 2: Evaluate this region as a candidate for appending ---
            let requiredPages = evaluateRequiredPages({
                region = storageRegion.region;
                previousOffset = storageRegion.offset;
                fileSize = requiredSize;
            });

            if (Region.size(storageRegion.region) + requiredPages <= 65_536) {
                // Is this a better append candidate than the best one so far?
                // A better candidate is one that requires fewer pages to grow.
                let isBetterCandidate = switch (bestAppendOption) {
                    case null { true }; // First one we've found
                    case (?ba) { requiredPages < ba.requiredPages };
                };

                if (isBetterCandidate) {
                    bestAppendOption := ?{
                        regionId;
                        storageRegion;
                        requiredPages;
                    };
                };
            };
        };

        // ───────────────────────────────────────────────
        // Prioritize Best-Fit over Appending
        // ───────────────────────────────────────────────
        switch (bestFitOption) {
            case (?{ regionId; storageRegion; offset; foundSize }) {
                // Remove this block from both free list maps.
                Allocator.removeFromFreeLists(storageRegion, offset, foundSize);

                // Check if we have leftover space worth keeping.
                let leftoverSize = foundSize - requiredSize;
                if (leftoverSize > 16) {
                    // 16 bytes is a reasonable minimum.
                    // Add the leftover piece back to the free lists.
                    let leftoverBlock = {
                        offset = Utils.checked_add(offset, requiredSize);
                        size = leftoverSize;
                    };
                    Allocator.addToFreeLists(storageRegion, leftoverBlock);
                };

                return ?{ regionId; storageRegion; offset };
            };
            case null {
                // No best-fit block was found, fall through to check append option.
            };
        };

        switch (bestAppendOption) {
            case (?{ regionId; storageRegion; requiredPages }) {
                growWithBudget(d3, storageRegion.region, requiredPages);
                let offset = storageRegion.offset;
                storageRegion.offset := Utils.checked_add(offset, requiredSize);
                return ?{ regionId; storageRegion; offset };
            };
            case null {
                // No append candidate was found, fall through to create a new region.
            };
        };

        // ───────────────────────────────────────────────
        // STRATEGY 2: Create a brand-new region
        // ───────────────────────────────────────────────
        let requiredPages = (requiredSize + Filebase.PAGE_SIZE - 1) / Filebase.PAGE_SIZE;
        if (requiredPages > 65_536) {
            Debug.trap("File is too large to fit in a single storage region (>4 GiB)");
        };

        let newRegion = Region.new();
        growWithBudget(d3, newRegion, requiredPages);

        let newRegionId = d3.nextRegionId;
        d3.nextRegionId += 1;

        // Initialize the new StorageRegion with empty B-Tree Maps
        let newStorageRegion : Filebase.StorageRegion = {
            var offset = requiredSize;
            region = newRegion;
            var freeBlocksByOffset = BTree.init<Nat64, Nat64>(null);
            var freeListBySize = BTree.init<Nat64, Vector.Vector<Nat64>>(null);
        };

        StableTrieMap.put(d3.storageRegionMap, Utils.nat_eq, Utils.hashNat, newRegionId, newStorageRegion);

        return ?{
            regionId = newRegionId;
            storageRegion = newStorageRegion;
            offset = 0;
        };
    };

    private func growWithBudget(d3 : Filebase.D3, region : Region.Region, pages : Nat64) {
        if (pages == 0) { return };

        let bytesToAdd : Nat64 = pages * Filebase.PAGE_SIZE;
        if (d3.bytesAllocated + bytesToAdd > d3.BYTES_BUDGET) {
            Debug.trap(
                "Out of memory: requested "
                # Nat64.toText(bytesToAdd)
                # " B, but budget "
                # Nat64.toText(d3.BYTES_BUDGET)
                # " B would be exceeded."
            );
        };

        ignore Region.grow(region, pages);
        d3.bytesAllocated += bytesToAdd;
    };

    public func storeFile({
        d3 : Filebase.D3;
        storeFileInput : InputTypes.StoreFileInputType;
    }) : async OutputTypes.StoreFileOutputType {
        let { fileDataObject; fileName; fileType } = storeFileInput;
        let fileLocationMap = d3.fileLocationMap;

        let fileNameObject = Text.encodeUtf8(fileName);
        let fileTypeObject = Text.encodeUtf8(fileType);

        let fileDataObjectSize = Nat64.fromNat(fileDataObject.size());
        let fileNameObjectSize = Nat64.fromNat(fileNameObject.size());
        let fileTypeObjectSize = Nat64.fromNat(fileTypeObject.size());

        let offsets = NTDO.getAllRelativeOffsets({
            fileSize = fileDataObjectSize;
            fileNameSize = fileNameObjectSize;
            fileTypeSize = fileTypeObjectSize;
        });

        let totalAllocatedSize = Utils.round_up_to_8(offsets.bufferOffset);

        switch (_findAvailableSpace(d3, totalAllocatedSize)) {
            case (null) {
                Debug.trap("storeFile: Out of memory. Could not find or allocate space.");
            };
            case (?{ regionId; storageRegion; offset = newFileOffset }) {
                let fileId = Utils.generateULIDSync();
                let region = storageRegion.region;

                Region.storeNat64(region, newFileOffset + offsets.fileStorageClassCodeOffset, NTDO.STORAGE_CLASS_CODE);
                Region.storeNat64(region, newFileOffset + offsets.fileSizeOffset, fileDataObjectSize);
                Region.storeNat64(region, newFileOffset + offsets.fileNameSizeOffset, fileNameObjectSize);
                Region.storeNat64(region, newFileOffset + offsets.fileTypeSizeOffset, fileTypeObjectSize);
                Region.storeBlob(region, newFileOffset + offsets.fileDataOffset, fileDataObject);
                Region.storeBlob(region, newFileOffset + offsets.fileNameOffset, fileNameObject);
                Region.storeBlob(region, newFileOffset + offsets.fileTypeOffset, fileTypeObject);

                ignore BTree.insert(
                    fileLocationMap,
                    Text.compare,
                    fileId,
                    {
                        regionId;
                        offset = newFileOffset;
                        totalAllocatedSize;
                        fileName;
                        fileType;
                        createdAt = Time.now();
                        status = #Complete;
                    },
                );

                return { fileId };
            };
        };
    };

    public func storeFileMetadata({
        d3 : Filebase.D3;
        storeFileMetadataInput : InputTypes.StoreFileMetadataInputType;
    }) : async OutputTypes.StoreFileMetadataOutputType {
        let { fileSizeInBytes; fileName; fileType } = storeFileMetadataInput;
        if (fileSizeInBytes < Filebase.CHUNK_SIZE) {
            throw Error.reject("File size is less than the minimum chunk size of " # debug_show (Filebase.CHUNK_SIZE) # " bytes.");
        };

        let fileLocationMap = d3.fileLocationMap;

        let fileNameObject = Text.encodeUtf8(fileName);
        let fileTypeObject = Text.encodeUtf8(fileType);

        let fileDataObjectSize = fileSizeInBytes;
        let fileNameObjectSize = Nat64.fromNat(fileNameObject.size());
        let fileTypeObjectSize = Nat64.fromNat(fileTypeObject.size());

        let offsets = NTDO.getAllRelativeOffsets({
            fileSize = fileDataObjectSize;
            fileNameSize = fileNameObjectSize;
            fileTypeSize = fileTypeObjectSize;
        });

        // The region growth logic in _findAvailableSpace handles the page-based physical memory.
        let totalAllocatedSize = Utils.round_up_to_8(offsets.bufferOffset);

        switch (_findAvailableSpace(d3, totalAllocatedSize)) {
            case (null) {
                Debug.trap("storeFileMetadata: Out of memory. Could not find or allocate space.");
            };
            case (?{ regionId; storageRegion; offset = newFileOffset }) {
                let fileId = Utils.generateULIDSync();
                let region = storageRegion.region;

                Region.storeNat64(region, newFileOffset + offsets.fileStorageClassCodeOffset, NTDO.STORAGE_CLASS_CODE);
                Region.storeNat64(region, newFileOffset + offsets.fileSizeOffset, fileDataObjectSize);
                Region.storeNat64(region, newFileOffset + offsets.fileNameSizeOffset, fileNameObjectSize);
                Region.storeNat64(region, newFileOffset + offsets.fileTypeSizeOffset, fileTypeObjectSize);
                Region.storeBlob(region, newFileOffset + offsets.fileNameOffset, fileNameObject);
                Region.storeBlob(region, newFileOffset + offsets.fileTypeOffset, fileTypeObject);

                ignore BTree.insert(
                    fileLocationMap,
                    Text.compare,
                    fileId,
                    {
                        regionId;
                        offset = newFileOffset;
                        totalAllocatedSize;
                        fileName;
                        fileType;
                        createdAt = Time.now();
                        status = #Pending;
                    },
                );

                return {
                    fileId;
                    chunkSizeInBytes = Filebase.CHUNK_SIZE;
                    numOfChunks = Commons.evaluateNumOfChunks({
                        fileSizeInBytes;
                    });
                };
            };
        };
    };

    public func storeFileChunk({
        d3 : Filebase.D3;
        storeFileChunkInput : InputTypes.StoreFileChunkInputType;
    }) : async OutputTypes.StoreFileChunkOutputType {
        let { fileId; chunkData; chunkIndex } = storeFileChunkInput;
        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        switch (BTree.get(fileLocationMap, Text.compare, fileId)) {
            case (null) {
                throw Error.reject("File " # fileId # " not found.");
            };
            case (?fileLocation) {
                // Reject writes to a file that is already finalized.
                if (fileLocation.status == #Complete) {
                    throw Error.reject("File " # fileId # " is already complete. No more chunks can be stored.");
                };

                switch (StableTrieMap.get(storageRegionMap, Utils.nat_eq, Utils.hashNat, fileLocation.regionId)) {
                    case (null) {
                        Debug.trap("storeFileChunk: Internal data corruption. FileLocation points to a missing StorageRegion.");
                        // This path is a trap, so returning a value is for type-checking, it won't be reached.
                        return { fileId = ""; chunkIndex = 0 };
                    };
                    case (?storageRegion) {
                        let offset = fileLocation.offset;
                        let region = storageRegion.region;

                        let fileSizeInBytes = Region.loadNat64(region, offset + NTDO.getFileSizeRelativeOffset());
                        let numOfChunks = Commons.evaluateNumOfChunks({
                            fileSizeInBytes;
                        });
                        let chunkSize = Commons.evaluateChunkSize({
                            chunkIndex;
                            numOfChunks;
                            fileSizeInBytes;
                        });

                        if (chunkIndex >= numOfChunks) {
                            throw Error.reject("Chunk index " # debug_show (chunkIndex) # " is out of bounds.");
                        };

                        if (Nat64.fromNat(chunkData.size()) > chunkSize) {
                            throw Error.reject("Chunk size is greater than the expected chunk size of " # debug_show (chunkSize) # " bytes for this index.");
                        };

                        let chunkStartOffset = offset + NTDO.getFileDataRelativeoffset() + chunkIndex * Filebase.CHUNK_SIZE;
                        Region.storeBlob(region, chunkStartOffset, chunkData);

                        // This logic correctly marks the file as complete on the final chunk.
                        if (chunkIndex == numOfChunks - 1) {
                            let updatedFileLocation = {
                                fileLocation with status = #Complete
                            };
                            ignore BTree.insert(fileLocationMap, Text.compare, fileId, updatedFileLocation);
                        };

                        return {
                            fileId;
                            chunkIndex;
                        };
                    };
                };
            };
        };
    };
};
