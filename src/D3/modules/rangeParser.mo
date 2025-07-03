import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";

module {
    public type Range = {
        start : Nat64;
        end : Nat64;
    };

    private func trimPrefix(text : Text, prefix : Text) : Text {
        if (Text.startsWith(text, #text prefix)) {
            var chars = text.chars();
            var i = prefix.size();
            while (i > 0) {
                ignore chars.next();
                i -= 1;
            };
            return Text.fromIter(chars);
        } else {
            return text;
        };
    };

    // Parses a "bytes=start-end" style Range header.
    // - "bytes=500-1000" -> {start=500, end=1000}
    // - "bytes=500-"     -> {start=500, end=fileSize-1}
    // Returns null for unsupported or invalid formats.
    public func parse(headerVal : Text, fileSize : Nat64) : ?Range {
        if (fileSize == 0) { return null };

        // 1. Check for the "bytes=" prefix.
        let prefix = "bytes=";
        if (not Text.startsWith(headerVal, #text prefix)) {
            return null;
        };

        // 2. Isolate the "start-end" part using our new helper.
        let rangeStr = trimPrefix(headerVal, prefix);

        // 3. Split by the hyphen.
        let parts = Iter.toArray(Text.split(rangeStr, #char '-'));
        let numParts = Array.size(parts);

        if (numParts == 0 or numParts > 2) {
            return null; // Invalid format
        };

        // 4. Parse the start part.
        let startText = parts[0];
        let startOpt = switch (Nat.fromText(startText)) {
            case (?startNat) {
                ?Nat64.fromNat(startNat);
            };
            case null { null };
        };
        let start = switch (startOpt) {
            case (?s) { s };
            case null {
                // Handle "-end" format (e.g., last 500 bytes)
                if (startText == "" and numParts == 2) {
                    let ?suffixNat = Nat.fromText(parts[1]) else {
                        return null;
                    };
                    let suffixLength = Nat64.fromNat(suffixNat);
                    if (suffixLength == 0) { return null };

                    let s = if (suffixLength > fileSize) { 0 : Nat64 } else {
                        fileSize - suffixLength;
                    };
                    return ?{ start = s; end = fileSize - 1 };
                };
                return null;
            };
        };

        // 5. Parse the end part.
        let endText = if (numParts == 2) { parts[1] } else { "" };
        var end : Nat64 = 0;

        if (endText == "") {
            // Format is "start-", so we go to the end of the file.
            end := fileSize - 1;
        } else {
            // Format is "start-end".
            let ?endNat = Nat.fromText(endText) else { return null };
            let e = Nat64.fromNat(endNat);
            end := e;
        };

        // 6. Final validation.
        if (start > end or start >= fileSize) {
            return null; // The requested range is logically invalid or entirely outside the file.
        };

        // The client-provided 'end' might be past the end of the file, so we clamp it.
        return ?{ start; end = Nat64.min(end, fileSize - 1) };
    };
};
