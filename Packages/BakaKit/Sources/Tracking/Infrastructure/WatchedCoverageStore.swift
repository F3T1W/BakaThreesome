import Foundation

/// Account and numbering scoped checkpoints; corrupt data is preserved instead of overwritten.
public actor WatchedCoverageStore {
    private struct Archive: Codable {
        var version = 1
        var records: [WatchedCoverageRecord] = []
    }
    private let file: URL
    private var cached: Archive?
    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BakaThreesome/watched-coverage.json")
    }

    public func state(for episode: WatchedEpisode) throws -> WatchedCoverageState? {
        guard episode.isValid else { throw CocoaError(.coderInvalidValue) }
        return try archive().records.first {
            $0.episode.userID == episode.userID && $0.episode.context.id == episode.context.id && $0.episode.number == episode.number
        }?.state
    }

    public func save(_ record: WatchedCoverageRecord) throws {
        guard record.isValid else { throw CocoaError(.coderInvalidValue) }
        var value = try archive()
        if let index = value.records.firstIndex(where: { $0.id == record.id }) {
            let previous = value.records[index]
            guard record.updatedAt >= previous.updatedAt else { return }
            value.records[index] = WatchedCoverageRecord(episode: record.episode,
                                                         state: previous.state.merging(record.state), updatedAt: record.updatedAt)
        } else { value.records.append(record) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        cached = value
    }

    private func archive() throws -> Archive {
        if let cached { return cached }
        let value = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file)) : Archive()
        guard value.version == 1, value.records.allSatisfy(\.isValid),
              Set(value.records.map(\.id)).count == value.records.count else { throw CocoaError(.coderReadCorrupt) }
        cached = value
        return value
    }
}
