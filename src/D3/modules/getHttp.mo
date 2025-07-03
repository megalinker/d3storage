import Filebase "../types/filebase";
import StorageClasses "../storageClasses";
import HttpTypes "../types/http";
import HttpParser "mo:httpParser";
import Array "mo:base/Array";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Get "get";
import RangeParser "rangeParser";

module {
    let { NTDO } = StorageClasses;

    public func getFileHTTP({
        d3 : Filebase.D3;
        httpRequest : HttpTypes.HttpRequest;
        httpStreamingCallbackActor : HttpTypes.HttpStreamingCallbackActor;
    }) : HttpTypes.HttpResponse {
        let { method; url } = HttpParser.parse(httpRequest);
        let { path; queryObj } = url;

        if (method != "GET") {
            return {
                status_code = 405; // Method Not Allowed
                headers = [];
                body = "Method Not Allowed" : Blob;
                streaming_strategy = null;
            };
        };

        if (Array.size(path.array) != 1 or path.array[0] != "d3") {
            return {
                status_code = 404; // Not Found
                headers = [];
                body = "Not Found: Invalid path" : Blob;
                streaming_strategy = null;
            };
        };

        let fileId = switch (queryObj.get("file_id")) {
            case (null) {
                return {
                    status_code = 400; // Bad Request
                    headers = [];
                    body = "Bad Request: Missing 'file_id' query parameter" : Blob;
                    streaming_strategy = null;
                };
            };
            case (?id) { id };
        };

        switch (Get._getFileAndRegion(d3, fileId)) {
            case (null) {
                return {
                    status_code = 404;
                    headers = [];
                    body = "Not Found: File with the specified file_id does not exist or its region is missing" : Blob;
                    streaming_strategy = null;
                };
            };
            case (?{ fileLocation; storageRegion }) {
                let offset = fileLocation.offset;
                let region = storageRegion.region;

                // Load file metadata from the region
                let fileSize = Region.loadNat64(region, offset + NTDO.getFileSizeRelativeOffset());
                let fileNameSize = Region.loadNat64(region, offset + NTDO.getFileNameSizeRelativeOffset());
                let fileTypeSize = Region.loadNat64(region, offset + NTDO.getFileTypeSizeRelativeOffset());
                let fileType = switch (Text.decodeUtf8(Region.loadBlob(region, offset + NTDO.getFileTypeRelativeOffset({ fileSize; fileNameSize }), Nat64.toNat(fileTypeSize)))) {
                    case (null) {
                        return {
                            status_code = 500;
                            headers = [];
                            body = "Internal Server Error: Corrupted file_type data" : Blob;
                            streaming_strategy = null;
                        };
                    };
                    case (?typ) { typ };
                };

                // Check for a Range header in the request
                var rangeHeaderVal : ?Text = null;
                for ((name, value) in httpRequest.headers.vals()) {
                    if (Text.toLowercase(name) == "range") {
                        rangeHeaderVal := ?value;
                    };
                };

                // Try to parse the range header
                let parsedRange = switch (rangeHeaderVal) {
                    case null { null };
                    case (?val) { RangeParser.parse(val, fileSize) };
                };

                switch (parsedRange) {
                    case (?{ start; end }) {
                        // --- BRANCH 1: VALID RANGE REQUEST ---
                        // Serve a partial file slice.

                        let lengthToLoad = end - start + 1;

                        // This check is technically redundant if the parser is correct, but it's good for safety.
                        if (start >= fileSize or lengthToLoad <= 0) {
                            return {
                                status_code = 416; // Range Not Satisfiable
                                headers = [("Content-Range", "bytes */" # Nat64.toText(fileSize))];
                                body = "" : Blob;
                                streaming_strategy = null;
                            };
                        };

                        // Calculate the exact offset of the data slice in the region
                        let dataSliceOffset = fileLocation.offset + NTDO.getFileDataRelativeoffset() + start;
                        let partialBody = Region.loadBlob(storageRegion.region, dataSliceOffset, Nat64.toNat(lengthToLoad));

                        let responseHeaders = [
                            ("Content-Type", fileType),
                            ("Accept-Ranges", "bytes"),
                            ("Content-Length", Nat64.toText(lengthToLoad)),
                            ("Content-Range", "bytes " # Nat64.toText(start) # "-" # Nat64.toText(end) # "/" # Nat64.toText(fileSize)),
                        ];

                        return {
                            status_code = 206; // Partial Content
                            headers = responseHeaders;
                            body = partialBody;
                            streaming_strategy = null; // No streaming for a specific range request
                        };
                    };

                    case (null) {
                        // --- BRANCH 2: NO (OR INVALID) RANGE REQUEST ---
                        // Serve the file from the beginning using the streaming strategy.

                        let fileChunkSize = Nat64.min(fileSize, Filebase.CHUNK_SIZE);
                        let chunkData = Region.loadBlob(region, offset + NTDO.getFileDataRelativeoffset(), Nat64.toNat(fileChunkSize));
                        let remainingSizeAfterChunking = fileSize - fileChunkSize;

                        var responseHeaders : [(Text, Text)] = [];
                        var streamingStrategy : ?HttpTypes.StreamingStrategy = null;

                        // Advertise that we accept range requests
                        responseHeaders := [("Accept-Ranges", "bytes"), ("Content-Type", fileType)];

                        if (remainingSizeAfterChunking > 0) {
                            streamingStrategy := ?#Callback({
                                token = {
                                    file_id = fileId;
                                    file_size = fileSize;
                                    index = 1;
                                    chunk_size = Filebase.CHUNK_SIZE;
                                };
                                callback = httpStreamingCallbackActor.http_request_streaming_callback;
                            });
                            // Add Transfer-Encoding for streaming responses
                            responseHeaders := Array.append(responseHeaders, [("Transfer-Encoding", "chunked")]);
                        } else {
                            // If the whole file fits in one chunk, send Content-Length
                            responseHeaders := Array.append(responseHeaders, [("Content-Length", Nat64.toText(fileSize))]);
                        };

                        return {
                            status_code = 200; // OK
                            headers = responseHeaders;
                            body = chunkData;
                            streaming_strategy = streamingStrategy;
                        };
                    };
                };
            };
        };
    };

    public func httpStreamingCallback({
        d3 : Filebase.D3;
        streamingCallbackToken : HttpTypes.StreamingCallbackToken;
    }) : HttpTypes.StreamingCallbackHttpResponse {
        let {
            file_id = fileId;
            file_size = fileSize;
            index;
        } = streamingCallbackToken;

        switch (Get._getFileAndRegion(d3, fileId)) {
            case (null) {
                return {
                    token = null;
                    body = Blob.fromArray([]);
                };
            };
            case (?{ fileLocation; storageRegion }) {
                let offset = fileLocation.offset;
                let region = storageRegion.region;

                let fileChunkStartOffset = index * Filebase.CHUNK_SIZE;
                let remainingSizeBeforeChunking = fileSize - fileChunkStartOffset;
                let fileChunkSize = Nat64.min(remainingSizeBeforeChunking, Filebase.CHUNK_SIZE);
                let chunkData = Region.loadBlob(region, offset + NTDO.getFileDataRelativeoffset() + fileChunkStartOffset, Nat64.toNat(fileChunkSize));
                let remainingSizeAfterChunking = remainingSizeBeforeChunking - fileChunkSize;

                if (remainingSizeAfterChunking == 0) {
                    return {
                        token = null;
                        body = chunkData;
                    };
                };

                return {
                    token = ?{
                        file_id = fileId;
                        file_size = fileSize;
                        index = index + 1;
                        chunk_size = Filebase.CHUNK_SIZE;
                    };
                    body = chunkData;
                };
            };
        };
    };
};
