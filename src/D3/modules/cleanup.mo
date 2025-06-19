import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Array "mo:base/Array";
import Filebase "../types/filebase";
import Delete "delete";

module {

    public type CleanupStats = {
        scanned : Nat;
        reclaimed : Nat;
        bytesFreed : Nat64;
    };

    // Deletes files that are in #Pending state for longer than the timeout period.
    public func cleanupAbandonedUploads({
        d3 : Filebase.D3;
        timeoutNanos : Nat64;
    }) : CleanupStats {

        let fileLocationMap = d3.fileLocationMap;
        let now = Time.now();
        var scanned : Nat = 0;
        var reclaimed : Nat = 0;
        var bytesFreed : Nat64 = 0;

        var fileIdsToDelete : [Text] = [];

        //======================================================================//
        // CORRECTED ITERATION WITH SAFE `switch` UNWRAPPING                    //
        //======================================================================//
        let iter = Map.entries(fileLocationMap);
        var currentEntry = iter.next();

        while (currentEntry != null) {
            switch (currentEntry) {
                case (null) {
                    // This case is technically handled by the while loop condition,
                    // but a full switch is the most robust pattern.
                };
                case (?entry) {
                    // `entry` is now the unwrapped tuple: (FileId, FileLocation)
                    let fileId = entry.0;
                    let fileLocation = entry.1;

                    // --- Your existing logic ---
                    scanned += 1;
                    switch (fileLocation.status) {
                        case (#Pending) {
                            let age = now - fileLocation.createdAt;
                            if (age > Int.abs(Nat64.toNat(timeoutNanos))) {
                                fileIdsToDelete := Array.append(fileIdsToDelete, [fileId]);
                                bytesFreed := bytesFreed + fileLocation.totalAllocatedSize;
                            };
                        };
                        case (#Complete) {
                            // Do nothing
                        };
                    };
                    // --- End of existing logic ---
                };
            };
            // Get the next entry for the next iteration.
            currentEntry := iter.next();
        };
        //======================================================================//

        // Deletion logic remains the same
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
