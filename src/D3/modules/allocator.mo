import Vector "mo:vector";
import Nat64 "mo:base/Nat64";
import BTree "mo:stableheapbtreemap/BTree";
import Filebase "../types/filebase";
import Utils "utils";
import Debug "mo:base/Debug";

module {
    // Helper to add a block to both free list maps.
    public func addToFreeLists(
        storageRegion : Filebase.StorageRegion,
        block : Filebase.FreeBlock,
    ) {
        let { offset; size } = block;

        ignore BTree.insert(storageRegion.freeBlocksByOffset, Utils.nat64_compare, offset, size);

        let updateFunc = func(offsetsVecOpt : ?Vector.Vector<Nat64>) : Vector.Vector<Nat64> {
            let vec = switch (offsetsVecOpt) {
                case null { Vector.new<Nat64>() };
                case (?v) { v };
            };
            Vector.add(vec, offset);
            return vec;
        };
        ignore BTree.update(storageRegion.freeListBySize, Utils.nat64_compare, size, updateFunc);
    };

    // Helper to remove a block from both free list maps.
    // It's the caller's responsibility to ensure the block exists in freeBlocksByOffset.
    public func removeFromFreeLists(
        storageRegion : Filebase.StorageRegion,
        offset : Nat64,
        size : Nat64,
    ) {
        // 1. Remove from the offset map.
        ignore BTree.delete(storageRegion.freeBlocksByOffset, Utils.nat64_compare, offset);

        // 2. Remove from the size map.
        switch (BTree.get(storageRegion.freeListBySize, Utils.nat64_compare, size)) {
            case null {
                // This indicates a data inconsistency, as the block existed in the offset map.
                Debug.trap("CRITICAL INVARIANT VIOLATED: Block found in freeBlocksByOffset but not in freeListBySize. Offset: " # Nat64.toText(offset) # ", Size: " # Nat64.toText(size));
            };
            case (?offsetsVec) {
                if (Vector.size(offsetsVec) == 1) {
                    // This is the last block of this size, remove the entire entry.
                    ignore BTree.delete(storageRegion.freeListBySize, Utils.nat64_compare, size);
                } else {
                    // Find the offset and remove it using the efficient swap-and-pop method.
                    var i : Nat = 0;
                    var foundIdx : ?Nat = null;
                    for (vec_offset in Vector.vals(offsetsVec)) {
                        if (vec_offset == offset) {
                            foundIdx := ?i;
                        };
                        i += 1;
                    };
                    switch (foundIdx) {
                        case null {
                            // If we never found the offset, it's an invariant violation.
                            Debug.trap("CRITICAL INVARIANT VIOLATED: Block size category exists, but offset not found in vector. Offset: " # Nat64.toText(offset));
                        };
                        case (?idx) {
                            // Use the efficient swap-and-pop method.
                            let lastIdx = Vector.size(offsetsVec) - 1;
                            if (idx < lastIdx) {
                                // Swap the found element with the last element.
                                Vector.put(offsetsVec, idx, Vector.get(offsetsVec, lastIdx));
                            };
                            // Remove the last element (which is either the original last, or our swapped element).
                            ignore Vector.removeLast(offsetsVec);
                        };
                    };
                };
            };
        };
    };
};
