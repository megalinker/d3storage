module {

    public type HeaderField = (Text, Text);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // application specific
    public type StreamingCallbackToken = {
        file_id : Text;
        file_size : Nat64;
        index : Nat64;
        chunk_size : Nat64;
    };

    public type StreamingCallbackHttpResponse = {
        token : ?StreamingCallbackToken;
        body : Blob;
    };

    public type StreamingCallback = shared query (StreamingCallbackToken) -> async (StreamingCallbackHttpResponse);

    public type StreamingStrategy = {
        #Callback : {
            callback : StreamingCallback;
            token : StreamingCallbackToken;
        };
    };

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    public type HttpRequest = {
        method : Text;
        url : Text;
        headers : [ HeaderField ];
        body : Blob;
        certificate_version : ?Nat16;
    };

    public type HttpResponse = {
        status_code : Nat16;
        headers : [ HeaderField ];
        body : Blob;
        streaming_strategy : ?StreamingStrategy;
    };

    ////////////////////////////////////////////////////////////////////////

    public type HttpStreamingCallbackActor = actor {
        http_request_streaming_callback : StreamingCallback;
    };

    ////////////////////////////////////////////////////////////////////////
};