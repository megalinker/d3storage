module {
    
    public type StoreFileOutputType = {
        fileId : Text;
    };

    public type GetFileOutputType = ?{
        fileId : Text;
        fileData : Blob;
        filename : Text;
        fileType : Text;
    };

    public type UpdateOperationOutputType = {
        #StoreFileOutput : StoreFileOutputType;
    };

    public type QueryOperationOutputType = {
        #GetFileOutput : GetFileOutputType;
    };

};