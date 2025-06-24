import StableTrieMap "../utils/StableTrieMap";
import Region "mo:base/Region";
import Time "mo:base/Time";
import Vector "mo:vector";

module {
    public type FileId = Text;
    public type RegionId = Nat;

    public type FreeBlock = {
        offset : Nat64;
        size : Nat64;
    };

    public type StorageRegion = {
        var offset : Nat64;
        region : Region.Region;
        var freeList : Vector.Vector<FreeBlock>;
    };

    public type FileStatus = {
        #Pending;
        #Complete;
    };

    public type FileLocation = {
        regionId : RegionId;
        offset : Nat64;
        totalAllocatedSize : Nat64;
        fileName : Text;
        fileType : Text;
        createdAt : Time.Time;
        status : FileStatus;
    };

    public let PAGE_SIZE : Nat64 = 65536;
    public let CHUNK_SIZE : Nat64 = 1_800_000;

    public class D3() {
        public var storageRegionMap : StableTrieMap.StableTrieMap<RegionId, StorageRegion> = StableTrieMap.new();
        public var fileLocationMap : StableTrieMap.StableTrieMap<FileId, FileLocation> = StableTrieMap.new();
        public var nextRegionId : RegionId = 0;
        public var bytesAllocated : Nat64 = 0;
        public let BYTES_BUDGET : Nat64 = 3_758_096_384;
    };
};
