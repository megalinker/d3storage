import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Prelude "mo:base/Prelude";
import Map "mo:map/Map";
import { nhash; thash; } "mo:map/Map";
import Filebase "../types/filebase";
import StorageClasses "../storageClasses";
import InputTypes "../types/input";
import OutputTypes "../types/output";

module {

    let { NTDO; } = StorageClasses;

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

};