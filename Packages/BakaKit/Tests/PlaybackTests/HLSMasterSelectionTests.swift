import Foundation
@testable import Playback
import Testing

struct HLSMasterSelectionTests {
    private let base = URL(string: "https://cdn.example/master.m3u8")!
    private var master: String {
        """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=9000000,URI="iframe.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="low",NAME="1. Original",LANGUAGE="ja",DEFAULT=YES,URI="low-ja.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="low",NAME="2. Dub",LANGUAGE="ru",URI="low-ru.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="high",NAME="3. Original",LANGUAGE="ja",DEFAULT=NO,URI="high-ja.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="high",NAME="4. Dub",LANGUAGE="ru",URI="high-ru.m3u8"
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Russian, full",LANGUAGE="ru",URI="ru.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=100000,CODECS="avc1.42c00b,mp4a.40.2",AUDIO="low",SUBTITLES="subs",CLOSED-CAPTIONS=NONE
        low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=800000,CODECS="avc1.42c00b,mp4a.40.2",AUDIO="high",SUBTITLES="subs",CLOSED-CAPTIONS=NONE
        high.m3u8
        """
    }

    @Test func equivalentProgramsKeepHighestQualityAllVoicesAndSubtitles() throws {
        let result = try #require(HLSMasterSelection.reduce(master, base: base))
        #expect(result.programCount == 2)
        #expect(result.renditionCount == 3)
        #expect(result.content.contains("https://cdn.example/high.m3u8"))
        #expect(result.content.contains("https://cdn.example/high-ja.m3u8"))
        #expect(result.content.contains("https://cdn.example/high-ru.m3u8"))
        #expect(result.content.contains("Russian, full"))
        #expect(!result.content.contains("low.m3u8"))
        #expect(result.content.components(separatedBy: "#EXT-X-STREAM-INF:").count == 2)
    }

    @Test func uniqueVoicesUnsupportedMetadataAndInsecureChildrenRetainOriginal() {
        for text in [
            master.replacingOccurrences(of: "4. Dub", with: "Different studio"),
            master + "\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key\"",
            master.replacingOccurrences(of: "high-ru.m3u8", with: "http://cdn.example/audio.m3u8"),
            master.replacingOccurrences(of: "high.m3u8", with: "https://user:secret@cdn.example/high.m3u8"),
            master.replacingOccurrences(of: "BANDWIDTH=800000", with: "BANDWIDTH=800000,BANDWIDTH=9")
        ] {
            #expect(HLSMasterSelection.reduce(text, base: base) == nil)
        }
    }
}
