import Foundation

extension MPVPlaybackEngine: PlaybackChapterController {
    public func chapters() async throws -> [PlaybackChapter] {
        let current = try runningSession()
        let value = try await command([.string("get_property"), .string("chapter-list")])
        try ensureCurrent(current.id)
        return try Self.decodeChapters(value)
    }

    static func decodeChapters(_ value: MPVValue) throws -> [PlaybackChapter] {
        guard case .array(let entries) = value, entries.count <= 1000 else { throw PlaybackError.invalidResponse }
        return try entries.map {
            guard case .object(let fields) = $0, case .number(let time) = fields["time"], time.isFinite, time >= 0 else {
                throw PlaybackError.invalidResponse
            }
            let title: String
            if case .string(let text) = fields["title"], text.utf8.count <= 1024, !text.contains("://") { title = text }
            else { title = "" }
            return PlaybackChapter(title: title, seconds: time)
        }
    }
}
