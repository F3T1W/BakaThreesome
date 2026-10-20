using System.Text.Json;
using System.Text.Json.Serialization;
using JetBrains.Annotations;

namespace BakaThreesome.Bridge.Contracts;

public static class Protocol
{
    public const int Version = 1;
}

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record BridgeRequest(
    [property: JsonPropertyName("version")]
    int Version,
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("method")] string Method,
    [property: JsonPropertyName("parameters")]
    JsonElement Parameters = default);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record BridgeError(
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("message")]
    string Message);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record HandshakeResult(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("capabilities")]
    string[] Capabilities);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record BridgeResponse(
    [property: JsonPropertyName("version")]
    int Version,
    [property: JsonPropertyName("id")] string? Id,
    [property: JsonPropertyName("result")] object? Result = null,
    [property: JsonPropertyName("error")] BridgeError? Error = null);
