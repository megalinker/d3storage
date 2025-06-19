import Map "mo:map/Map";
import Region "mo:base/Region";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";

module {
    public type FileId = Text;
    public type RegionId = Nat;

    public type FreeBlock = {
        offset : Nat64;
        size : Nat64;
    };

    public type StorageRegion = {
        var offset : Nat64;
        region : Region;
        var freeList : Buffer.Buffer<FreeBlock>;
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
        public let storageRegionMap : Map.Map<RegionId, StorageRegion> = Map.new();
        public let fileLocationMap : Map.Map<FileId, FileLocation> = Map.new();
        public var nextRegionId : RegionId = 0;
    };
};
