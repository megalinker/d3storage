import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import BTree "mo:stableheapbtreemap/BTree";
import Filebase "../types/filebase";
import Delete "delete";
import OutputTypes "../types/output";

module {

    public func cleanupAbandonedUploads({
        d3 : Filebase.D3;
        timeoutNanos : Nat64;
        startKey : ?Text;
        limit : Nat;
    }) : OutputTypes.CleanupStats {

        let now : Time.Time = Time.now();
        var scanned : Nat = 0;
        var reclaimed : Nat = 0;
        var bytesFreed : Nat64 = 0;

        let lowerBound = switch (startKey) {
            case null { "" };
            case (?key) { key };
        };

        let scanResult = BTree.scanLimit<Text, Filebase.FileLocation>(
            d3.fileLocationMap,
            Text.compare,
            lowerBound,
            "\u{FFFF}",
            #fwd,
            limit,
        );

        for ((fileId, fileLocation) in scanResult.results.vals()) {
            scanned += 1;

            switch (fileLocation.status) {
                case (#Pending) {
                    let age : Nat64 = Nat64.fromIntWrap(now - fileLocation.createdAt);
                    if (age > timeoutNanos) {
                        let deleteResult = Delete.deleteFile({
                            d3;
                            deleteFileInput = { fileId };
                        });
                        if (deleteResult.success) {
                            reclaimed += 1;
                            bytesFreed += fileLocation.totalAllocatedSize;
                        };
                    };
                };
                case (#Complete) {
                    // Do nothing
                };
            };
        };

        return {
            scanned;
            reclaimed;
            bytesFreed;
            nextKey = scanResult.nextKey;
        };
    };
};
