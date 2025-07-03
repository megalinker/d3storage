//--- File: src/D3/modules/delete.mo ---

import StableTrieMap "../utils/StableTrieMap";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Filebase "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Utils "utils";
import BTree "mo:stableheapbtreemap/BTree";
import Allocator "allocator";

module {
    public func deleteFile({
        d3 : Filebase.D3;
        deleteFileInput : InputTypes.DeleteFileInputType;
    }) : OutputTypes.DeleteFileOutputType {
        let { fileId } = deleteFileInput;

        let ?fileLocation = BTree.get(d3.fileLocationMap, Text.compare, fileId) else {
            return { success = false; error = ?"File not found." };
        };

        let ?storageRegion = StableTrieMap.get(d3.storageRegionMap, Utils.nat_eq, Utils.hashNat, fileLocation.regionId) else {
            return {
                success = false;
                error = ?"Internal Error: Storage region for file not found.";
            };
        };

        var blockToCoalesce : Filebase.FreeBlock = {
            offset = fileLocation.offset;
            size = fileLocation.totalAllocatedSize;
        };

        // 1. Check for a free block immediately to the RIGHT of our new block.
        let rightNeighborOffset = Utils.checked_add(blockToCoalesce.offset, blockToCoalesce.size);
        switch (BTree.get(storageRegion.freeBlocksByOffset, Utils.nat64_compare, rightNeighborOffset)) {
            case null { /* No right neighbor to merge with */ };
            case (?rightNeighborSize) {
                // Found a right neighbor. Merge it into our current block.
                Allocator.removeFromFreeLists(storageRegion, rightNeighborOffset, rightNeighborSize);
                blockToCoalesce := {
                    offset = blockToCoalesce.offset;
                    size = blockToCoalesce.size + rightNeighborSize;
                };
            };
        };

        // 2. Check for a free block immediately to the LEFT of our new block.
        // To do this, we scan backwards from our block's offset with a limit of 1.
        let scanResult = BTree.scanLimit<Nat64, Nat64>(
            storageRegion.freeBlocksByOffset,
            Utils.nat64_compare,
            0, // lower bound
            blockToCoalesce.offset, // upper bound
            #bwd, // direction
            1 // limit
        );

        if (scanResult.results.size() > 0) {
            let (leftOffset, leftSize) = scanResult.results[0];
            if (Utils.checked_add(leftOffset, leftSize) == blockToCoalesce.offset) {
                // Found an adjacent left neighbor. Merge our block into it.
                // First, remove the old left block from the maps.
                Allocator.removeFromFreeLists(storageRegion, leftOffset, leftSize);

                // Then, update our block's offset and size.
                blockToCoalesce := {
                    offset = leftOffset;
                    size = Utils.checked_add(blockToCoalesce.size, leftSize);
                };
            };
        };

        // 3. Add the final (potentially merged) block back to the free lists.
        Allocator.addToFreeLists(storageRegion, blockToCoalesce);

        // Finally, remove the file from the location map.
        ignore BTree.delete(d3.fileLocationMap, Text.compare, fileId);

        return { success = true; error = null };
    };
};
