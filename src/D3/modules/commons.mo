import Filebase "../types/filebase";

module {

    public func evaluateNumOfChunks({ fileSizeInBytes : Nat64 }) : Nat64 {

        let reminderBytes = fileSizeInBytes % Filebase.CHUNK_SIZE;
        var numOfChunks = (fileSizeInBytes - reminderBytes) / Filebase.CHUNK_SIZE;
        if (reminderBytes > 0) {
            numOfChunks := numOfChunks + 1;
        };
        return numOfChunks;
    };

    public func evaluateChunkSize({ chunkIndex : Nat64; numOfChunks : Nat64; fileSizeInBytes : Nat64 }) : Nat64 {

        if (chunkIndex < numOfChunks - 1) {
            return Filebase.CHUNK_SIZE;
        } else {
            return fileSizeInBytes % Filebase.CHUNK_SIZE;
        };
    };

};