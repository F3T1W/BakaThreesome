using System.Net;
using System.Text.Json;
using BakaThreesome.Bridge.Contracts;
using BakaThreesome.ShikimoriBridge;
using ShikimoriSharp;

var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
var adapter = new ShikimoriAdapter();

// stdout is reserved for the protocol. Never log request bodies or exception details.
while (await Console.In.ReadLineAsync() is { } line)
{
    BridgeResponse response;
    string? id = null;
    try
    {
        if (line.Length > 1_048_576) throw new ArgumentException();
        var request = JsonSerializer.Deserialize<BridgeRequest>(line, options);
        id = request?.Id;
        response = request switch
        {
            null or { Id: null or "" } => Failure(id, "invalid_request", "A request ID is required."),
            { Version: not Protocol.Version } => Failure(id, "unsupported_version", "Unsupported protocol version."),
            _ => new BridgeResponse(Protocol.Version, id, await adapter.Execute(request))
        };
    }
    catch (JsonException) { response = Failure(id, "invalid_json", "Malformed JSON request."); }
    catch (NotSupportedException) { response = Failure(id, "unknown_method", "Method is not available."); }
    catch (ArgumentException) { response = Failure(id, "invalid_parameters", "Check the supplied values."); }
    catch (ShikimoriRequestException error)
    {
        response = error.StatusCode switch
        {
            HttpStatusCode.Unauthorized => Failure(id, "unauthorized", "Sign in to Shikimori again."),
            HttpStatusCode.Forbidden => Failure(id, "forbidden", "The account does not allow this action."),
            HttpStatusCode.TooManyRequests => Failure(id, "rate_limited", "Wait before trying again."),
            HttpStatusCode.UnprocessableEntity => Failure(id, "invalid_parameters", "Shikimori rejected these values."),
            _ => Failure(id, "service_error", "Shikimori could not complete the request.")
        };
    }
    catch (OperationCanceledException) { response = Failure(id, "timeout", "Shikimori did not respond in time."); }
    catch (HttpRequestException) { response = Failure(id, "network_error", "Shikimori could not be reached."); }
    catch (Exception) { response = Failure(id, "request_failed", "The request could not be completed."); }
    await Console.Out.WriteLineAsync(JsonSerializer.Serialize(response, options));
    await Console.Out.FlushAsync();
}

static BridgeResponse Failure(string? id, string code, string message) =>
    new(Protocol.Version, id, Error: new BridgeError(code, message));
