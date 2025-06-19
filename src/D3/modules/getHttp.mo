import Filebase "../types/filebase";
import StorageClasses "../storageClasses";
import HttpTypes "../types/http";
import HttpParser "mo:httpParser";
import Map "mo:map/Map";
import { nhash; thash } "mo:map/Map";
import Array "mo:base/Array";
import Region "mo:base/Region";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {

    let { NTDO } = StorageClasses;

    public func getFileHTTP({
        d3 : Filebase.D3;
        httpRequest : HttpTypes.HttpRequest;
        httpStreamingCallbackActor : HttpTypes.HttpStreamingCallbackActor;
    }) : HttpTypes.HttpResponse {

        let { method; url } = HttpParser.parse(httpRequest);
        let { path; queryObj } = url;

        ////////////////////////////////////////////// VALIDATIONS //////////////////////////////////////////////

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

        /////////////////////////////////////////////////////////////////////////////////////////////////////////

        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        switch (Map.get(fileLocationMap, thash, fileId)) {
            case (null) {
                return {
                    status_code = 404;
                    headers = [];
                    body = "Not Found: File with the specified file_id does not exist" : Blob;
                    streaming_strategy = null;
                };
            };
            case (?fileLocation) {
                switch (Map.get(storageRegionMap, nhash, fileLocation.regionId)) {
                    case (null) {
                        // This is a serious internal error, the file location points to a non-existent region.
                        return {
                            status_code = 500;
                            headers = [];
                            body = "Internal Server Error: Storage region for this file is missing" : Blob;
                            streaming_strategy = null;
                        };
                    };
                    case (?storageRegion) {
                        let offset = fileLocation.offset;
                        let region = storageRegion.region;

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

                        let fileChunkSize = Nat64.min(fileSize, Filebase.CHUNK_SIZE);
                        let chunkData = Region.loadBlob(region, offset + NTDO.getFileDataRelativeoffset(), Nat64.toNat(fileChunkSize));
                        let remainingSizeAfterChunking = fileSize - fileChunkSize;

                        var responseHeaders : [(Text, Text)] = [];
                        var streamingStrategy : ?HttpTypes.StreamingStrategy = null;
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
                            responseHeaders := [
                                ("Content-Type", fileType),
                                ("Transfer-Encoding", "chunked"),
                                ("Content-Disposition", "inline"),
                            ];
                        } else {
                            streamingStrategy := null;
                            responseHeaders := [("Content-Type", fileType)];
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

        let storageRegionMap = d3.storageRegionMap;
        let fileLocationMap = d3.fileLocationMap;

        switch (Map.get(fileLocationMap, thash, fileId)) {
            case (null) {
                return {
                    token = null;
                    body = Blob.fromArray([]);
                };
            };
            case (?fileLocation) {
                switch (Map.get(storageRegionMap, nhash, fileLocation.regionId)) {
                    case (null) {
                        return {
                            token = null;
                            body = Blob.fromArray([]);
                        };
                    };
                    case (?storageRegion) {
                        let offset = fileLocation.offset;
                        let region = storageRegion.region;

                        let fileChunkStartOffset = index * Filebase.CHUNK_SIZE;
                        let remainingSizeBeforeChunking = fileSize - fileChunkStartOffset;
                        let fileChunkSize = Nat64.min(remainingSizeBeforeChunking, Filebase.CHUNK_SIZE);
                        let chunkData = Region.loadBlob(region, offset + NTDO.getFileDataRelativeoffset() + fileChunkStartOffset, Nat64.toNat(fileChunkSize));
                        let remainingSizeAfterChunking = remainingSizeBeforeChunking - fileChunkSize;

                        // streaming is done
                        if (remainingSizeAfterChunking == 0) {
                            return {
                                token = null;
                                body = chunkData;
                            };
                        };

                        // more streaming is required
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
    };
};
