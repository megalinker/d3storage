
module {

    public type StoreFileInputType = {
        fileDataObject : Blob;
        fileName : Text;
        fileType : Text;
    };

    public type StoreFileMetadataInputType = {
        fileSizeInBytes : Nat64;
        fileName : Text;
        fileType : Text;
    };

    public type StoreFileChunkInputType = {
        fileId : Text;
        chunkData : Blob;
        chunkIndex : Nat64;
    };

    public type GetFileInputType = {
        fileId : Text;
    };

    public type GetFileIdsInputType = {};

    public type UpdateOperationInputType = {
        #StoreFile : StoreFileInputType;
        #StoreFileMetadata : StoreFileMetadataInputType;
        #StoreFileChunk : StoreFileChunkInputType;
    };

    public type QueryOperationInputType = {
        #GetFile : GetFileInputType;
        #GetFileIds : GetFileIdsInputType;
    };
};