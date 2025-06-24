import XorShift "mo:rand/XorShift";
import ULIDSource "mo:ulid/Source";
import ULID "mo:ulid/ULID";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Prim "mo:prim";
module {

    public func generateULIDSync() : Text {
        return ULID.toText(ULIDSource.Source(XorShift.toReader(XorShift.XorShift64(null)), Nat64.fromIntWrap(Time.now())).new());
    };

    public func hashNat(key : Nat) : Nat32 {
        var hash = Prim.intToNat64Wrap(key);
        hash := (hash >> 30) ^ (hash *% 0xbf58476d1ce4e5b9);
        hash := (hash >> 27) ^ (hash *% 0x94d049bb133111eb);

        return Prim.nat64ToNat32(hash >> 31 ^ hash & 0x3fffffff);
    };
};
