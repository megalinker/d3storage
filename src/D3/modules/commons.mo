import Filebase "../types/filebase";

module {

    public func evaluateNumOfChunks({ fileSizeInBytes : Nat64 }) : Nat64 {
        if (fileSizeInBytes == 0) { return 0 };

        return (fileSizeInBytes + Filebase.CHUNK_SIZE - 1) / Filebase.CHUNK_SIZE;
    };

    public func evaluateChunkSize({
        chunkIndex : Nat64;
        numOfChunks : Nat64;
        fileSizeInBytes : Nat64;
    }) : Nat64 {

        if (chunkIndex < numOfChunks - 1) {
            return Filebase.CHUNK_SIZE;
        };

        let remainder = fileSizeInBytes % Filebase.CHUNK_SIZE;

        if (remainder == 0) Filebase.CHUNK_SIZE else remainder;
    };
};
