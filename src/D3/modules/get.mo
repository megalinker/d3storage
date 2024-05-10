import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Prelude "mo:base/Prelude";
import Buffer "mo:base/Buffer";
import Map "mo:map/Map";
import { nhash; thash; } "mo:map/Map";
import Filebase "../types/filebase";
import StorageClasses "../storageClasses";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Commons "commons";

module {

    let { NTDO; } = StorageClasses;

    public func getFileMetadata({
        d3 : Filebase.D3;
        getFileMetadataInput : InputTypes.GetFileMetadataInputType;
    }) : OutputTypes.GetFileMetadataOutputType {

        let { fileId; } = getFileMetadataInput;
        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        if (not Map.has(fileLocationMap, thash, fileId)) {
            return null;
        };

        ignore do ?{
            let fileLocation = Map.get(fileLocationMap, thash, fileId)!;
            let storageRegion = Map.get(storageRegionMap, nhash, fileLocation.regionId)!;
            let offset = fileLocation.offset;
            let region = storageRegion.region;

            let fileSize = Region.loadNat64(region, offset + NTDO.getFileSizeRelativeOffset());
            let fileNameSize = Region.loadNat64(region, offset + NTDO.getFileNameSizeRelativeOffset());
            let fileTypeSize = Region.loadNat64(region, offset + NTDO.getFileTypeSizeRelativeOffset());

            let fileName = Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileNameRelativeOffset({ fileSize }), Nat64.toNat(fileNameSize)))!;
            let fileType = Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileTypeRelativeOffset({ fileSize; fileNameSize }), Nat64.toNat(fileTypeSize)))!;

            return ?{
                fileId;
                fileName;
                fileType;
                fileSizeInBytes = fileSize;
                chunkSizeInBytes = Filebase.CHUNK_SIZE;
                numOfChunks = Commons.evaluateNumOfChunks({ fileSizeInBytes = fileSize });
            };
        };

        Prelude.unreachable();        
    };

    public func getFile({
        d3 : Filebase.D3;
        getFileInput : InputTypes.GetFileInputType;
    }) : OutputTypes.GetFileOutputType {

        let { fileId; } = getFileInput;
        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        if (not Map.has(fileLocationMap, thash, fileId)) {
            return null;
        };

        ignore do ?{
            let fileLocation = Map.get(fileLocationMap, thash, fileId)!;
            let storageRegion = Map.get(storageRegionMap, nhash, fileLocation.regionId)!;
            let offset = fileLocation.offset;
            let region = storageRegion.region;

            let fileSize = Region.loadNat64(region, offset + NTDO.getFileSizeRelativeOffset());
            let fileNameSize = Region.loadNat64(region, offset + NTDO.getFileNameSizeRelativeOffset());
            let fileTypeSize = Region.loadNat64(region, offset + NTDO.getFileTypeSizeRelativeOffset());

            let fileData = Region.loadBlob(region, offset + NTDO.getFileDataRelativeoffset(), Nat64.toNat(fileSize));
            let fileName = Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileNameRelativeOffset({ fileSize }), Nat64.toNat(fileNameSize)))!;
            let fileType = Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileTypeRelativeOffset({ fileSize; fileNameSize }), Nat64.toNat(fileTypeSize)))!;

            return ?{
                fileId;
                fileData;
                fileSize;
                fileName;
                fileType;
            };
        };

        Prelude.unreachable();
    };

    public func getFileIds({
        d3 : Filebase.D3;
        getFileIdsInput : InputTypes.GetFileIdsInputType;
    }) : OutputTypes.GetFileIdsOutputType {

        let {} = getFileIdsInput;
        let fileLocationMap = d3.fileLocationMap;

        let fileIdsBuffer = Buffer.Buffer<OutputTypes.FileIdItemType>(Map.size(fileLocationMap));
        for ((fileId, { offset; fileName; fileType; }) in Map.entries(fileLocationMap)) {
            fileIdsBuffer.add({ fileId; offset; fileName; fileType; });
        };

        return {
            fileIds = Buffer.toArray(fileIdsBuffer);
        };
    };

};