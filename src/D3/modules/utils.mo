import XorShift "mo:rand/XorShift";
import ULIDSource "mo:ulid/Source";
import ULID "mo:ulid/ULID";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Prim "mo:prim";
import Text "mo:base/Text";
import Debug "mo:base/Debug";

module {
    // --- ID Generation ---
    public func generateULIDSync() : Text {
        return ULID.toText(ULIDSource.Source(XorShift.toReader(XorShift.XorShift64(null)), Nat64.fromIntWrap(Time.now())).new());
    };

    // --- Hashing Functions ---
    public func hashNat(key : Nat) : Nat32 {
        var hash = Prim.intToNat64Wrap(key);
        hash := (hash >> 30) ^ (hash *% 0xbf58476d1ce4e5b9);
        hash := (hash >> 27) ^ (hash *% 0x94d049bb133111eb);
        return Prim.nat64ToNat32(hash >> 31 ^ hash & 0x3fffffff);
    };

    // --- Safe Math Functions ---
    public func checked_add(a : Nat64, b : Nat64) : Nat64 {
        if (0xFFFFFFFFFFFFFFFF - a < b) {
            Debug.trap(
                "CRITICAL: Nat64 addition overflow detected. a="
                # Nat64.toText(a) # ", b=" # Nat64.toText(b)
            );
        };
        return a + b;
    };

    public func round_up_to_8(n : Nat64) : Nat64 {
        return (n + 7) & (Nat64.fromNat(7) ^ 0xFFFFFFFFFFFFFFFF);
    };

    // --- Comparison Functions ---
    public let nat_eq = func(a : Nat, b : Nat) : Bool { a == b };
    public let nat64_compare = Nat64.compare;
};
