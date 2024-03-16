import Filebase "filebase";

module {

    public type StoreFileInputType = {
        fileDataObject : Blob;
        fileName : Text;
        fileType : Text;
    };

    public type GetFileInputType = {
        fileId : Text;
    };

    public type UpdateOperationInputType = {
        #StoreFile : StoreFileInputType;
    };

    public type QueryOperationInputType = {
        #GetFile : GetFileInputType;
    };
};