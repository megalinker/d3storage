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
import D3 "../D3";
import Filebase "../D3/types/filebase";
import StableTrieMap "../D3/utils/StableTrieMap";
import Vector "mo:vector";
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
        let span = max - min + 1;
        switch (rand.range(32)) {
            case (?v) { min + Nat64.fromNat(v % Nat64.toNat(span)) };
            case null { Debug.trap("entropy exhausted in randNat64") };
        };
    };

    func mkBlob(size : Nat) : Blob {
        let arr = Array.tabulate<Nat8>(size, func _ { 0 });
        Blob.fromArray(arr);
    };

    public func checkRegion(d3 : D3.D3, regionId : Filebase.RegionId) {
        let ?storageRegion = StableTrieMap.get(d3.storageRegionMap, nat_eq, Utils.hashNat, regionId) else Debug.trap("missing region " # Int.toText(regionId));

        let capacity : Nat64 = Region.size(storageRegion.region) * Filebase.PAGE_SIZE;
        let tailSpace : Nat64 = capacity - storageRegion.offset;

        var freeSum : Nat64 = 0;
        for (blk in Vector.vals(storageRegion.freeList)) {
            freeSum += blk.size;
        };

        var liveSum : Nat64 = 0;
        for ((_, loc) in StableTrieMap.entries(d3.fileLocationMap)) {
            if (loc.regionId == regionId) {
                liveSum += loc.totalAllocatedSize;
            };
        };

        if (freeSum + tailSpace + liveSum != capacity) {
            Debug.print("---- Region State ----");
            Debug.print("Offset: " # Nat64.toText(storageRegion.offset));
            Debug.print("Capacity: " # Nat64.toText(capacity));
            Debug.print("Free List (" # Nat.toText(Vector.size(storageRegion.freeList)) # " blocks):");
            for (blk in Vector.vals(storageRegion.freeList)) {
                Debug.print("  - offset: " # Nat64.toText(blk.offset) # ", size: " # Nat64.toText(blk.size));
            };
            Debug.trap(
                "Invariant failed in region " # Int.toText(regionId) # ":\n" #
                "  freeSum=" # Nat64.toText(freeSum) #
                ", tailSpace=" # Nat64.toText(tailSpace) #
                ", liveSum=" # Nat64.toText(liveSum) # "\n" #
                "  TOTAL=" # Nat64.toText(freeSum + tailSpace + liveSum) #
                ", but capacity=" # Nat64.toText(capacity)
            );
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
            let should_add = switch (rand.range(1)) {
                case (?v) { v % 2 == 0 };
                case null { true };
            };

            if (should_add and liveFiles.size() < MAX_FILES) {
                // Add a file
                let size : Nat64 = randNat64(rand, 1, 2 * Filebase.CHUNK_SIZE);
                Debug.print("Chaotic run: Adding file of size " # Nat64.toText(size));
                let resp = await D3.storeFile({
                    d3;
                    storeFileInput = {
                        fileDataObject = mkBlob(Nat64.toNat(size));
                        fileName = "chaos" # Nat.toText(i);
                        fileType = "application/octet-stream";
                    };
                });
                liveFiles.add(resp.fileId);
            } else if (liveFiles.size() > 0) {
                // Delete a file
                let ixToDelete = switch (rand.range(16)) {
                    case (?v) { v % liveFiles.size() };
                    case null { 0 };
                };
                let fileIdToDelete = liveFiles.get(ixToDelete);
                Debug.print("Chaotic run: Deleting file " # fileIdToDelete);

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
