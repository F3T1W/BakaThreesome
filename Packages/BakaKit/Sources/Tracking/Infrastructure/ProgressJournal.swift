import Foundation

/// A small atomic outbox. It contains only title IDs, confirmed numbering and completed episode numbers.
public actor ProgressJournal {
    private let file: URL
    private var cached: ProgressJournalSnapshot?
    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BakaThreesome/progress-sync.json")
    }
    public func snapshot() throws -> ProgressJournalSnapshot {
        if let cached { return cached }
        let value: ProgressJournalSnapshot
        if FileManager.default.fileExists(atPath: file.path) {
            value = try JSONDecoder().decode(ProgressJournalSnapshot.self, from: Data(contentsOf: file))
        } else { value = ProgressJournalSnapshot() }
        guard value.version == 1, value.numbering.allSatisfy(\.isValid), value.pending.allSatisfy(\.isValid),
              Set(value.numbering.map(\.id)).count == value.numbering.count,
              Set(value.pending.map(\.id)).count == value.pending.count else { throw CocoaError(.coderReadCorrupt) }
        cached = value
        return value
    }
    public func confirm(_ rule: EpisodeNumbering) throws {
        guard rule.isValid else { throw CocoaError(.coderInvalidValue) }
        var value = try snapshot()
        value.numbering.removeAll { $0.id == rule.id }
        value.numbering.append(rule)
        try persist(value)
    }
    public func enqueue(_ episode: WatchedEpisode) throws {
        guard episode.isValid else { throw CocoaError(.coderInvalidValue) }
        var value = try snapshot()
        guard !value.pending.contains(where: { $0.id == episode.id }) else { return }
        value.pending.append(episode)
        try persist(value)
    }
    public func remove(id: String) throws {
        var value = try snapshot()
        value.pending.removeAll { $0.id == id }
        try persist(value)
    }
    private func persist(_ value: ProgressJournalSnapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        cached = value
    }
}

