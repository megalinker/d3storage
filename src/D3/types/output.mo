module {

    public type StoreFileOutputType = {
        fileId : Text;
    };
    public type StoreFileMetadataOutputType = {
        fileId : Text;
        chunkSizeInBytes : Nat64;
        numOfChunks : Nat64;
    };

    public type StoreFileChunkOutputType = {
        fileId : Text;
        chunkIndex : Nat64;
    };

    public type GetFileOutputType = ?{
        fileId : Text;
        fileData : Blob;
        fileSize : Nat64;
        fileName : Text;
        fileType : Text;
    };

    public type FileIdItemType = {
        fileId : Text;
        offset : Nat64;
        fileName : Text;
        fileType : Text;
    };

    public type GetFileIdsOutputType = {
        fileIds : [ FileIdItemType ];
    };

    public type UpdateOperationOutputType = {
        #StoreFileOutput : StoreFileOutputType;
        #StoreFileMetadataOutput : StoreFileMetadataOutputType;
        #StoreFileChunkOutput : StoreFileChunkOutputType;
    };

    public type QueryOperationOutputType = {
        #GetFileOutput : GetFileOutputType;
        #GetFileIdsOutput : GetFileIdsOutputType;
    };

};