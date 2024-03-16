import Region "mo:base/Region";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Prelude "mo:base/Prelude";
import Map "mo:map/Map";
import { nhash; thash; } "mo:map/Map";
import Filebase "../types/filebase";
import {
    REGION_ID;
    FILE_SIZE_OFFSET;
    FILE_NAME_SIZE_OFFSET;
    FILE_TYPE_SIZE_OFFSET;
    FILE_DATA_OFFSET;
} "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Utils "utils";

module {

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

        let fileNameOffset = FILE_DATA_OFFSET + fileDataObjectSize;
        let fileTypeOffset = fileNameOffset + fileNameObjectSize;
        let bufferOffset = fileTypeOffset + fileTypeObjectSize;

        let totalFileSize = bufferOffset + Filebase.PAGE_SIZE;

        ignore do ?{
            let fileId = Utils.generateULIDSync();
            let storageRegion = Map.get(storageRegionMap, nhash, REGION_ID)!;
            let region = storageRegion.region;
            let currentOffset = storageRegion.offset;
            let requiredPages = evaluateRequiredPages({ previousOffset = currentOffset; fileSize = totalFileSize });
            ignore Region.grow(region, requiredPages);

            Region.storeNat64(region, currentOffset + FILE_SIZE_OFFSET, fileDataObjectSize);
            Region.storeNat64(region, currentOffset + FILE_NAME_SIZE_OFFSET, fileNameObjectSize);
            Region.storeNat64(region, currentOffset + FILE_TYPE_SIZE_OFFSET, fileTypeObjectSize);
            Region.storeBlob(region, currentOffset + FILE_DATA_OFFSET, fileDataObject);
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

    private func evaluateRequiredPages({ previousOffset : Nat64; fileSize : Nat64 }) : Nat64 {
        let remainingBytes = Filebase.PAGE_SIZE - (previousOffset % Filebase.PAGE_SIZE);
        var requiredPages = (fileSize - (fileSize % Filebase.PAGE_SIZE) ) / Filebase.PAGE_SIZE;
        var reminderBytes = fileSize % Filebase.PAGE_SIZE;
        if (reminderBytes > remainingBytes) {
            requiredPages := requiredPages + 1;
        };
        return requiredPages;
    };

};