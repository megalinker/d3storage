import D3 "../D3";
import Property "property";
import Scenario "scenario";
import Random "mo:base/Random";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat"

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

    // Run all available tests
    public shared func run_all_tests() : async Text {
        let scenario_result = await self.run_scenarios();
        Debug.print(scenario_result);

        let fuzz_result = await self.fuzz();
        Debug.print(fuzz_result);

        "\nAll tests completed successfully! 🎉";
    };
};
