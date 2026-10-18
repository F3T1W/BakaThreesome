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
        let allTitles = AnimeTitleNormalizer.unique(anime.titles + additionalTitles)
        let queries = Array(allTitles.prefix(12))
        let exact = Set(allTitles.map(AnimeTitleNormalizer.normalize))
        var collected: [Int64: KinopubTitle] = [:]
        var searched: [String] = []
        var inspected: Set<Int64> = []
        var complete = allTitles.count <= 12
        for query in queries {
            try Task.checkCancellation()
            let result = try await catalog.search(query)
            complete = complete && result.isComplete
            searched.append(query)
            for item in result.items where collected[item.id] == nil { collected[item.id] = item }
            let ranked = collected.values.sorted { lhs, rhs in
                let l = rank(lhs, anime: anime, exact: exact)
                let r = rank(rhs, anime: anime, exact: exact)
                return l == r ? lhs.id < rhs.id : l > r
            }
            // Fetch season information only for exact title candidates, never for every broad search hit.
            let exactCandidates = ranked.filter { matchesTitle($0, exact: exact) }
            if allowAutomatic, exactCandidates.count == 1, let first = exactCandidates.first,
               let year = anime.year, first.year == year, anime.kind == "tv", complete {
                var detail = first
                if inspected.insert(first.id).inserted {
                    detail = try await catalog.details(first)
                    collected[detail.id] = detail
                }
                if detail.seasons.count == 1, let season = detail.seasons.first {
                    return AnimeMatchResult(
                        candidates: [detail],
                        automatic: EpisodeMapping(animeID: AnimeID(rawValue: anime.id),
                                                  kinopubItemID: detail.id, season: season, episodeOffset: 0),
                        queries: searched, isComplete: complete
                    )
                }
            }
        }
        let ranked = collected.values.sorted { lhs, rhs in
            let l = rank(lhs, anime: anime, exact: exact)
            let r = rank(rhs, anime: anime, exact: exact)
            return l == r ? lhs.id < rhs.id : l > r
        }
        return AnimeMatchResult(candidates: ranked, automatic: nil, queries: searched, isComplete: complete)
    }

    private func matchesTitle(_ item: KinopubTitle, exact: Set<String>) -> Bool {
        item.titles.contains { exact.contains(AnimeTitleNormalizer.normalize($0)) }
    }

    private func rank(_ item: KinopubTitle, anime: AnimeIdentity, exact: Set<String>) -> Int {
        (matchesTitle(item, exact: exact) ? 100 : 0) + (anime.year != nil && anime.year == item.year ? 20 : 0)
    }
}
