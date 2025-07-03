import BTree "mo:stableheapbtreemap/BTree";
import Region "mo:base/Region";
import Time "mo:base/Time";
import Vector "mo:vector";
import StableTrieMap "../utils/StableTrieMap";

module {
    public type FileId = Text;
    public type RegionId = Nat;

    public type FreeBlock = {
        offset : Nat64;
        size : Nat64;
    };

    public type OffsetMap = BTree.BTree<Nat64, Nat64>;
    public type SizeMap = BTree.BTree<Nat64, Vector.Vector<Nat64>>;

    public type StorageRegion = {
        var offset : Nat64;
        region : Region.Region;
        var freeBlocksByOffset : OffsetMap;
        var freeListBySize : SizeMap;
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

    public type FileLocationMap = BTree.BTree<FileId, FileLocation>;

    public let PAGE_SIZE : Nat64 = 65536;
    public let CHUNK_SIZE : Nat64 = 1_800_000;

    public class D3() {
        public var storageRegionMap : StableTrieMap.StableTrieMap<RegionId, StorageRegion> = StableTrieMap.new();
        public var fileLocationMap : FileLocationMap = BTree.init<FileId, FileLocation>(null);
        public var nextRegionId : RegionId = 0;
        public var bytesAllocated : Nat64 = 0;
        public let BYTES_BUDGET : Nat64 = 3_758_096_384;
    };
};
