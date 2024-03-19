import D3 "../D3";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import TestFile "testFile";

shared ({ caller }) actor class Test() = this {

    stable let d3 = D3.D3();

    public shared func updateOperation({
        updateOperationInput : D3.UpdateOperationInputType;
    }) : async D3.UpdateOperationOutputType {
        await D3.updateOperation({ d3; updateOperationInput });
    };

    public query func queryOperation({
        queryOperationInput : D3.QueryOperationInputType;
    }) : async D3.QueryOperationOutputType {
        D3.queryOperation({ d3; queryOperationInput });
    };

    public shared func uploadTestFile() : async D3.UpdateOperationOutputType {

        await D3.updateOperation({ d3; updateOperationInput = #StoreFile({
            fileDataObject = Blob.fromArray(TestFile.SoccerBall);
            fileName = "SoccerBall.jpeg";
            fileType = "image/jpeg";
        })});
    };

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////

    public query ({ caller }) func http_request(httpRequest : D3.HttpRequest) : async D3.HttpResponse {

        D3.getFileHTTP({ d3; httpRequest; httpStreamingCallbackActor = this });
    };

    public query ({ caller }) func http_request_streaming_callback(streamingCallbackToken : D3.StreamingCallbackToken) : async D3.StreamingCallbackHttpResponse {

        D3.httpStreamingCallback({ d3; streamingCallbackToken; });
    };

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

};
