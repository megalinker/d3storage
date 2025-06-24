import StableTrieMap "../utils/StableTrieMap";
import Array "mo:base/Array";
import Order "mo:base/Order";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Vector "mo:vector";
import Filebase "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";
import Utils "utils";

module {

    let text_eq = Text.equal;
    let text_hash = Text.hash;
    let nat_eq = func(a : Nat, b : Nat) : Bool { a == b };

    private func _compareFreeBlocks(a : Filebase.FreeBlock, b : Filebase.FreeBlock) : Order.Order {
        return Nat64.compare(a.offset, b.offset);
    };

    private func _coalesceFreeList(storageRegion : Filebase.StorageRegion) {
        if (Vector.size(storageRegion.freeList) <= 1) {
            return;
        };

        let sortedFreeList = Array.sort<Filebase.FreeBlock>(
            Vector.toArray(storageRegion.freeList),
            _compareFreeBlocks,
        );

        let mergedList = Vector.new<Filebase.FreeBlock>();

        if (sortedFreeList.size() > 0) {
            var currentOffset = sortedFreeList[0].offset;
            var currentSize = sortedFreeList[0].size;

            var i = 1;
            while (i < sortedFreeList.size()) {
                let nextBlock = sortedFreeList[i];
                if (currentOffset + currentSize == nextBlock.offset) {
                    currentSize += nextBlock.size;
                } else {
                    Vector.add(
                        mergedList,
                        {
                            offset = currentOffset;
                            size = currentSize;
                        },
                    );
                    currentOffset := nextBlock.offset;
                    currentSize := nextBlock.size;
                };
                i += 1;
            };
            Vector.add(mergedList, { offset = currentOffset; size = currentSize });
        };

        storageRegion.freeList := mergedList;
    };

    public func coalesceFreeList(storageRegion : Filebase.StorageRegion) : () {
        _coalesceFreeList(storageRegion);
    };

    public func deleteFile({
        d3 : Filebase.D3;
        deleteFileInput : InputTypes.DeleteFileInputType;
    }) : OutputTypes.DeleteFileOutputType {

        let { fileId } = deleteFileInput;

        let fileLocation = switch (StableTrieMap.get(d3.fileLocationMap, text_eq, text_hash, fileId)) {
            case (null) {
                return { success = false; error = ?"File not found." };
            };
            case (?loc) { loc };
        };

        switch (StableTrieMap.get(d3.storageRegionMap, nat_eq, Utils.hashNat, fileLocation.regionId)) {
            case (null) {
                return {
                    success = false;
                    error = ?"Internal Error: Storage region for file not found.";
                };
            };
            case (?storageRegion) {
                let newFreeBlock : Filebase.FreeBlock = {
                    offset = fileLocation.offset;
                    size = fileLocation.totalAllocatedSize;
                };

                Vector.add(storageRegion.freeList, newFreeBlock);

                _coalesceFreeList(storageRegion);

                StableTrieMap.delete(d3.fileLocationMap, text_eq, text_hash, fileId);

                return { success = true; error = null };
            };
        };
    };
};
