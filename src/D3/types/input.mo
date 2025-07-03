module {

    ///////////////////////////// UPDATE OPERATIONS ////////////////////////

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

    public type DeleteFileInputType = {
        fileId : Text;
    };

    ///////////////////////////// QUERY OPERATIONS ////////////////////////

    public type GetFileMetadataInputType = {
        fileId : Text;
    };

    public type GetFileInputType = {
        fileId : Text;
    };

    public type GetFileIdsInputType = {};

    public type CleanupAbandonedUploadsInputType = {
        timeoutNanos : Nat64;
        startKey : ?Text;
        limit : Nat;
    };

    public type UpdateOperationInputType = {
        #StoreFile : StoreFileInputType;
        #StoreFileMetadata : StoreFileMetadataInputType;
        #StoreFileChunk : StoreFileChunkInputType;
        #DeleteFile : DeleteFileInputType;
        #CleanupAbandonedUploads : CleanupAbandonedUploadsInputType;
    };

    public type QueryOperationInputType = {
        #GetFileMetadata : GetFileMetadataInputType;
        #GetFile : GetFileInputType;
        #GetFileIds : GetFileIdsInputType;
    };

    //////////////////////////////////////////////////////////////////////

};
