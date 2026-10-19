import Foundation
@testable import Playback
import Testing

@Test func openingSkipRequiresAnExplicitLabelAndTheNextChapterBoundary() throws {
    let chapters = [PlaybackChapter(title: "Prologue", seconds: 0), PlaybackChapter(title: "02. Opening", seconds: 30),
                    PlaybackChapter(title: "Episode", seconds: 120), PlaybackChapter(title: "Ending", seconds: 1300)]
    let opening = try #require(OpeningSegment.from(chapters: chapters).first)
    #expect(opening.start == 30)
    #expect(opening.end == 120)
    #expect(!opening.contains(29))
    #expect(opening.contains(30))
    #expect(!opening.contains(120))
    for title in ["Chapter 1", "Episode", "Opening scene", "Ending", ""] {
        #expect(OpeningSegment.from(chapters: [.init(title: title, seconds: 0), .init(title: "Story", seconds: 90)]).isEmpty)
    }
    for title in ["OP", "OP 2", "Intro", "Opening credits"] {
        #expect(!OpeningSegment.from(chapters: [.init(title: title, seconds: 0), .init(title: "Story", seconds: 90)]).isEmpty)
    }
    #expect(OpeningSegment.from(chapters: [.init(title: "OP", seconds: 0)]).isEmpty)
    #expect(OpeningSegment.from(chapters: [.init(title: "OP", seconds: 100), .init(title: "Story", seconds: 90)]).isEmpty)
    #expect(OpeningSegment.from(chapters: [.init(title: "OP", seconds: 0), .init(title: "Story", seconds: 600)]).isEmpty)
    #expect(OpeningSegment.from(chapters: [.init(title: "OP", seconds: .nan), .init(title: "Story", seconds: 90)]).isEmpty)
}

@Test func chapterDecodingRejectsInvalidTimesAndDoesNotExposeAddresses() throws {
    let chapters = try MPVPlaybackEngine.decodeChapters(.array([
        .object(["time": .number(0), "title": .string("Opening")]),
        .object(["time": .number(90), "title": .string("https://example.com/?token=synthetic")])
    ]))
    #expect(chapters[0].title == "Opening")
    #expect(chapters[1].title.isEmpty)
    #expect(throws: PlaybackError.invalidResponse) {
        try MPVPlaybackEngine.decodeChapters(.array([.object(["time": .number(-1)])]))
    }
}
