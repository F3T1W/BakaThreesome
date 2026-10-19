using System.Globalization;
using System.Text;
using System.Text.Json;
using Newtonsoft.Json.Linq;
using ShikimoriSharp;

namespace BakaThreesome.ShikimoriBridge;

/// <summary>Loads current poster derivatives through the shared ShikimoriSharp transport and rate limits.</summary>
internal sealed class ShikimoriPosters(ShikimoriClient client)
{
    public async Task<AnimePoster[]> Load(long[]? animeIDs)
    {
        if (animeIDs is not { Length: >= 1 and <= 50 } || animeIDs.Any(id => id <= 0))
            throw new ArgumentException();
        var ids = animeIDs.Distinct().ToArray();
        const string query = "query Posters($ids: String!) { animes(ids: $ids, limit: 50, censored: false) { id poster { main2xUrl } } }";
        using var content = new StringContent(JsonSerializer.Serialize(new
        {
            query, variables = new { ids = string.Join(",", ids.Select(id => id.ToString(CultureInfo.InvariantCulture))) }
        }), Encoding.UTF8, "application/json");
        var response = await client.Client.RequestForm<JObject>("https://shikimori.io/api/graphql", content, method: "POST");
        if (response["errors"] is JArray { Count: > 0 } || response["data"]?["animes"] is not JArray animes)
            throw new InvalidDataException();
        var posters = new Dictionary<long, string?>();
        foreach (var anime in animes)
        {
            if (!long.TryParse(anime["id"]?.ToString(), NumberStyles.None, CultureInfo.InvariantCulture, out var id)
                || !ids.Contains(id)) throw new InvalidDataException();
            var url = anime["poster"] is JObject poster ? poster["main2xUrl"]?.ToString() : null;
            posters[id] = SafeURL(url);
        }
        return ids.Select(id => new AnimePoster(id, posters.GetValueOrDefault(id))).ToArray();
    }

    private static string? SafeURL(string? value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var url) && url.Scheme == Uri.UriSchemeHttps
            && string.IsNullOrEmpty(url.UserInfo) && !string.IsNullOrEmpty(url.Host) ? url.AbsoluteUri : null;
}

public sealed record AnimePoster(long AnimeID, string? ImageURL);
