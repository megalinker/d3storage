import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Map "mo:map/Map";
import { nhash; thash } "mo:map/Map";
import Filebase "../types/filebase";
import StorageClasses "../storageClasses";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Commons "commons";

module {

    let { NTDO } = StorageClasses;

    private type FileContext = {
        region : Region.Region;
        offset : Nat64;
        fileSize : Nat64;
        fileNameSize : Nat64;
        fileTypeSize : Nat64;
    };

    private func _getFileContext(d3 : Filebase.D3, fileId : Filebase.FileId) : ?FileContext {
        switch (Map.get(d3.fileLocationMap, thash, fileId)) {
            case (null) { return null };
            case (?fileLocation) {
                switch (Map.get(d3.storageRegionMap, nhash, fileLocation.regionId)) {
                    case (null) { return null };
                    case (?storageRegion) {
                        let offset = fileLocation.offset;
                        let region = storageRegion.region;

                        let fileSize = Region.loadNat64(region, offset + NTDO.getFileSizeRelativeOffset());
                        let fileNameSize = Region.loadNat64(region, offset + NTDO.getFileNameSizeRelativeOffset());
                        let fileTypeSize = Region.loadNat64(region, offset + NTDO.getFileTypeSizeRelativeOffset());

                        return ?{
                            region;
                            offset;
                            fileSize;
                            fileNameSize;
                            fileTypeSize;
                        };
                    };
                };
            };
        };
    };

    public func getFileMetadata({
        d3 : Filebase.D3;
        getFileMetadataInput : InputTypes.GetFileMetadataInputType;
    }) : OutputTypes.GetFileMetadataOutputType {

        let { fileId } = getFileMetadataInput;

        switch (_getFileContext(d3, fileId)) {
            case (null) {
                return null;
            };
            case (?{ region; offset; fileSize; fileNameSize; fileTypeSize }) {
                let fileName = switch (Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileNameRelativeOffset({ fileSize }), Nat64.toNat(fileNameSize)))) {
                    case (?name) { name };
                    case (null) {
                        Debug.trap("Data corruption: failed to decode UTF-8 for fileName. FileId: " # fileId);
                    };
                };

                let fileType = switch (Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileTypeRelativeOffset({ fileSize; fileNameSize }), Nat64.toNat(fileTypeSize)))) {
                    case (?typ) { typ };
                    case (null) {
                        Debug.trap("Data corruption: failed to decode UTF-8 for fileType. FileId: " # fileId);
                    };
                };

                return ?{
                    fileId;
                    fileName;
                    fileType;
                    fileSizeInBytes = fileSize;
                    chunkSizeInBytes = Filebase.CHUNK_SIZE;
                    numOfChunks = Commons.evaluateNumOfChunks({
                        fileSizeInBytes = fileSize;
                    });
                };
            };
        };
    };

    public func getFile({
        d3 : Filebase.D3;
        getFileInput : InputTypes.GetFileInputType;
    }) : OutputTypes.GetFileOutputType {

        let { fileId } = getFileInput;

        switch (_getFileContext(d3, fileId)) {
            case (null) {
                return null;
            };
            case (?{ region; offset; fileSize; fileNameSize; fileTypeSize }) {

                if (fileSize > 2_000_000) {
                    Debug.print("getFile: Attempted to fetch a file (" # Nat64.toText(fileSize) # " bytes) larger than the 2MB message limit. Use the HTTP interface instead.");
                    return null;
                };

                let fileData = Region.loadBlob(region, offset + NTDO.getFileDataRelativeoffset(), Nat64.toNat(fileSize));

                let fileName = switch (Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileNameRelativeOffset({ fileSize }), Nat64.toNat(fileNameSize)))) {
                    case (?name) { name };
                    case (null) {
                        Debug.trap("Data corruption: failed to decode UTF-8 for fileName. FileId: " # fileId);
                    };
                };

                let fileType = switch (Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileTypeRelativeOffset({ fileSize; fileNameSize }), Nat64.toNat(fileTypeSize)))) {
                    case (?typ) { typ };
                    case (null) {
                        Debug.trap("Data corruption: failed to decode UTF-8 for fileType. FileId: " # fileId);
                    };
                };

                return ?{
                    fileId;
                    fileData;
                    fileSize;
                    fileName;
                    fileType;
                };
            };
        };
    };

    public func getFileIds({
        d3 : Filebase.D3;
        getFileIdsInput : InputTypes.GetFileIdsInputType;
    }) : OutputTypes.GetFileIdsOutputType {

        let {} = getFileIdsInput;
        let fileLocationMap = d3.fileLocationMap;

        let fileIdsBuffer = Buffer.Buffer<OutputTypes.FileIdItemType>(Map.size(fileLocationMap));
        for ((fileId, { offset; fileName; fileType }) in Map.entries(fileLocationMap)) {
            fileIdsBuffer.add({ fileId; offset; fileName; fileType });
        };

        return {
            fileIds = Buffer.toArray(fileIdsBuffer);
        };
    };
};
