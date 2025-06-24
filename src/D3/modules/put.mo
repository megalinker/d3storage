import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
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
import Delete "delete";
import Vector "mo:vector";

module {

    let { NTDO } = StorageClasses;

    // Helper functions for StableTrieMap
    let text_eq = Text.equal;
    let text_hash = Text.hash;
    let nat_eq = func(a : Nat, b : Nat) : Bool { a == b };

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

        // ───────────────────────────────────────────────
        // STRATEGY 1: first-fit inside existing free blocks
        // ───────────────────────────────────────────────
        let regionIdIterator = StableTrieMap.keys(d3.storageRegionMap);

        for (regionId : Filebase.RegionId in regionIdIterator) {
            let storageRegion = switch (StableTrieMap.get(d3.storageRegionMap, nat_eq, Utils.hashNat, regionId)) {
                case (?r) { r };
                case null {
                    Debug.trap("unreachable: map key disappeared during iteration");
                };
            };

            var i : Nat = 0;
            let freeList = storageRegion.freeList;

            while (i < Vector.size(freeList)) {
                let block = Vector.get(freeList, i);

                if (block.size >= requiredSize) {
                    let offset = block.offset;
                    let leftoverSize = block.size - requiredSize;

                    let lastIndex = Vector.size(freeList) - 1;
                    if (i < lastIndex) {
                        let lastBlock = Vector.get(freeList, lastIndex);
                        Vector.put(freeList, i, lastBlock);
                    };
                    ignore Vector.removeLast(freeList);

                    if (leftoverSize > 16) {
                        let leftoverBlock = {
                            offset = offset + requiredSize;
                            size = leftoverSize;
                        };
                        Vector.add(freeList, leftoverBlock);
                    };

                    Delete.coalesceFreeList(storageRegion);

                    return ?{ regionId; storageRegion; offset };
                };
                i += 1;
            };
        };

        // ───────────────────────────────────────────────
        // STRATEGY 2: append at end of an existing region (grow if needed)
        // ───────────────────────────────────────────────
        let regionIdIterator2 = StableTrieMap.keys(d3.storageRegionMap);

        for (regionId : Filebase.RegionId in regionIdIterator2) {
            let storageRegion = switch (StableTrieMap.get(d3.storageRegionMap, nat_eq, Utils.hashNat, regionId)) {
                case (?r) { r };
                case null { Debug.trap("unreachable") };
            };

            let requiredPages = evaluateRequiredPages({
                region = storageRegion.region;
                previousOffset = storageRegion.offset;
                fileSize = requiredSize;
            });

            if (Region.size(storageRegion.region) + requiredPages <= 65_536) {
                growWithBudget(d3, storageRegion.region, requiredPages);

                let offset = storageRegion.offset;
                storageRegion.offset := offset + requiredSize;

                return ?{
                    regionId;
                    storageRegion;
                    offset;
                };
            };
        };

        // ───────────────────────────────────────────────
        // STRATEGY 3: create a brand-new region
        // ───────────────────────────────────────────────
        let requiredPages = (requiredSize + Filebase.PAGE_SIZE - 1) / Filebase.PAGE_SIZE;
        if (requiredPages > 65_536) {
            Debug.trap("File is too large to fit in a single storage region (>4 GiB)");
        };

        let newRegion = Region.new();
        growWithBudget(d3, newRegion, requiredPages);

        let newRegionId = d3.nextRegionId;
        d3.nextRegionId += 1;

        let newStorageRegion : Filebase.StorageRegion = {
            var offset = requiredSize;
            region = newRegion;
            var freeList = Vector.new<Filebase.FreeBlock>();
        };

        StableTrieMap.put(d3.storageRegionMap, nat_eq, Utils.hashNat, newRegionId, newStorageRegion);

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

        let totalAllocatedSize = offsets.bufferOffset;

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

                StableTrieMap.put(
                    fileLocationMap,
                    text_eq,
                    text_hash,
                    fileId,
                    {
                        regionId;
                        offset = newFileOffset;
                        totalAllocatedSize = totalAllocatedSize;
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

        let totalAllocatedSize = offsets.bufferOffset + (Filebase.PAGE_SIZE - (offsets.bufferOffset % Filebase.PAGE_SIZE));

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

                StableTrieMap.put(
                    fileLocationMap,
                    text_eq,
                    text_hash,
                    fileId,
                    {
                        regionId;
                        offset = newFileOffset;
                        totalAllocatedSize = totalAllocatedSize;
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

        switch (StableTrieMap.get(fileLocationMap, text_eq, text_hash, fileId)) {
            case (null) {
                throw Error.reject("File " # fileId # " not found.");
            };
            case (?fileLocation) {
                switch (StableTrieMap.get(storageRegionMap, nat_eq, Utils.hashNat, fileLocation.regionId)) {
                    case (null) {
                        Debug.trap("storeFileChunk: Internal data corruption. FileLocation points to a missing StorageRegion.");
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

                        if (chunkIndex == numOfChunks - 1) {
                            let updatedFileLocation : Filebase.FileLocation = {
                                regionId = fileLocation.regionId;
                                offset = fileLocation.offset;
                                totalAllocatedSize = fileLocation.totalAllocatedSize;
                                fileName = fileLocation.fileName;
                                fileType = fileLocation.fileType;
                                createdAt = fileLocation.createdAt;
                                status = #Complete;
                            };
                            StableTrieMap.put(fileLocationMap, text_eq, text_hash, fileId, updatedFileLocation);
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
