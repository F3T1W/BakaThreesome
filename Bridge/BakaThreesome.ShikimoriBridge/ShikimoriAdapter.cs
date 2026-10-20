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

public sealed class ShikimoriAdapter(HttpClient? httpClient = null)
{
    private static readonly string[] Capabilities =
    [
        "handshake", "catalog.posters", "catalog.search", "anime.details", "account.exchange", "account.refresh",
        "account.whoami", "watchlist.list", "watchlist.save", "watchlist.progress"
    ];

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly ShikimoriClient _client = new(NullLogger.Instance, new ClientSettings("BakaThreesome", "", ""),
        httpClient);

    public async Task<object> Execute(BridgeRequest request)
    {
        var p = request.Parameters.ValueKind == JsonValueKind.Object
            ? request.Parameters.Deserialize<Parameters>(Json) ?? new Parameters()
            : new Parameters();
        var token = string.IsNullOrEmpty(p.AccessToken)
            ? null
            : new AccessToken
            {
                Access_Token = p.AccessToken, Scope = "user_rates", TokenType = "Bearer"
            };
        return request.Method switch
        {
            "handshake" => new HandshakeResult("BakaThreesome.ShikimoriBridge", Capabilities),
            "catalog.posters" => await new ShikimoriPosters(_client).Load(p.AnimeIDs),
            "catalog.search" => await Search(p, token),
            "anime.details" => await Details(p, token),
            "account.whoami" => await Profile(token),
            "account.exchange" => await Authorize(p, false),
            "account.refresh" => await Authorize(p, true),
            "watchlist.list" => await List(p, token),
            "watchlist.progress" => await AdvanceProgress(p, token),
            "watchlist.save" => await Save(p, token),
            _ => throw new NotSupportedException()
        };
    }

    private async Task<AnimeSummary[]> Search(Parameters p, AccessToken? token)
    {
        return
        [
            .. (await _client.Animes.GetAnime(new AnimeRequestSettings
            {
                search = p.Query, page = ValidatePage(p.Page), limit = 30, order = Order.ranked
            }, token)).Select(Summary)
        ];
    }

    private async Task<AnimeDetails> Details(Parameters p, AccessToken? token)
    {
        Positive(p.AnimeId, nameof(p.AnimeId));
        var detail = await _client.Animes.GetAnime(p.AnimeId, token);
        return new AnimeDetails(Summary(detail), detail.UserRate is { } rate ? Rate(rate, p.AnimeId) : null,
            new AnimeIdentity(detail.Id,
                [
                    .. new[] { detail.Name, detail.Russian, detail.LicenseNameRu }
                        .Concat(detail.English ?? []).Concat(detail.Japanese ?? [])
                        .Concat(detail.Synonyms ?? [])
                        .Where(value => !string.IsNullOrWhiteSpace(value)).Distinct()
                ],
                detail.AiredOn?.Year, detail.Kind ?? "unknown"));
    }

    private async Task<UserProfile> Profile(AccessToken? token)
    {
        ArgumentNullException.ThrowIfNull(token);
        var user = await _client.Users.WhoAmI(token);
        return new UserProfile(user.Id, user.Nickname);
    }

    private async Task<TokenPair> Authorize(Parameters p, bool refresh)
    {
        if (string.IsNullOrWhiteSpace(p.ClientId) || string.IsNullOrWhiteSpace(p.ClientSecret))
            throw new ArgumentException("Client credentials are required.");
        var manager = new AuthorizationManager(
            new ClientSettings("BakaThreesome", p.ClientId, p.ClientSecret),
            (url, content) => _client.Client.RequestForm<AccessToken>(url, content, method: "POST"));
        AccessToken result;
        if (!refresh)
        {
            ArgumentNullException.ThrowIfNull(p.Code);
            result = await manager.GetAccessToken(p.Code);
        }
        else
        {
            ArgumentNullException.ThrowIfNull(p.RefreshToken);
            result = await manager.RefreshAccessToken(new AccessToken { RefreshToken = p.RefreshToken });
        }

        if (string.IsNullOrEmpty(result.Access_Token) || string.IsNullOrEmpty(result.RefreshToken)
                                                      || result.ExpiresIn <= 0)
            throw new InvalidDataException();
        return new TokenPair(result.Access_Token, result.RefreshToken,
            DateTimeOffset.UtcNow.ToUnixTimeSeconds() + result.ExpiresIn);
    }

