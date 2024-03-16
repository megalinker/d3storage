import XorShift "mo:rand/XorShift";
import ULIDSource "mo:ulid/Source";
import ULID "mo:ulid/ULID";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";

module {

    public func generateULIDSync() : Text {
        return ULID.toText(ULIDSource.Source(XorShift.toReader(XorShift.XorShift64(null)), Nat64.fromIntWrap(Time.now())).new());
    };

};