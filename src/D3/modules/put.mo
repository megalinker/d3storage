import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Prelude "mo:base/Prelude";
import Error "mo:base/Error";
import Map "mo:map/Map";
import { nhash; thash; } "mo:map/Map";
import Filebase "../types/filebase";
import { REGION_ID; } "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Utils "utils";
import StorageClasses "../storageClasses";
import Commons "commons";

module {

    let { NTDO; } = StorageClasses;

    public func storeFile({
        d3 : Filebase.D3;
        storeFileInput : InputTypes.StoreFileInputType;
    }) : async OutputTypes.StoreFileOutputType {

        let { fileDataObject; fileName; fileType; } = storeFileInput;
        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        if (Map.size(storageRegionMap) == 0) {
            let region = Region.new();
            Map.set(storageRegionMap, nhash, Region.id(region), { var offset : Nat64 = 0; region; });
        };

        /////////////////////////////////////////////////////////////////////////////////////////////

        let fileNameObject = Text.encodeUtf8(fileName);
        let fileTypeObject = Text.encodeUtf8(fileType);

        let fileDataObjectSize = Nat64.fromNat(fileDataObject.size());
        let fileNameObjectSize = Nat64.fromNat(fileNameObject.size());
        let fileTypeObjectSize = Nat64.fromNat(fileTypeObject.size());

        let {
            fileStorageClassCodeOffset;
            fileSizeOffset;
            fileNameSizeOffset;
            fileTypeSizeOffset;
            fileDataOffset;
            fileNameOffset;
            fileTypeOffset;
            bufferOffset;
        } = NTDO.getAllRelativeOffsets({
            fileSize = fileDataObjectSize;
            fileNameSize = fileNameObjectSize;
            fileTypeSize = fileTypeObjectSize;
        });

        let totalFileSize = bufferOffset + Filebase.PAGE_SIZE;

        ignore do ?{
            let fileId = Utils.generateULIDSync();
            let storageRegion = Map.get(storageRegionMap, nhash, REGION_ID)!;
            let region = storageRegion.region;
            let currentOffset = storageRegion.offset;
            let requiredPages = evaluateRequiredPages({ region; previousOffset = currentOffset; fileSize = totalFileSize });
            ignore Region.grow(region, requiredPages);

            Region.storeNat64(region, currentOffset + fileStorageClassCodeOffset, NTDO.STORAGE_CLASS_CODE);
            Region.storeNat64(region, currentOffset + fileSizeOffset, fileDataObjectSize);
            Region.storeNat64(region, currentOffset + fileNameSizeOffset, fileNameObjectSize);
            Region.storeNat64(region, currentOffset + fileTypeSizeOffset, fileTypeObjectSize);
            Region.storeBlob(region, currentOffset + fileDataOffset, fileDataObject);
            Region.storeBlob(region, currentOffset + fileNameOffset, fileNameObject);
            Region.storeBlob(region, currentOffset + fileTypeOffset, fileTypeObject);

            let newOffset = currentOffset + totalFileSize;
            storageRegion.offset := newOffset;
            Map.set(fileLocationMap, thash, fileId, { regionId = REGION_ID; offset = currentOffset; fileName; fileType; });

            return { fileId; };
        };

        /////////////////////////////////////////////////////////////////////////////////////////////

        Prelude.unreachable();

    };

    private func evaluateRequiredPages({ region : Region.Region; previousOffset : Nat64; fileSize : Nat64 }) : Nat64 {

        let currentRegionSizeInPages = Region.size(region);
        let currentRegionSizeInBytes = currentRegionSizeInPages * Filebase.PAGE_SIZE;
        let remainingBytes = if (currentRegionSizeInBytes > previousOffset) currentRegionSizeInBytes - previousOffset else 0 : Nat64;
        
        let reminderBytes = fileSize % Filebase.PAGE_SIZE;
        var requiredPages = (fileSize - reminderBytes) / Filebase.PAGE_SIZE;
        if (reminderBytes > remainingBytes) {
            requiredPages := requiredPages + 1;
        };
        return requiredPages;
    };

    public func storeFileMetadata({
        d3 : Filebase.D3;
        storeFileMetadataInput : InputTypes.StoreFileMetadataInputType;
    }) : async OutputTypes.StoreFileMetadataOutputType {

        let { fileSizeInBytes; fileName; fileType; } = storeFileMetadataInput;
        if (fileSizeInBytes < Filebase.CHUNK_SIZE) {
            throw Error.reject("File size is less than the minimum chunk size of " # debug_show(Filebase.CHUNK_SIZE) # " bytes.");
        };

        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        if (Map.size(storageRegionMap) == 0) {
            let region = Region.new();
            Map.set(storageRegionMap, nhash, Region.id(region), { var offset : Nat64 = 0; region; });
        };

        /////////////////////////////////////////////////////////////////////////////////////////////

        let fileNameObject = Text.encodeUtf8(fileName);
        let fileTypeObject = Text.encodeUtf8(fileType);

        let fileDataObjectSize = fileSizeInBytes;
        let fileNameObjectSize = Nat64.fromNat(fileNameObject.size());
        let fileTypeObjectSize = Nat64.fromNat(fileTypeObject.size());

        let {
            fileStorageClassCodeOffset;
            fileSizeOffset;
            fileNameSizeOffset;
            fileTypeSizeOffset;
            fileNameOffset;
            fileTypeOffset;
            bufferOffset;
        } = NTDO.getAllRelativeOffsets({
            fileSize = fileDataObjectSize;
            fileNameSize = fileNameObjectSize;
            fileTypeSize = fileTypeObjectSize;
        });

        let totalFileSize = bufferOffset + Filebase.PAGE_SIZE;

        ignore do ?{
            let fileId = Utils.generateULIDSync();
            let storageRegion = Map.get(storageRegionMap, nhash, REGION_ID)!;
            let region = storageRegion.region;
            let currentOffset = storageRegion.offset;
            let requiredPages = evaluateRequiredPages({ region; previousOffset = currentOffset; fileSize = totalFileSize });
            ignore Region.grow(region, requiredPages);

            Region.storeNat64(region, currentOffset + fileStorageClassCodeOffset, NTDO.STORAGE_CLASS_CODE);
            Region.storeNat64(region, currentOffset + fileSizeOffset, fileDataObjectSize);
            Region.storeNat64(region, currentOffset + fileNameSizeOffset, fileNameObjectSize);
            Region.storeNat64(region, currentOffset + fileTypeSizeOffset, fileTypeObjectSize);
            Region.storeBlob(region, currentOffset + fileNameOffset, fileNameObject);
            Region.storeBlob(region, currentOffset + fileTypeOffset, fileTypeObject);

            let newOffset = currentOffset + totalFileSize;
            storageRegion.offset := newOffset;
            Map.set(fileLocationMap, thash, fileId, { regionId = REGION_ID; offset = currentOffset; fileName; fileType; });

            return {
                fileId;
                chunkSizeInBytes = Filebase.CHUNK_SIZE;
                numOfChunks = Commons.evaluateNumOfChunks({ fileSizeInBytes });
            };
        };

        /////////////////////////////////////////////////////////////////////////////////////////////

        Prelude.unreachable();

    };

    public func storeFileChunk({
        d3 : Filebase.D3;
        storeFileChunkInput : InputTypes.StoreFileChunkInputType;
    }) : async OutputTypes.StoreFileChunkOutputType {

        let { fileId; chunkData; chunkIndex; } = storeFileChunkInput;
        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        if (not Map.has(fileLocationMap, thash, fileId)) {
            throw Error.reject("File " # fileId # " not found.");
        }; 

        /////////////////////////////////////////////////////////////////////////////////////////////

        ignore do ?{
            let fileLocation = Map.get(fileLocationMap, thash, fileId)!;
            let storageRegion = Map.get(storageRegionMap, nhash, fileLocation.regionId)!;
            let offset = fileLocation.offset;
            let region = storageRegion.region;

            let fileSizeInBytes = Region.loadNat64(region, offset + NTDO.getFileSizeRelativeOffset());
            let numOfChunks = Commons.evaluateNumOfChunks({ fileSizeInBytes });
            let chunkSize = Commons.evaluateChunkSize({ chunkIndex; numOfChunks; fileSizeInBytes });

            /////////////////////////////////////////////////////////////////////////////////////////////

            // check if chunk index is out of bounds
            if (chunkIndex >= numOfChunks) {
                throw Error.reject("Chunk index " # debug_show(chunkIndex) # " is out of bounds.");
            };

            // check if chunk size is greater than the maximum chunk size
            if (Nat64.fromNat(chunkData.size()) > chunkSize) {
                throw Error.reject("Chunk size is greater than the maximum chunk size of " # debug_show(Filebase.CHUNK_SIZE) # " bytes.");
            };

            /////////////////////////////////////////////////////////////////////////////////////////////

            Region.storeBlob(region, offset + NTDO.getFileDataRelativeoffset() + chunkIndex * Filebase.CHUNK_SIZE, chunkData);

            return {
                fileId;
                chunkIndex;
            };
        };

        /////////////////////////////////////////////////////////////////////////////////////////////

        Prelude.unreachable();
    };

};