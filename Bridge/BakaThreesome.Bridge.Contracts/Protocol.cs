using System.Text.Json;

namespace BakaThreesome.Bridge.Contracts;

public static class Protocol
{
    public const int Version = 1;
    public const string Handshake = "handshake";
}

public sealed record BridgeRequest(int Version, string Id, string Method, JsonElement Parameters = default);

public sealed record BridgeError(string Code, string Message);

public sealed record HandshakeResult(string Name, string[] Capabilities);

public sealed record BridgeResponse(
    int Version,
    string? Id,
    object? Result = null,
    BridgeError? Error = null);
