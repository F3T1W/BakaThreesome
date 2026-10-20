using System.Text.Json.Serialization;
using JetBrains.Annotations;

namespace BakaThreesome.ShikimoriBridge;

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record AnimeSummary(
    [property: JsonPropertyName("id")] long Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("episodes")]
    long Episodes,
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("communityScore")]
    double? CommunityScore);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record UserRateSummary(
    [property: JsonPropertyName("id")] long Id,
    [property: JsonPropertyName("animeID")]
    long AnimeId,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("episodes")]
    long Episodes,
    [property: JsonPropertyName("score")] long Score);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record AnimeIdentity(
    [property: JsonPropertyName("id")] long Id,
    [property: JsonPropertyName("titles")] string[] Titles,
    [property: JsonPropertyName("year")] int? Year,
    [property: JsonPropertyName("kind")] string Kind);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record AnimeDetails(
    [property: JsonPropertyName("anime")] AnimeSummary Anime,
    [property: JsonPropertyName("rate")] UserRateSummary? Rate,
    [property: JsonPropertyName("identity")]
    AnimeIdentity Identity);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record ListEntry(
    [property: JsonPropertyName("anime")] AnimeSummary Anime,
    [property: JsonPropertyName("rate")] UserRateSummary Rate);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record UserProfile(
    [property: JsonPropertyName("id")] long Id,
    [property: JsonPropertyName("nickname")]
    string Nickname);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record TokenPair(
    [property: JsonPropertyName("accessToken")]
    string AccessToken,
    [property: JsonPropertyName("refreshToken")]
    string RefreshToken,
    [property: JsonPropertyName("expiresAt")]
    long ExpiresAt);

[UsedImplicitly(ImplicitUseTargetFlags.WithMembers, Reason = "Serialized for the Swift JSON v1 client.")]
public sealed record AnimePoster(
    [property: JsonPropertyName("animeID")]
    long AnimeId,
    [property: JsonPropertyName("imageURL")]
    string? ImageUrl);
