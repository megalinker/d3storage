import StableTrieMap "../utils/StableTrieMap";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Filebase "../types/filebase";
import Delete "delete";

module {

    public type CleanupStats = {
        scanned : Nat;
        reclaimed : Nat;
        bytesFreed : Nat64;
    };

    public func cleanupAbandonedUploads({
        d3 : Filebase.D3;
        timeoutNanos : Nat64;
    }) : CleanupStats {

        let fileLocationMap = d3.fileLocationMap;
        let now : Time.Time = Time.now();
        var scanned : Nat = 0;
        var reclaimed : Nat = 0;
        var bytesFreed : Nat64 = 0;

        let fileIdsToDelete = Buffer.Buffer<Text>(StableTrieMap.size(fileLocationMap));

        let iter = StableTrieMap.entries(fileLocationMap);

        for ((key, fileLocation) in iter) {
            let fileId = key;
            scanned += 1;

            switch (fileLocation.status) {
                case (#Pending) {
                    let age : Nat64 = Nat64.fromIntWrap(now - fileLocation.createdAt);
                    if (age > timeoutNanos) {
                        fileIdsToDelete.add(fileId);
                        bytesFreed += fileLocation.totalAllocatedSize;
                    };
                };
                case (#Complete) {
                    // Do nothing
                };
            };
        };

        for (fileId in fileIdsToDelete.vals()) {
            ignore Delete.deleteFile({
                d3;
                deleteFileInput = { fileId };
            });
            reclaimed += 1;
        };

        return { scanned; reclaimed; bytesFreed };
    };
};
