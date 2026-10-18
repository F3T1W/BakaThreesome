import Catalog
import Foundation

public actor EpisodeMappingStore {
    private let file: URL
    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BakaThreesome/episode-mappings.json")
    }

    public func mapping(for animeID: Int64) throws -> EpisodeMapping? {
        try read().first { $0.animeID.rawValue == animeID }
    }

    public func save(_ mapping: EpisodeMapping) throws {
        guard valid(mapping) else { throw CocoaError(.coderInvalidValue) }
        var values = try read().filter { $0.animeID != mapping.animeID }
        values.append(mapping)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(values.sorted { $0.animeID.rawValue < $1.animeID.rawValue })
        try data.write(to: file, options: .atomic)
    }

    private func read() throws -> [EpisodeMapping] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let values = try JSONDecoder().decode([EpisodeMapping].self, from: Data(contentsOf: file))
        guard values.allSatisfy(valid), Set(values.map(\.animeID)).count == values.count else {
            throw CocoaError(.coderReadCorrupt)
        }
        return values
    }

    private func valid(_ value: EpisodeMapping) -> Bool {
        value.animeID.rawValue > 0 && value.kinopubItemID > 0
            && (0...999).contains(value.season) && (0...10000).contains(value.episodeOffset)
    }
}
