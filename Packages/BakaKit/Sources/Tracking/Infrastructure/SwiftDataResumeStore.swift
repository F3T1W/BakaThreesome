import Catalog
import Foundation
import Playback
import SwiftData

@Model
private final class ResumeRecord {
    @Attribute(.unique) var key: String
    var animeID: Int64
    var title: String
    var kind: String
    var itemID: Int64
    var season: Int
    var episode: Int
    var seconds: Double
    var duration: Double
    var updatedAt: Date

    init(_ entry: ResumeEntry) {
        key = entry.id; animeID = entry.context.animeID.rawValue; title = entry.context.title
        kind = entry.context.kind; itemID = entry.context.kinopubItemID; season = entry.context.season
        episode = entry.context.episode; seconds = entry.position.seconds; duration = entry.position.duration ?? 0
        updatedAt = entry.updatedAt
    }

    var entry: ResumeEntry {
        ResumeEntry(context: EpisodeContext(animeID: AnimeID(rawValue: animeID), title: title, kind: kind,
                                           kinopubItemID: itemID, season: season, episode: episode),
                    position: PlaybackPosition(seconds: seconds, duration: duration), updatedAt: updatedAt)
    }
}

@Model
private final class ResumeTitleCursor {
    @Attribute(.unique) var animeID: Int64
    var episodeID: String
    var updatedAt: Date
    init(_ entry: ResumeEntry) {
        animeID = entry.context.animeID.rawValue; episodeID = entry.id; updatedAt = entry.updatedAt
    }
}

/// Keeps its ModelContext on one actor; UI and player exchange only immutable value types.
public actor SwiftDataResumeStore: ResumeHistoryStore {
    private let file: URL
    private let inMemory: Bool
    private var container: ModelContainer?
    private var context: ModelContext?

    public init(file: URL? = nil, inMemory: Bool = false) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BakaThreesome/playback.store")
        self.inMemory = inMemory
    }

    public func entries() throws -> [ResumeEntry] {
        let values = try modelContext().fetch(FetchDescriptor<ResumeRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        let entries = values.map(\.entry)
        guard entries.allSatisfy(\.isValid) else { throw CocoaError(.coderReadCorrupt) }
        return entries
    }

    public func snapshot() async throws -> ResumeHistorySnapshot {
        let values = try entries()
        let cursors = try modelContext().fetch(FetchDescriptor<ResumeTitleCursor>())
        let latest = Dictionary(uniqueKeysWithValues: cursors.map { ($0.animeID, $0.episodeID) })
        return ResumeHistorySnapshot(entries: values, latestEpisodeIDs: latest)
    }

    public func save(_ entry: ResumeEntry) throws {
        guard entry.isValid else { throw CocoaError(.coderInvalidValue) }
        let context = try modelContext()
        if let record = try record(id: entry.id, in: context) {
            guard record.updatedAt <= entry.updatedAt else { return }
            record.title = entry.context.title; record.kind = entry.context.kind
            record.seconds = entry.position.seconds; record.duration = entry.position.duration ?? 0
            record.updatedAt = entry.updatedAt
        } else {
            context.insert(ResumeRecord(entry))
        }
        do {
            try updateCursor(entry, in: context)
            try context.save()
        }
        catch { context.rollback(); throw error }
    }

    public func remove(id: String) throws {
        let context = try modelContext()
        if let record = try record(id: id, in: context) {
            do {
                try updateCursor(record.entry, in: context)
                context.delete(record)
                try context.save()
            }
            catch { context.rollback(); throw error }
        }
    }

    private func updateCursor(_ entry: ResumeEntry, in context: ModelContext) throws {
        let animeID = entry.context.animeID.rawValue
        var descriptor = FetchDescriptor<ResumeTitleCursor>(predicate: #Predicate { $0.animeID == animeID })
        descriptor.fetchLimit = 1
        if let cursor = try context.fetch(descriptor).first {
            if entry.updatedAt >= cursor.updatedAt { cursor.episodeID = entry.id; cursor.updatedAt = entry.updatedAt }
        } else {
            let all = try context.fetch(FetchDescriptor<ResumeRecord>()).map(\.entry)
                .filter { $0.context.animeID.rawValue == animeID }
            let latest = (all + [entry]).max { $0.updatedAt < $1.updatedAt } ?? entry
            context.insert(ResumeTitleCursor(latest))
        }
    }

    private func record(id: String, in context: ModelContext) throws -> ResumeRecord? {
        var descriptor = FetchDescriptor<ResumeRecord>(predicate: #Predicate { $0.key == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func modelContext() throws -> ModelContext {
        if let context { return context }
        let schema = Schema([ResumeRecord.self, ResumeTitleCursor.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: file, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.container = container
        self.context = context
        return context
    }
}
