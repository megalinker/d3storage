import Filebase "types/filebase";
import Put "modules/put";
import Get "modules/get";
import InputTypes "types/input";
import OutputTypes "types/output";

module {

    public func updateOperation({
        d3 : Filebase.D3;
        updateOperationInput : InputTypes.UpdateOperationInputType;
    }) : async OutputTypes.UpdateOperationOutputType {

        switch (updateOperationInput) {
            case (#StoreFile(storeFileInput)) {
                return #StoreFileOutput(await Put.storeFile({ d3; storeFileInput; }))
            };
        };

    };

    public func queryOperation({
        d3 : Filebase.D3;
        queryOperationInput : InputTypes.QueryOperationInputType;
    }) : OutputTypes.QueryOperationOutputType {

        switch (queryOperationInput) {
            case (#GetFile(getFileInput)) {
                return #GetFileOutput(Get.getFile({ d3; getFileInput; }))
            };
        };
    };

};