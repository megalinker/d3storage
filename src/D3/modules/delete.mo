import Map "mo:map/Map";
import { nhash; thash } "mo:map/Map";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Order "mo:base/Order";
import Nat64 "mo:base/Nat64";
import Filebase "../types/filebase";
import InputTypes "../types/input";
import OutputTypes "../types/output";

module {

    private func _compareFreeBlocks(a : Filebase.FreeBlock, b : Filebase.FreeBlock) : Order.Order {
        return Nat64.compare(a.offset, b.offset);
    };

    private func _coalesceFreeList(storageRegion : Filebase.StorageRegion) {
        if (storageRegion.freeList.size() <= 1) {
            return;
        };

        // 1. Convert buffer to an array and sort it.
        let sortedFreeList = Array.sort<Filebase.FreeBlock>(
            Buffer.toArray(storageRegion.freeList),
            _compareFreeBlocks,
        );

        // 2. Iterate and merge, building a new list of blocks.
        let mergedList = Buffer.Buffer<Filebase.FreeBlock>(sortedFreeList.size());

        if (sortedFreeList.size() > 0) {
            // Start with the first block from the sorted list.
            var currentOffset = sortedFreeList[0].offset;
            var currentSize = sortedFreeList[0].size;

            // Loop from the second element (index 1) onwards.
            var i = 1;
            while (i < sortedFreeList.size()) {
                let nextBlock = sortedFreeList[i];

                // Check for adjacency.
                if (currentOffset + currentSize == nextBlock.offset) {
                    // It's adjacent. Merge by extending the current size.
                    currentSize := currentSize + nextBlock.size;
                } else {
                    // Not adjacent. The merged block is complete. Add it to the list.
                    mergedList.add({
                        offset = currentOffset;
                        size = currentSize;
                    });
                    // Start a new block from the nextBlock.
                    currentOffset := nextBlock.offset;
                    currentSize := nextBlock.size;
                };
                i += 1;
            };

            // After the loop, the last merged block is still in our variables. Add it.
            mergedList.add({ offset = currentOffset; size = currentSize });
        };

        // 3. Replace the old free list with the new, merged one.
        storageRegion.freeList := mergedList;
    };

    public func deleteFile({
        d3 : Filebase.D3;
        deleteFileInput : InputTypes.DeleteFileInputType;
    }) : OutputTypes.DeleteFileOutputType {

        let { fileId } = deleteFileInput;
        let fileLocationMap = d3.fileLocationMap;

        let fileLocation = switch (Map.get(fileLocationMap, thash, fileId)) {
            case (null) {
                return {
                    success = false;
                    error = ?"File not found.";
                };
            };
            case (?loc) { loc };
        };

        switch (Map.get(d3.storageRegionMap, nhash, fileLocation.regionId)) {
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

                storageRegion.freeList.add(newFreeBlock);

                _coalesceFreeList(storageRegion);

                Map.delete(fileLocationMap, thash, fileId);

                return {
                    success = true;
                    error = null;
                };
            };
        };
    };
};
