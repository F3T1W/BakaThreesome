using System.Net;
using System.Text;
using System.Text.Json;
using BakaThreesome.Bridge.Contracts;
using BakaThreesome.ShikimoriBridge;
using ShikimoriSharp;

static void Check(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
static BridgeRequest Request(string method, object parameters) => new(1, "test", method,
    JsonSerializer.SerializeToElement(parameters));

var calls = 0;
var posterFailure = false;
using var handler = new StubHandler(async request =>
{
    Check(request.RequestUri!.Host == "shikimori.io", "Canonical host");
    Check(request.Headers.UserAgent.ToString() == "BakaThreesome", "Application user agent");
    calls++;
    var path = request.RequestUri.AbsolutePath;
    if (path == "/api/graphql")
    {
        Check(request.Method == HttpMethod.Post, "GraphQL POST");
        Check(request.Headers.Authorization == null, "Public posters do not need account tokens");
        using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
        Check(body.RootElement.GetProperty("variables").GetProperty("ids").GetString() == "1,2,3", "Batched distinct poster IDs");
        Check(body.RootElement.GetProperty("query").GetString()!.Contains("main2xUrl"), "Retina poster derivative");
        return (HttpStatusCode.OK, posterFailure ? """{"errors":[{"message":"synthetic error"}]}""" :
            """{"data":{"animes":[{"id":"1","poster":{"main2xUrl":"https://shikimori.io/uploads/poster/animes/1/main.webp"}},{"id":"2","poster":null},{"id":"3","poster":{"main2xUrl":"http://unsafe.example/poster.jpg"}}]}}""");
    }
    if (path == "/api/animes")
    {
        Check(request.Method == HttpMethod.Get && request.Content == null, "GET must not have a body");
        Check(Uri.UnescapeDataString(request.RequestUri.Query.Replace("+", " ")).Contains("search=A & B/+?"), "Encoded search");
        Check(request.RequestUri.Query.Contains("page=2"), "Pagination query");
        return (HttpStatusCode.OK, """[{"id":1,"name":"Example","episodes":12,"kind":"tv","score":"8.25"}]""");
    }
    if (path == "/api/animes/1")
    {
        return (HttpStatusCode.OK, """{"id":1,"name":"Original Title","russian":"Localized Title","english":["English Title"],"japanese":["Japanese Title"],"synonyms":["Alternative Title"],"license_name_ru":"Licensed Title","aired_on":"2002-10-03","episodes":12,"kind":"tv"}""");
    }
    if (path == "/api/users/42/anime_rates")
    {
        Check(request.RequestUri.Query.Contains("status=on_hold"), "List filter query");
        Check(request.Headers.Authorization?.Parameter == "test-access", "Bearer header");
        return (HttpStatusCode.OK, """[{"id":7000000000,"status":"on_hold","episodes":3,"score":8,"anime":{"id":1,"name":"Example","episodes":12,"kind":"tv"}}]""");
    }
    if (path == "/api/v2/user_rates/7000000001")
    {
        Check(request.Method == HttpMethod.Put, "Progress is an absolute update");
        Check(request.Headers.Authorization?.Parameter == "test-access", "Progress bearer header");
        using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
        var rate = body.RootElement.GetProperty("user_rate");
        Check(rate.EnumerateObject().Count() == 1 && rate.GetProperty("episodes").GetInt32() == 4,
            "Progress never writes a rating, status or other user fields");
        return (HttpStatusCode.OK, """{"id":7000000001,"status":"watching","episodes":4,"score":8,"target_id":1}""");
    }
    if (path == "/api/v2/user_rates" || path == "/api/v2/user_rates/7000000000")
    {
        Check(request.Method == (path.EndsWith("7000000000") ? HttpMethod.Put : HttpMethod.Post), "Correct write method");
        Check(request.Content?.Headers.ContentType?.MediaType == "application/json", "JSON write content");
        using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
        var rate = body.RootElement.GetProperty("user_rate");
        Check(rate.GetProperty("status").GetString() == "on_hold", "String status enum");
        Check(rate.GetProperty("episodes").GetInt32() == 3 && rate.GetProperty("score").GetInt32() == 8, "Progress and rating");
        Check(rate.GetProperty("target_type").GetString() == "Anime", "Target enum");
        return (HttpStatusCode.OK, """{"id":7000000000,"status":"on_hold","episodes":3,"score":8,"target_id":1,"target_type":"Anime","user_id":42}""");
    }
    if (path == "/oauth/token")
    {
        Check(request.Method == HttpMethod.Post && string.IsNullOrEmpty(request.RequestUri.Query), "Secret-free token URL");
        var body = await request.Content!.ReadAsStringAsync();
        Check(body.Contains("test-secret") && body.Contains("test-code") && body.Contains("urn:ietf:wg:oauth:2.0:oob"), "OAuth form fields");
        return (HttpStatusCode.OK, """{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}""");
    }
    return (HttpStatusCode.Unauthorized, "sensitive server text");
});
using var http = new HttpClient(handler);
var adapter = new ShikimoriAdapter(http);
var posters = (AnimePoster[])await adapter.Execute(Request("catalog.posters", new { animeIDs = new long[] { 1, 2, 3, 1 } }));
Check(posters.Length == 3 && posters[0].ImageURL!.StartsWith("https://"), "Poster URL normalization");
Check(posters[1].ImageURL == null && posters[2].ImageURL == null, "Missing and insecure artwork fallback");
posterFailure = true;
try
{
    await adapter.Execute(Request("catalog.posters", new { animeIDs = new long[] { 1, 2, 3 } }));
    throw new InvalidOperationException("GraphQL errors must not be treated as missing artwork");
}
catch (InvalidDataException) { }
var posterCalls = calls;
try
{
    await adapter.Execute(Request("catalog.posters", new { animeIDs = new long[] { 0 } }));
    throw new InvalidOperationException("Invalid poster IDs must be rejected");
}
catch (ArgumentException) { }
Check(calls == posterCalls, "Poster validation happens before HTTP");
var search = (AnimeSummary[])await adapter.Execute(Request("catalog.search", new { query = "A & B/+?", page = 2 }));
Check(search is [{ Id: 1, Episodes: 12, CommunityScore: 8.25 }], "Normalized catalog");
var details = (AnimeDetails)await adapter.Execute(Request("anime.details", new { animeID = 1 }));
Check(details.Identity.Year == 2002 && details.Identity.Kind == "tv", "Matching identity metadata");
Check(details.Identity.Titles.Length == 6 && details.Identity.Titles.Contains("Alternative Title"), "All title aliases survive the bridge");
var list = (ListEntry[])await adapter.Execute(Request("watchlist.list", new { userID = 42, status = "on_hold", accessToken = "test-access" }));
Check(list is [{ Rate.Id: 7000000000, Rate.Status: "on_hold" }], "Normalized list and long IDs");
foreach (long? id in new long?[] { null, 7000000000 })
{
    var rate = (UserRateSummary)await adapter.Execute(Request("watchlist.save", new
    { userID = 42, animeID = 1, rateID = id, status = "on_hold", episodes = 3, score = 8, accessToken = "test-access" }));
    Check(rate.Id == 7000000000 && rate.AnimeID == 1, "Object write response");
}
var progressRate = (UserRateSummary)await adapter.Execute(Request("watchlist.progress", new
{ animeID = 1, rateID = 7000000001, episodes = 4, accessToken = "test-access" }));
Check(progressRate.Episodes == 4 && progressRate.Score == 8, "Progress-only response");
var tokens = (TokenPair)await adapter.Execute(Request("account.exchange", new
{ clientID = "test-client", clientSecret = "test-secret", code = "test-code" }));
Check(tokens.RefreshToken == "new-refresh" && tokens.ExpiresAt > DateTimeOffset.UtcNow.ToUnixTimeSeconds(), "Normalized token lifetime");
var before = calls;
try
{
    await adapter.Execute(Request("account.whoami", new { accessToken = "test-access" }));
    throw new InvalidOperationException("Expected unauthorized");
}
catch (ShikimoriRequestException error) { Check(error.StatusCode == HttpStatusCode.Unauthorized, "Typed HTTP error"); }
Check(calls == before + 1, "No implicit retry or token refresh");
Console.WriteLine("Shikimori adapter checks passed: query encoding, list filters, long IDs, JSON writes, OAuth, no retries.");

sealed class StubHandler(Func<HttpRequestMessage, Task<(HttpStatusCode, string)>> action) : HttpMessageHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var (status, body) = await action(request);
        return new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
    }
}
