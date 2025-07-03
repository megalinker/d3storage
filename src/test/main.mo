import D3 "../D3";
import Filebase "../D3/types/filebase";
import Property "property";
import Scenario "scenario";
import Random "mo:base/Random";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";

actor class TestMain() = self {

    // Stable state for D3 instance
    stable var d3 = D3.D3();

    // The number of property-based runs to execute.
    let FUZZ_RUNS : Nat = 25;

    // --- HTTP Streaming Interface Implementation ---

    public shared query func http_request_streaming_callback(
        streamingCallbackToken : D3.StreamingCallbackToken
    ) : async D3.StreamingCallbackHttpResponse {
        D3.httpStreamingCallback({ d3; streamingCallbackToken });
    };

    // --- Test Entrypoints ---

    // Run the chaotic property-based tests
    public shared func fuzz() : async Text {
        Debug.print("### RUNNING PROPERTY-BASED FUZZ TESTS ###");
        d3 := D3.D3();
        let rand = Random.Finite(await Random.blob());

        var i = 0;
        while (i < FUZZ_RUNS) {
            Debug.print("\n--- Fuzz Iteration " # Nat.toText(i + 1) # "/" # Nat.toText(FUZZ_RUNS) # " ---");
            await Property.runChaoticScenario(d3, rand);
            i += 1;
        };

        "All " # Nat.toText(FUZZ_RUNS) # " fuzzing scenarios passed ✅";
    };

    // Run the deterministic lifecycle scenarios
    public shared func run_scenarios() : async Text {
        Debug.print("### RUNNING DETERMINISTIC SCENARIO TESTS ###");
        d3 := D3.D3();

        await Scenario.runFullLifecycleScenario(d3, self);

        "All deterministic scenarios passed ✅";
    };

    // ====================================================================
    // === Driver function for the incremental cleanup process.         ===
    // ====================================================================
    public shared(_msg) func runCleanup() : async Text {
        Debug.print("### STARTING INCREMENTAL CLEANUP ###");

        var nextKey : ?Text = null;
        var totalReclaimed : Nat = 0;
        var totalBytesFreed : Nat64 = 0;
        let BATCH_SIZE : Nat = 1000; // Process 1000 files per message
        var done = false;

        // The while loop orchestrates the batch processing.
        // Each iteration is a separate "turn" that respects IC cycle limits.
        while (not done) {
            let stats = D3.cleanupAbandonedUploads({
                d3;
                timeoutNanos = 3_600_000_000_000; // 1 hour in nanoseconds
                startKey = nextKey;
                limit = BATCH_SIZE;
            });

            // Aggregate stats from the completed batch
            totalReclaimed += stats.reclaimed;
            totalBytesFreed += stats.bytesFreed;

            Debug.print(
                "Cleanup Batch Report: Scanned=" # Nat.toText(stats.scanned) #
                ", Reclaimed=" # Nat.toText(stats.reclaimed) #
                ", Bytes Freed=" # Nat64.toText(stats.bytesFreed)
            );

            // Check if there is more work to do
            switch (stats.nextKey) {
                case null {
                    // No next key was returned, so we are finished.
                    done := true;
                };
                case (?key) {
                    // A next key was returned. Set it as the starting
                    // point for the next iteration of the loop.
                    nextKey := ?key;
                };
            };
        };

        let report = "Cleanup finished. Total Reclaimed: " # Nat.toText(totalReclaimed) # ", Total Bytes Freed: " # Nat64.toText(totalBytesFreed);
        Debug.print("### " # report # " ###");
        return report;
    };


    // Run all available tests
    public shared func run_all_tests() : async Text {
        let scenario_result = await self.run_scenarios();
        Debug.print(scenario_result);

        let fuzz_result = await self.fuzz();
        Debug.print(fuzz_result);

        Debug.print("\n--- Running a test cleanup ---");
        // First, create an abandoned upload to test against
        ignore await D3.storeFileMetadata({
            d3;
            storeFileMetadataInput = {
                fileSizeInBytes = 2 * Filebase.CHUNK_SIZE;
                fileName = "abandoned_for_test.dat";
                fileType = "application/octet-stream";
            };
        });
        let cleanup_result = await self.runCleanup();
        Debug.print(cleanup_result);

        "\nAll tests completed successfully! 🎉";
    };
};