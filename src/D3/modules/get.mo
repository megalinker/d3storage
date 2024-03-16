import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Prelude "mo:base/Prelude";
import Map "mo:map/Map";
import { nhash; thash; } "mo:map/Map";
import Filebase "../types/filebase";
import {
    FILE_SIZE_OFFSET;
    FILE_NAME_SIZE_OFFSET;
    FILE_TYPE_SIZE_OFFSET;
    FILE_DATA_OFFSET;
} "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";

module {

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

            let fileDataSize = Region.loadNat64(region, offset + FILE_SIZE_OFFSET);
            let filenameSize = Region.loadNat64(region, offset + FILE_NAME_SIZE_OFFSET);
            let fileTypeSize = Region.loadNat64(region, offset + FILE_TYPE_SIZE_OFFSET);

            let fileData = Region.loadBlob(region, offset + FILE_DATA_OFFSET, Nat64.toNat(fileDataSize));
            let filename = Text.decodeUtf8(Region.loadBlob(region, offset + FILE_DATA_OFFSET + fileDataSize, Nat64.toNat(filenameSize)))!;
            let fileType = Text.decodeUtf8(Region.loadBlob(region, offset + FILE_DATA_OFFSET + fileDataSize + filenameSize, Nat64.toNat(fileTypeSize)))!;

            return ?{
                fileId;
                fileData;
                filename;
                fileType;
            };
        };

        Prelude.unreachable();
    };

};