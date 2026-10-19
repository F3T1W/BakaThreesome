import Foundation
@testable import BakaUI
import Testing

@MainActor
struct StreamDiagnosticProbeTests {
    @Test func resumeProbeSelectsTheSegmentCoveringTheSavedPosition() {
        let base = URL(string: "https://cdn.example/video/index.m3u8?private=synthetic")!
        let body = """
        #EXTM3U
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:4.5,
        first.ts?token=synthetic
        #EXTINF:5.5,
        second.ts
        #EXTINF:3,
        third.ts
        #EXT-X-ENDLIST
        """
        #expect(StreamDiagnosticProbe.segment(at: 0, in: body, base: base)?.lastPathComponent == "first.ts")
        #expect(StreamDiagnosticProbe.segment(at: 4.5, in: body, base: base)?.lastPathComponent == "second.ts")
        #expect(StreamDiagnosticProbe.segment(at: 9.9, in: body, base: base)?.lastPathComponent == "second.ts")
        #expect(StreamDiagnosticProbe.segment(at: 10, in: body, base: base)?.lastPathComponent == "third.ts")
        #expect(StreamDiagnosticProbe.segment(at: 13, in: body, base: base) == nil)
    }

    @Test func probeRejectsCredentialBearingAndNonHTTPSMedia() {
        let base = URL(string: "https://cdn.example/index.m3u8")!
        for address in ["http://cdn.example/video.ts", "https://user:secret@cdn.example/video.ts", "file:///tmp/video.ts"] {
            #expect(StreamDiagnosticProbe.segment(at: 0, in: "#EXTINF:3,\n" + address, base: base) == nil)
        }
        for length in ["nan", "inf", "-1", "0", "invalid"] {
            #expect(StreamDiagnosticProbe.segment(at: 0, in: "#EXTINF:\(length),\nvideo.ts", base: base) == nil)
        }
    }
}
