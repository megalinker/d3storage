import Map "mo:map/Map";
import Region "mo:base/Region";

module {

    ////////////////////////////////////////////////////////////////////////////

    public type FileId = Text;
    public type RegionId = Nat;

    public type StorageRegion = {
        var offset : Nat64;
        region : Region;
    };

    public type FileLocation = {
        regionId : Nat;
        offset : Nat64;
        fileName : Text;
        fileType : Text;
    };

    public let PAGE_SIZE : Nat64 = 65536;
    public let REGION_ID : Nat = 16;
    public let CHUNK_SIZE : Nat64 = 1_800_000;    // ~1.8MB

    ////////////////////////////////////////////////////////////////////////////

    public class D3() {
        public let storageRegionMap : Map.Map<RegionId, StorageRegion> = Map.new();
        public let fileLocationMap : Map.Map<FileId, FileLocation> = Map.new();
    };

}