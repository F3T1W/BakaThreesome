import Foundation

public struct PlaybackChapter: Equatable, Sendable {
    public let title: String
    public let seconds: Double
    public init(title: String, seconds: Double) { self.title = title; self.seconds = seconds }
}

public protocol PlaybackChapterController: Sendable {
    func chapters() async throws -> [PlaybackChapter]
}

public struct OpeningSegment: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public func contains(_ seconds: Double) -> Bool { seconds.isFinite && seconds >= start && seconds < end }

    public static func from(chapters: [PlaybackChapter]) -> [OpeningSegment] {
        guard chapters.count <= 1000, chapters.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 }),
              zip(chapters, chapters.dropFirst()).allSatisfy({ $0.seconds < $1.seconds }) else { return [] }
        return zip(chapters, chapters.dropFirst()).compactMap { chapter, next in
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: "^\\d+[.\\s-]+", with: "", options: .regularExpression)
            guard title.range(of: "^(op(?:\\s*\\d+)?|opening(?:\\s+credits)?|intro)$", options: .regularExpression) != nil,
                  (5...300).contains(next.seconds - chapter.seconds) else { return nil }
            return OpeningSegment(start: chapter.seconds, end: next.seconds)
        }
    }
}
