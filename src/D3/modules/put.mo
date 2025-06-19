import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Map "mo:map/Map";
import { nhash; thash } "mo:map/Map";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Filebase "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Utils "utils";
import StorageClasses "../storageClasses";
import Commons "commons";

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
        // --- STRATEGY 1: Search all existing regions for the FIRST available free block ---
        // CORRECT ITERATION: Use the static Map.keys() function to get a key iterator.
        let regionIdIterator = Map.keys(d3.storageRegionMap);
        for (regionId : Filebase.RegionId in regionIdIterator) {

            let storageRegion = switch (Map.get(d3.storageRegionMap, nhash, regionId)) {
                case (?r) { r };
                case (null) {
                    Debug.trap("unreachable: map key disappeared during iteration");
                    let dummy : Filebase.StorageRegion = {
                        var offset = 0;
                        region = Region.new();
                        var freeList = Buffer.Buffer<Filebase.FreeBlock>(0);
                    };
                    dummy;
                };
            };

            // Use a while loop to find the FIRST block that fits.
            var i = 0;
            let freeList = storageRegion.freeList;
            while (i < freeList.size()) {
                let block = freeList.get(i);

                if (block.size >= requiredSize) {
                    // FIRST-FIT: We found a suitable block. Use it and exit immediately.
                    let blockToUse = block;
                    let offset = blockToUse.offset;
                    let leftoverSize = blockToUse.size - requiredSize;

                    if (leftoverSize > 16) {
                        freeList.put(
                            i,
                            {
                                offset = blockToUse.offset + requiredSize;
                                size = leftoverSize;
                            },
                        );
                    } else {
                        let lastIndex = freeList.size() - 1;
                        if (i < lastIndex) {
                            freeList.put(i, freeList.get(lastIndex));
                        };
                        ignore freeList.removeLast();
                    };

                    return ?{ regionId; storageRegion; offset };
                };
                i += 1;
            };
        };

        // --- STRATEGY 2: Check all existing regions for space at the end ---
        // Re-get the iterator for the second loop.
        let regionIdIterator2 = Map.keys(d3.storageRegionMap);
        for (regionId : Filebase.RegionId in regionIdIterator2) {
            let storageRegion = switch (Map.get(d3.storageRegionMap, nhash, regionId)) {
                case (?r) { r };
                case (null) {
                    Debug.trap("unreachable");
                    let dummy : Filebase.StorageRegion = {
                        var offset = 0;
                        region = Region.new();
                        var freeList = Buffer.Buffer<Filebase.FreeBlock>(0);
                    };
                    dummy;
                };
            };

            let requiredPages = evaluateRequiredPages({
                region = storageRegion.region;
                previousOffset = storageRegion.offset;
                fileSize = requiredSize;
            });
            if (Region.size(storageRegion.region) + requiredPages <= 65536) {
                ignore Region.grow(storageRegion.region, requiredPages);
                let newFileOffset = storageRegion.offset;
                storageRegion.offset := newFileOffset + requiredSize;
                return ?{ regionId; storageRegion; offset = newFileOffset };
            };
        };

        // --- STRATEGY 3: All existing regions are full. Create a new one. ---
        let requiredPages = (requiredSize + Filebase.PAGE_SIZE - 1) / Filebase.PAGE_SIZE;
        if (requiredPages > 65536) {
            Debug.trap("File is too large to fit in a single storage region (>4GiB)");
        };

        let newRegion = Region.new();
        ignore Region.grow(newRegion, requiredPages);

        let newRegionId = d3.nextRegionId;
        d3.nextRegionId += 1;

        let newStorageRegion : Filebase.StorageRegion = {
            var offset = requiredSize;
            region = newRegion;
            var freeList = Buffer.Buffer<Filebase.FreeBlock>(0);
        };

        Map.set(d3.storageRegionMap, nhash, newRegionId, newStorageRegion);

        return ?{
            regionId = newRegionId;
            storageRegion = newStorageRegion;
            offset = 0;
        };
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

                Map.set(
                    fileLocationMap,
                    thash,
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

                Map.set(
                    fileLocationMap,
                    thash,
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

        switch (Map.get(fileLocationMap, thash, fileId)) {
            case (null) {
                throw Error.reject("File " # fileId # " not found.");
            };
            case (?fileLocation) {
                switch (Map.get(storageRegionMap, nhash, fileLocation.regionId)) {
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
                            Map.set(fileLocationMap, thash, fileId, updatedFileLocation);
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
