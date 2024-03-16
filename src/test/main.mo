import D3 "../D3";

shared ({ caller }) actor class Test() {

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

};
