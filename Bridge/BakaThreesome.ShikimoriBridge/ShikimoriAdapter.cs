using System.Globalization;
using System.Text.Json;
using BakaThreesome.Bridge.Contracts;
using Microsoft.Extensions.Logging.Abstractions;
using ShikimoriSharp;
using ShikimoriSharp.Bases;
using ShikimoriSharp.Classes;
using ShikimoriSharp.Enums;
using ShikimoriSharp.Settings;

namespace BakaThreesome.ShikimoriBridge;

public sealed class ShikimoriAdapter
{
    public static readonly string[] Capabilities =
    ["handshake", "catalog.search", "anime.details", "account.exchange", "account.refresh", "account.whoami", "watchlist.list", "watchlist.save"];

    private readonly ShikimoriClient client;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public ShikimoriAdapter(HttpClient? httpClient = null)
    {
        client = new ShikimoriClient(NullLogger.Instance, new ClientSettings("BakaThreesome", "", ""), httpClient);
    }

    public async Task<object> Execute(BridgeRequest request)
    {
        var p = request.Parameters.ValueKind == JsonValueKind.Object
            ? request.Parameters.Deserialize<Parameters>(Json) ?? new Parameters() : new Parameters();
        var token = string.IsNullOrEmpty(p.AccessToken) ? null : new AccessToken
        {
            Access_Token = p.AccessToken, Scope = "user_rates", TokenType = "Bearer"
        };
        switch (request.Method)
        {
            case "handshake": return new HandshakeResult("BakaThreesome.ShikimoriBridge", Capabilities);
            case "catalog.search":
                return (await client.Animes.GetAnime(new AnimeRequestSettings
                {
                    search = p.Query, page = Page(p.Page), limit = 30, order = Order.ranked
                }, token)).Select(Summary).ToArray();
            case "anime.details":
                Positive(p.AnimeID);
                var detail = await client.Animes.GetAnime(p.AnimeID, token);
                return new AnimeDetails(Summary(detail), detail.UserRate is { } rate ? Rate(rate, p.AnimeID) : null,
                    new AnimeIdentity(detail.Id,
                        new[] { detail.Name, detail.Russian, detail.LicenseNameRu }
                            .Concat(detail.English ?? []).Concat(detail.Japanese ?? []).Concat(detail.Synonyms ?? [])
                            .Where(value => !string.IsNullOrWhiteSpace(value)).Distinct().ToArray(),
                        detail.AiredOn?.Year, detail.Kind ?? "unknown"));
            case "account.whoami":
                Required(token);
                var user = await client.Users.WhoAmI(token);
                return new UserProfile(user.Id, user.Nickname);
            case "account.exchange":
            case "account.refresh":
                if (string.IsNullOrWhiteSpace(p.ClientID) || string.IsNullOrWhiteSpace(p.ClientSecret))
                    throw new ArgumentException("Client credentials are required.");
                var manager = new AuthorizationManager(
                    new ClientSettings("BakaThreesome", p.ClientID, p.ClientSecret),
                    (url, content) => client.Client.RequestForm<AccessToken>(url, content, method: "POST"));
                AccessToken result;
                if (request.Method == "account.exchange")
                {
                    Required(p.Code);
                    result = await manager.GetAccessToken(p.Code!);
                }
                else
                {
                    Required(p.RefreshToken);
                    result = await manager.RefreshAccessToken(new AccessToken { RefreshToken = p.RefreshToken });
                }
                if (string.IsNullOrEmpty(result.Access_Token) || string.IsNullOrEmpty(result.RefreshToken)
                    || result.ExpiresIn <= 0) throw new InvalidDataException();
                return new TokenPair(result.Access_Token, result.RefreshToken,
                    DateTimeOffset.UtcNow.ToUnixTimeSeconds() + (long)result.ExpiresIn);
            case "watchlist.list":
                Required(token);
                Positive(p.UserID);
                MyList? status = p.Status == null ? null : Status(p.Status);
                return (await client.Users.GetUserAnimeRates(p.UserID,
                    new AnimeRateRequestSettings { limit = 50, page = Page(p.Page), status = status }, token))
                    .Where(entry => entry.Anime != null)
                    .Select(entry => new ListEntry(Summary(entry.Anime), Rate(entry, entry.Anime.Id))).ToArray();
            case "watchlist.save":
                Required(token);
                Positive(p.UserID);
                Positive(p.AnimeID);
                if (p.Episodes is < 0 or > 100000 || p.Score is < 0 or > 10) throw new ArgumentException();
                var state = Status(p.Status);
                var values = new UserRateContent(p.UserID, p.AnimeID, TargetType.Anime)
                    { episodes = p.Episodes, score = p.Score, status = state };
                UserRate updated;
                if (p.RateID is { } id)
                {
                    Positive(id);
                    updated = await client.UserRates.EditUserRate(id, new UserRateEditSettings(values), token);
                }
                else
                    updated = await client.UserRates.NewUserRate(new NewUserRateSettings(values), token);
                return Rate(updated, p.AnimeID);
            default: throw new NotSupportedException();
        }
    }

    private static int Page(int page) => page is >= 1 and <= 1000 ? page : throw new ArgumentException();
    private static void Positive(long value) { if (value <= 0) throw new ArgumentException(); }
    private static void Required(object? value) { if (value == null) throw new ArgumentException(); }
    private static MyList Status(string? value) => Enum.TryParse<MyList>(value, out var result)
        && Enum.IsDefined(result) ? result : throw new ArgumentException();

    private static AnimeSummary Summary(AnimeMangaBase anime) => new(
        anime.Id, anime.Name ?? "Untitled", anime is Anime a ? a.Episodes : ((AnimeID)anime).Episodes,
        anime.Kind ?? "unknown",
        double.TryParse(anime.Score, CultureInfo.InvariantCulture, out var score) ? score : null);
    private static UserRateSummary Rate(PublicUserRate rate, long animeID) => new(
        rate.Id, animeID, rate.Status, rate.Episodes ?? 0, rate.Score);

    private sealed class Parameters
    {
        public string? Query { get; init; }
        public int Page { get; init; } = 1;
        public string? AccessToken { get; init; }
        public string? ClientID { get; init; }
        public string? ClientSecret { get; init; }
        public string? Code { get; init; }
        public string? RefreshToken { get; init; }
        public long AnimeID { get; init; }
        public long UserID { get; init; }
        public long? RateID { get; init; }
        public string? Status { get; init; }
        public int Episodes { get; init; }
        public int Score { get; init; }
    }
}

public sealed record AnimeSummary(long Id, string Title, long Episodes, string Kind, double? CommunityScore);
public sealed record UserRateSummary(long Id, long AnimeID, string Status, long Episodes, long Score);
public sealed record AnimeIdentity(long Id, string[] Titles, int? Year, string Kind);
public sealed record AnimeDetails(AnimeSummary Anime, UserRateSummary? Rate, AnimeIdentity Identity);
public sealed record ListEntry(AnimeSummary Anime, UserRateSummary Rate);
public sealed record UserProfile(long Id, string Nickname);
public sealed record TokenPair(string AccessToken, string RefreshToken, long ExpiresAt);
