// -----------------------------------------------------------------------------
// Property-based allocator tests for the D3 storage layer
// -----------------------------------------------------------------------------
import Nat64 "mo:base/Nat64";
import Random "mo:base/Random";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Region "mo:base/Region";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import BTree "mo:stableheapbtreemap/BTree";
import Vector "mo:vector";
import D3 "../D3";
import Filebase "../D3/types/filebase";
import StableTrieMap "../D3/utils/StableTrieMap";
import Utils "../D3/modules/utils";

module Property {
    // ---------------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------------
    let MAX_FILES : Nat = 60;
    let CHAOTIC_OPERATIONS : Nat = 200; // Number of random add/delete operations

    let nat_eq = func(a : Nat, b : Nat) : Bool { a == b };

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    func randNat64(rand : Random.Finite, min : Nat64, max : Nat64) : Nat64 {
        // This implementation can be improved for larger ranges, but is fine for testing.
        let span = max - min + 1;
        switch (rand.range(32)) {
            case (?v) { min + Nat64.fromNat(v % Nat64.toNat(span)) };
            case null { Debug.trap("entropy exhausted in randNat64") };
        };
    };

    func mkBlob(size : Nat) : Blob {
        // Creating a large zeroed blob can be slow. For testing, a small blob is often enough.
        // If performance is an issue, consider creating smaller blobs.
        let arr = Array.tabulate<Nat8>(size, func _ { 0 });
        Blob.fromArray(arr);
    };

    // ====================================================================
    // === CHANGE: checkRegion is updated to use the new B-Tree Map     ===
    // === data structures for the free list.                           ===
    // ====================================================================
    public func checkRegion(d3 : D3.D3, regionId : Filebase.RegionId) {
        let ?storageRegion = StableTrieMap.get(d3.storageRegionMap, nat_eq, Utils.hashNat, regionId) else Debug.trap("missing region " # Int.toText(regionId));

        let capacity : Nat64 = Region.size(storageRegion.region) * Filebase.PAGE_SIZE;
        let tailSpace : Nat64 = capacity - storageRegion.offset;

        // Calculate the sum of all free blocks by iterating the offset map.
        var freeSum : Nat64 = 0;
        for ((_, blkSize) in BTree.entries(storageRegion.freeBlocksByOffset)) {
            freeSum += blkSize;
        };

        // Calculate the sum of all live files in this region.
        var liveSum : Nat64 = 0;
        for ((_, loc) in BTree.entries(d3.fileLocationMap)) {
            if (loc.regionId == regionId) {
                liveSum += loc.totalAllocatedSize;
            };
        };

        if (freeSum + tailSpace + liveSum != capacity) {
            Debug.print("---- Region State (ID: " # Nat.toText(regionId) # ") ----");
            Debug.print("Region Capacity: " # Nat64.toText(capacity));
            Debug.print("  - Used by Files (liveSum): " # Nat64.toText(liveSum));
            Debug.print("  - In Free List (freeSum): " # Nat64.toText(freeSum));
            Debug.print("  - Unallocated Tail Space: " # Nat64.toText(tailSpace));
            Debug.print("  - Total Accounted For: " # Nat64.toText(freeSum + tailSpace + liveSum));

            Debug.print("\nFree Blocks By Offset (" # Nat.toText(BTree.size(storageRegion.freeBlocksByOffset)) # " blocks):");
            for ((off, siz) in BTree.entries(storageRegion.freeBlocksByOffset)) {
                Debug.print("  - offset: " # Nat64.toText(off) # ", size: " # Nat64.toText(siz));
            };

            Debug.trap(
                "Invariant failed in region " # Int.toText(regionId) # ":\n" #
                "  (freeSum + tailSpace + liveSum) != capacity"
            );
        };

        var totalOffsetsInSizeMap : Nat = 0;
        for ((_, vec) in BTree.entries(storageRegion.freeListBySize)) {
            totalOffsetsInSizeMap += Vector.size(vec);
        };

        if (totalOffsetsInSizeMap != BTree.size(storageRegion.freeBlocksByOffset)) {
            Debug.trap(
                "CRITICAL INVARIANT FAILED: Mismatch in free block counts.\n" #
                "  - Count in freeBlocksByOffset: " # Nat.toText(BTree.size(storageRegion.freeBlocksByOffset)) # "\n" #
                "  - Sum of counts in freeListBySize: " # Nat.toText(totalOffsetsInSizeMap)
            );
        };

        for ((offset, size) in BTree.entries(storageRegion.freeBlocksByOffset)) {

            switch (BTree.get(storageRegion.freeListBySize, Utils.nat64_compare, size)) {
                case null {
                    Debug.trap("CRITICAL INVARIANT FAILED: Block (offset: " # Nat64.toText(offset) # ", size: " # Nat64.toText(size) # ") exists in offset map but its size category is missing from size map.");
                };
                case (?offsetsVec) {
                    var found = false;

                    for (off in Vector.vals(offsetsVec)) {
                        if (off == offset) {
                            found := true;
                        };
                    };
                    if (not found) {
                        Debug.trap("CRITICAL INVARIANT FAILED: Block (offset: " # Nat64.toText(offset) # ") not found in its corresponding size vector in freeListBySize.");
                    };
                };
            };
        };
    };

    public func checkAllRegions(d3 : D3.D3) {
        for (regionId in StableTrieMap.keys(d3.storageRegionMap)) {
            checkRegion(d3, regionId);
        };
    };

    public func runChaoticScenario(d3 : D3.D3, rand : Random.Finite) : async () {
        Debug.print("--- Starting Chaotic Allocator Scenario ---");
        var liveFiles = Buffer.Buffer<Text>(MAX_FILES);

        for (i in Iter.range(0, CHAOTIC_OPERATIONS - 1)) {
            let rand_even = switch (rand.range(1)) {
                case (?v) { v % 2 == 0 };
                case (null) { true };
            };
            let should_add = liveFiles.size() == 0 or (liveFiles.size() < MAX_FILES and rand_even);

            if (should_add) {
                // Add a file
                let size : Nat64 = randNat64(rand, 1, 2 * Filebase.CHUNK_SIZE);
                Debug.print("Chaotic run (" # Nat.toText(i) # "): Adding file of size " # Nat64.toText(size));
                let resp = await D3.storeFile({
                    d3;
                    storeFileInput = {
                        fileDataObject = mkBlob(Nat64.toNat(size));
                        fileName = "chaos" # Nat.toText(i);
                        fileType = "application/octet-stream";
                    };
                });
                liveFiles.add(resp.fileId);
            } else {
                // Delete a file
                let ixToDelete = switch (rand.range(16)) {
                    case (?v) { v % liveFiles.size() };
                    case null { 0 };
                };
                let fileIdToDelete = liveFiles.get(ixToDelete);
                Debug.print("Chaotic run (" # Nat.toText(i) # "): Deleting file " # fileIdToDelete);

                // Use efficient swap-and-pop to remove from buffer
                let lastIx = liveFiles.size() - 1;
                if (ixToDelete != lastIx) {
                    let lastVal = liveFiles.get(lastIx);
                    liveFiles.put(ixToDelete, lastVal);
                };
                ignore liveFiles.removeLast();

                ignore D3.deleteFile({
                    d3;
                    deleteFileInput = { fileId = fileIdToDelete };
                });
            };

            // CRITICAL: Check invariants after every single operation.
            checkAllRegions(d3);
        };
        Debug.print("--- Chaotic Allocator Scenario Passed ---");
    };
};
