using System.Text.Json;
using System.Text.Json.Nodes;
using BakaThreesome.Bridge.Contracts;

namespace BakaThreesome.ShikimoriBridge.Checks;

internal static class WireContractChecks
{
    // The same fixture is decoded by Swift. C# naming changes must preserve this schema.
    public static void Run()
    {
        var fixture = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "bridge-v1.json")))!;
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var anime = new AnimeSummary(1, "Example", 12, "tv", 8.25);
        var rate = new UserRateSummary(7000000000, 1, "on_hold", 3, 8);
        var identity = new AnimeIdentity(1, ["Example", "Alternative Title"], 2002, "tv");
        var results = new Dictionary<string, object>
        {
            ["catalog"] = new[] { anime },
            ["posters"] = new AnimePoster[]
            {
                new(1, "https://shikimori.io/uploads/poster/animes/1/main.webp"), new(2, null), new(3, null)
            },
            ["details"] = new AnimeDetails(anime, rate, identity),
            ["list"] = new[] { new ListEntry(anime, rate) },
            ["rate"] = rate,
            ["profile"] = new UserProfile(42, "Example"),
            ["tokens"] = new TokenPair("synthetic-access", "synthetic-refresh", 2000000000),
            ["handshake"] = new HandshakeResult("BakaThreesome.ShikimoriBridge", ["handshake"])
        };
        foreach (var (name, result) in results)
        {
            var actual =
                JsonSerializer.SerializeToNode(new BridgeResponse(Protocol.Version, "fixture", result), options);
            var expected = new JsonObject
            {
                ["version"] = 1, ["id"] = "fixture", ["result"] = fixture[name]!.DeepClone(), ["error"] = null
            };
            RequireEqual(actual, expected, name);
        }

        var error = new BridgeError("unauthorized", "Sign in to Shikimori again.");
        RequireEqual(JsonSerializer.SerializeToNode(error, options), fixture["error"], "error");
    }

    private static void RequireEqual(JsonNode? actual, JsonNode? expected, string name)
    {
        if (!JsonNode.DeepEquals(actual, expected))
            throw new InvalidOperationException($"The {name} response no longer matches the Swift wire contract.");
    }
}