    private async Task<ListEntry[]> List(Parameters p, AccessToken? token)
    {
        ArgumentNullException.ThrowIfNull(token);
        Positive(p.UserId, nameof(p.UserId));
        MyList? status = p.Status == null ? null : ParseStatus(p.Status);
        return
        [
            .. (await _client.Users.GetUserAnimeRates(p.UserId,
                new AnimeRateRequestSettings { limit = 50, page = ValidatePage(p.Page), status = status }, token))
            .Where(entry => entry.Anime != null)
            .Select(entry => new ListEntry(Summary(entry.Anime), Rate(entry, entry.Anime.Id)))
        ];
    }

    private async Task<UserRateSummary> AdvanceProgress(Parameters p, AccessToken? token)
    {
        ArgumentNullException.ThrowIfNull(token);
        Positive(p.AnimeId, nameof(p.AnimeId));
        if (p.RateId is not { } progressRateId)
            throw new ArgumentException("A rate ID is required.", nameof(p));
        Positive(progressRateId, nameof(p.RateId));
        ValidateRange(p.Episodes, 1, 100000, nameof(p.Episodes));
        var progress = await _client.UserRates.EditUserRate(progressRateId,
            new UserRateEditSettings(new UserRateBase { episodes = p.Episodes }), token);
        return Rate(progress, p.AnimeId);
    }

    private async Task<UserRateSummary> Save(Parameters p, AccessToken? token)
    {
        ArgumentNullException.ThrowIfNull(token);
        Positive(p.UserId, nameof(p.UserId));
        Positive(p.AnimeId, nameof(p.AnimeId));
        ValidateRange(p.Episodes, 0, 100000, nameof(p.Episodes));
        ValidateRange(p.Score, 0, 10, nameof(p.Score));
        var state = ParseStatus(p.Status);
        var values = new UserRateContent(p.UserId, p.AnimeId, TargetType.Anime)
            { episodes = p.Episodes, score = p.Score, status = state };
        UserRate updated;
        if (p.RateId is { } id)
        {
            Positive(id, nameof(p.RateId));
            updated = await _client.UserRates.EditUserRate(id, new UserRateEditSettings(values), token);
        }
        else
        {
            updated = await _client.UserRates.NewUserRate(new NewUserRateSettings(values), token);
        }

        return Rate(updated, p.AnimeId);
    }

    private static int ValidatePage(int page)
    {
        ValidateRange(page, 1, 1000, nameof(page));
        return page;
    }

    private static void Positive(long value, string parameterName)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(value, parameterName);
    }

    private static void ValidateRange(int value, int minimum, int maximum, string parameterName)
    {
        if (value < minimum || value > maximum)
            throw new ArgumentOutOfRangeException(parameterName, "The value is outside the supported range.");
    }

    private static MyList ParseStatus(string? value)
    {
        return Enum.TryParse<MyList>(value, out var result) && Enum.IsDefined(result)
            ? result
            : throw new ArgumentException("A supported watch status is required.", nameof(value));
    }

    private static AnimeSummary Summary(AnimeMangaBase anime)
    {
        return new AnimeSummary(
            anime.Id, anime.Name ?? "Untitled", anime is Anime a ? a.Episodes : ((AnimeID)anime).Episodes,
            anime.Kind ?? "unknown",
            double.TryParse(anime.Score, CultureInfo.InvariantCulture, out var score) ? score : null);
    }

    private static UserRateSummary Rate(PublicUserRate rate, long animeId)
    {
        return new UserRateSummary(
            rate.Id, animeId, rate.Status, rate.Episodes ?? 0, rate.Score);
    }

    private sealed class Parameters
    {
        public long[]? AnimeIDs { get; init; }
        public string? Query { get; init; }
        public int Page { get; init; } = 1;
        public string? AccessToken { get; init; }
        public string? ClientId { get; init; }
        public string? ClientSecret { get; init; }
        public string? Code { get; init; }
        public string? RefreshToken { get; init; }
        public long AnimeId { get; init; }
        public long UserId { get; init; }
        public long? RateId { get; init; }
        public string? Status { get; init; }
        public int Episodes { get; init; }
        public int Score { get; init; }
    }
}
