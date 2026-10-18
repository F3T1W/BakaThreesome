import Foundation
import Kinopub
import Testing

@Test func browserSourcesKeepPlaybackTokensOutOfLabelsAndReferrers() throws {
    let candidate = try #require(BrowserMediaCandidate(
        address: "https://media.example/stream/master.m3u8?token=synthetic-secret#fragment",
        pageAddress: "https://mirror.example:443/watch/1?session=synthetic-session#episode",
        source: "Resource"))
    #expect(candidate.url.query == "token=synthetic-secret")
    #expect(candidate.displayName == "M3U8 · media.example · Resource")
    #expect(candidate.referrerOrigin?.path == "/")
    #expect(candidate.referrerOrigin?.query == nil)
    #expect(candidate.referrerOrigin?.fragment == nil)
}

@Test(arguments: ["blob:https://example.com/id", "javascript:alert(1)", "file:///etc/passwd",
                  "http://example.com/video.mp4", "https://user:secret@example.com/video.mp4"])
func browserRejectsUnusableOrCredentialBearingSources(_ address: String) {
    #expect(BrowserMediaCandidate(address: address, pageAddress: "https://mirror.example/watch", source: "Video") == nil)
}

@Test func identifiesThePlayerMasterRatherThanItsCDNTracks() throws {
    let master = try #require(BrowserMediaCandidate(
        address: "https://mirror.example/manifest/hls4/synthetic/123.m3u8?loc=nl",
        pageAddress: "https://mirror.example/item/view/123/s1e1", source: "Video"))
    #expect(master.isPrimaryManifest)
    #expect(master.displayName.hasPrefix("Player manifest"))
    let child = try #require(BrowserMediaCandidate(
        address: "https://cdn.example/hls/audio/index.m3u8?token=synthetic",
        pageAddress: "https://mirror.example/item/view/123/s1e1", source: "Resource"))
    #expect(!child.isPrimaryManifest)
}
