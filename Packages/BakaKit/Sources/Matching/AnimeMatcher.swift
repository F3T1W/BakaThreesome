import Catalog
import Foundation
import Kinopub

public enum AnimeTitleNormalizer {
    public static func normalize(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        // Accent-insensitive Latin matching must not erase meaningful kana or Cyrillic marks.
        let normalized = folded.map { character -> String in
            let value = String(character)
            guard let base = value.decomposedStringWithCanonicalMapping.unicodeScalars.first,
                  (65...90).contains(base.value) || (97...122).contains(base.value) else { return value }
            return value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }.joined()
        return normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func unique(_ titles: [String]) -> [String] {
        var seen: Set<String> = []
        return titles.compactMap { title in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(trimmed)
            return !key.isEmpty && seen.insert(key).inserted ? trimmed : nil
        }
    }
}

public struct AnimeMatchResult: Sendable {
    public let candidates: [KinopubTitle]
    public let automatic: EpisodeMapping?
    public let queries: [String]
    public let isComplete: Bool
}

public struct AnimeMatcher: Sendable {
    private let catalog: any KinopubCatalog
    public init(catalog: any KinopubCatalog) { self.catalog = catalog }

    public func find(_ anime: AnimeIdentity, additionalTitles: [String] = [], allowAutomatic: Bool = true) async throws -> AnimeMatchResult {
        let names = AnimeTitleNormalizer.unique(additionalTitles + anime.titles)
        // Broader queries are discovery aids, never trusted aliases for automatic matching.
        let normalizedNames = Set(names.map(AnimeTitleNormalizer.normalize))
        let broader = AnimeTitleNormalizer.unique(names.map {
            $0.replacingOccurrences(of: "(?i)\\s*\\((?:tv|movie|ova|ona)\\)\\s*$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "(?i)\\b(?:season\\s+\\d+|\\d+(?:st|nd|rd|th)\\s+season)\\b", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }).filter { !normalizedNames.contains(AnimeTitleNormalizer.normalize($0)) }
        let planned = AnimeTitleNormalizer.unique(names + broader.prefix(4))
        let queries = Array(planned.prefix(12))
        var collected: [Int64: KinopubTitle] = [:]
        var complete = planned.count <= 12
        var conflictingYears: Set<Int64> = []
        for query in queries {
            try Task.checkCancellation()
            let result = try await catalog.search(query)
            complete = complete && result.isComplete
            for item in result.items {
                if let previous = collected[item.id] {
                    if let year = previous.year, let nextYear = item.year, year != nextYear { conflictingYears.insert(item.id) }
                    collected[item.id] = KinopubTitle(id: item.id,
                        titles: AnimeTitleNormalizer.unique(previous.titles + item.titles),
                        year: conflictingYears.contains(item.id) ? nil : (previous.year ?? item.year),
                        seasons: Array(Set(previous.seasons + item.seasons)).sorted(),
                        format: previous.format ?? item.format)
                } else { collected[item.id] = item }
            }
        }
        try Task.checkCancellation()
        func assessment(_ item: KinopubTitle) -> AnimeMatchAssessment {
            AnimeMatchAssessment(item: item, anime: anime, additionalTitles: additionalTitles)
        }
        var assessments = collected.mapValues { assessment($0) }
        var automatic: EpisodeMapping?
        let exact = collected.values.filter { assessments[$0.id]?.isExact == true }
        if allowAutomatic, complete, exact.count == 1, let first = exact.first,
           first.year == anime.year, anime.year != nil, anime.kind == "tv" {
            let detail = try await catalog.details(first)
            try Task.checkCancellation()
            guard detail.id == first.id else { throw KinopubSearchError.unsupportedPage }
            collected[detail.id] = detail
            let verified = assessment(detail)
            assessments[detail.id] = verified
            if verified.allowsAutomatic, let season = detail.seasons.first {
                automatic = EpisodeMapping(animeID: AnimeID(rawValue: anime.id), kinopubItemID: detail.id,
                                           season: season, episodeOffset: 0)
            }
        }
        let ranked = collected.values.sorted {
            let lhs = assessments[$0.id]?.score ?? 0, rhs = assessments[$1.id]?.score ?? 0
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
        return AnimeMatchResult(candidates: ranked, automatic: automatic, queries: queries, isComplete: complete)
    }
}
