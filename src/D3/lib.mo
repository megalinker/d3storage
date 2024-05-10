import Filebase "types/filebase";
import Put "modules/put";
import Get "modules/get";
import GetHttp "modules/getHttp";
import Service "service";
import OutputTypes "types/output";
import InputTypes "types/input";
import HttpTypes "types/http";

module {

    public type D3 = Filebase.D3;
    public let D3 = Filebase.D3;

    ///////////////////////////// UPDATE OPERATIONS ////////////////////////

    public type StoreFileInputType = InputTypes.StoreFileInputType;
    public type StoreFileOutputType = OutputTypes.StoreFileOutputType;
    public let storeFile = Put.storeFile;

    public type storeFileMetadataInputType = InputTypes.StoreFileMetadataInputType;
    public type storeFileMetadataOutputType = OutputTypes.StoreFileMetadataOutputType;
    public let storeFileMetadata = Put.storeFileMetadata;

    public type StoreFileChunkInputType = InputTypes.StoreFileChunkInputType;
    public type StoreFileChunkOutputType = OutputTypes.StoreFileChunkOutputType;
    public let storeFileChunk = Put.storeFileChunk;

    ///////////////////////////// QUERY OPERATIONS ////////////////////////

    public type GetFileMetadataInputType = InputTypes.GetFileMetadataInputType;
    public type GetFileMetadataOutputType = OutputTypes.GetFileMetadataOutputType;
    public let getFileMetadata = Get.getFileMetadata;

    public type GetFileInputType = InputTypes.GetFileInputType;
    public type GetFileOutputType = OutputTypes.GetFileOutputType;
    public let getFile = Get.getFile;

    public type GetFileIdsInputType = InputTypes.GetFileIdsInputType;
    public type GetFileIdsOutputType = OutputTypes.GetFileIdsOutputType;
    public type FileIdItemType = OutputTypes.FileIdItemType;
    public let getFileIds = Get.getFileIds;

    /////////////////////////// SERVICE OPERATIONS //////////////////////////

    public type UpdateOperationInputType = InputTypes.UpdateOperationInputType;
    public type UpdateOperationOutputType = OutputTypes.UpdateOperationOutputType;
    public let updateOperation = Service.updateOperation;

    public type QueryOperationInputType = InputTypes.QueryOperationInputType;
    public type QueryOperationOutputType = OutputTypes.QueryOperationOutputType;
    public let queryOperation = Service.queryOperation;

    //////////////////////////// HTTP OPERATIONS ////////////////////////////

    public type HttpRequest = HttpTypes.HttpRequest;
    public type HttpResponse = HttpTypes.HttpResponse;
    public let getFileHTTP = GetHttp.getFileHTTP;

    public type StreamingCallbackToken = HttpTypes.StreamingCallbackToken;
    public type StreamingCallbackHttpResponse = HttpTypes.StreamingCallbackHttpResponse;
    public let httpStreamingCallback = GetHttp.httpStreamingCallback;

};