import D3 "../D3";
import Filebase "../D3/types/filebase";
import TestFile "testFile";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import BTree "mo:stableheapbtreemap/BTree";
import Utils "../D3/modules/utils";
import HttpParser "mo:httpParser";
import Array "mo:base/Array";
import Property "property";
import Vector "mo:vector";

module Scenario {

    // Helper to assert two blobs are equal.
    func assertBlobsEqual(a : Blob, b : Blob) {
        if (not Blob.equal(a, b)) {
            Debug.trap("Assertion failed: Blobs are not equal.");
        };
    };

    public func runFullLifecycleScenario(d3 : D3.D3, httpCallbackActor : D3.HttpStreamingCallbackActor) : async () {
        Debug.print("\n--- Starting Full Lifecycle Scenario ---");

        let fileBlob = Blob.fromArray(TestFile.SoccerBall);
        let fileSize = Nat64.fromNat(fileBlob.size());
        let fileName = "soccer_ball.jpg";
        let fileType = "image/jpeg";

        // 1. Chunked Upload
        Debug.print("1. Starting chunked upload for " # fileName);
        let meta = await D3.storeFileMetadata({
            d3;
            storeFileMetadataInput = {
                fileSizeInBytes = fileSize;
                fileName;
                fileType;
            };
        });

        let fileId = meta.fileId;
        let CHUNK_SIZE = meta.chunkSizeInBytes;
        let numOfChunks = meta.numOfChunks;

        assert (meta.fileId != "");
        Debug.print("  - Metadata stored. FileID: " # fileId # ", Chunks: " # Nat64.toText(numOfChunks));

        for (i_int in Iter.range(0, Int.abs(Nat64.toNat(numOfChunks) - 1))) {
            let i = Nat64.fromNat(Int.abs(i_int));
            let start = i * CHUNK_SIZE;
            let end = Nat64.min((i + 1) * CHUNK_SIZE, fileSize);
            let chunkSize = end - start;

            let chunkBlob = Blob.fromArray(
                Iter.toArray(
                    Array.slice<Nat8>(
                        Blob.toArray(fileBlob),
                        Nat64.toNat(start),
                        Nat64.toNat(start) + Nat64.toNat(chunkSize),
                    )
                )
            );

            ignore await D3.storeFileChunk({
                d3;
                storeFileChunkInput = {
                    fileId;
                    chunkData = chunkBlob;
                    chunkIndex = i;
                };
            });
            Debug.print("  - Uploaded chunk " # Nat64.toText(i + 1) # "/" # Nat64.toText(numOfChunks));
        };
        Debug.print("  - Chunked upload complete.");

        // Verify file status is now #Complete
        let ?loc = BTree.get(d3.fileLocationMap, Text.compare, fileId) else Debug.trap("File location not found after upload");
        assert (loc.status == #Complete);

        // 2. Verification
        Debug.print("2. Verifying file metadata and content.");

        let retrievedMeta_opt : D3.GetFileMetadataOutputType = D3.getFileMetadata({
            d3;
            getFileMetadataInput = { fileId };
        });

        switch (retrievedMeta_opt) {
            case (null) {
                Debug.trap("getFileMetadata returned null for a valid fileId");
            };
            case (?m) {
                assert (m.fileId == fileId);
                assert (m.fileName == fileName);
                assert (m.fileType == fileType);
                assert (m.fileSizeInBytes == fileSize);
            };
        };
        Debug.print("  - getFileMetadata verified.");

        // 3. HTTP Streaming Download & Verification
        Debug.print("3. Testing HTTP streaming download.");
        let httpRequest : D3.HttpRequest = {
            method = "GET";
            url = "/d3?file_id=" # fileId;
            headers = [];
            body = Blob.fromArray([]);
            certificate_version = null;
        };

        var httpResponse = D3.getFileHTTP({
            d3;
            httpRequest;
            httpStreamingCallbackActor = httpCallbackActor;
        });

        assert (httpResponse.status_code == 200);

        let downloadedBlobBuffer = Buffer.Buffer<Blob>(Nat64.toNat(numOfChunks));
        downloadedBlobBuffer.add(httpResponse.body);
        Debug.print("  - Received first HTTP chunk.");

        var streamingStrategy = httpResponse.streaming_strategy;

        label whileLoop while (true) {
            switch (streamingStrategy) {
                case (null) { break whileLoop };
                case (?#Callback({ token; callback })) {
                    Debug.print("  - Requesting next streaming chunk...");
                    let streamingResponse = await callback(token);
                    downloadedBlobBuffer.add(streamingResponse.body);
                    switch (streamingResponse.token) {
                        case (null) { streamingStrategy := null };
                        case (?t) {
                            streamingStrategy := ?#Callback({
                                token = t;
                                callback;
                            });
                        };
                    };
                };
            };
        };

        Debug.print("  - HTTP streaming complete. Re-assembling file.");

        let blobArray = Buffer.toArray(downloadedBlobBuffer);
        let downloadedFileBlob = Array.foldLeft<Blob, Blob>(
            blobArray,
            Blob.fromArray([]),
            func(acc, next) {
                let accBytes = Blob.toArray(acc);
                let nextBytes = Blob.toArray(next);
                let buf = Vector.fromArray<Nat8>(accBytes);
                for (b in nextBytes.vals()) {
                    Vector.add<Nat8>(buf, b);
                };
                Blob.fromArray(Vector.toArray(buf));
            },
        );

        assertBlobsEqual(fileBlob, downloadedFileBlob);
        Debug.print("  - Downloaded file content verified via HTTP stream.");

        // 4. Deletion
        Debug.print("4. Deleting file.");
        let deleteResult = D3.deleteFile({
            d3;
            deleteFileInput = { fileId };
        });
        assert deleteResult.success;
        assert (BTree.get(d3.fileLocationMap, Text.compare, fileId) == null);
        Debug.print("  - File deleted successfully and removed from map.");

        // Verify space was reclaimed correctly
        Property.checkAllRegions(d3);
        Debug.print("  - Memory invariants hold after deletion.");

        // 5. Test Cleanup of Abandoned Upload
        Debug.print("5. Testing cleanup of abandoned uploads.");
        let abandonedMeta = await D3.storeFileMetadata({
            d3;
            storeFileMetadataInput = {
                fileSizeInBytes = 2 * CHUNK_SIZE;
                fileName = "abandoned.dat";
                fileType = "application/octet-stream";
            };
        });
        let stats = D3.cleanupAbandonedUploads({
            d3;
            timeoutNanos = 0;
            startKey = null;
            limit = 100;
        });
        assert (stats.reclaimed == 1);
        assert (BTree.get(d3.fileLocationMap, Text.compare, abandonedMeta.fileId) == null);
        Debug.print("  - cleanupAbandonedUploads successfully reclaimed 1 pending file.");

        Property.checkAllRegions(d3);
        Debug.print("  - Memory invariants hold after cleanup.");

        Debug.print("--- Full Lifecycle Scenario Passed ---");
    };
};
