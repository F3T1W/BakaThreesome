using System.Text.Json;
using BakaThreesome.Bridge.Contracts;

var jsonOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web);

// stdout is reserved for one JSON response per request. Never log payloads or secrets.
while (await Console.In.ReadLineAsync() is { } line)
{
    BridgeResponse response;
    try
    {
        var request = JsonSerializer.Deserialize<BridgeRequest>(line, jsonOptions);
        response = request switch
        {
            null => Failure(null, "invalid_request", "Expected a JSON request."),
            { Id: null or "" } => Failure(null, "invalid_request", "A request ID is required."),
            { Version: not Protocol.Version } =>
                Failure(request.Id, "unsupported_version", "Unsupported protocol version."),
            { Method: Protocol.Handshake } => new BridgeResponse(
                Protocol.Version,
                request.Id,
                new HandshakeResult("BakaThreesome.ShikimoriBridge", [Protocol.Handshake])),
            _ => Failure(request.Id, "unknown_method", "Method is not available.")
        };
    }
    catch (JsonException)
    {
        response = Failure(null, "invalid_json", "Malformed JSON request.");
    }

    await Console.Out.WriteLineAsync(JsonSerializer.Serialize(response, jsonOptions));
    await Console.Out.FlushAsync();
}

static BridgeResponse Failure(string? id, string code, string message) =>
    new(Protocol.Version, id, Error: new BridgeError(code, message));
