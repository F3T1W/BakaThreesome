import Catalog
import Foundation
import Kinopub

public struct AnimeMatchAssessment: Sendable {
    public let reasons: [String]
    public let warnings: [String]
    public let score: Int
    public let isExact: Bool
    public let allowsAutomatic: Bool

    public init(item: KinopubTitle, anime: AnimeIdentity, additionalTitles: [String] = []) {
        let source = AnimeTitleNormalizer.unique(anime.titles + additionalTitles)
        let exact = Set(source.map(AnimeTitleNormalizer.normalize))
        let matched = item.titles.first { exact.contains(AnimeTitleNormalizer.normalize($0)) }
        isExact = matched != nil
        var reasons: [String] = []
        var warnings: [String] = []
        var score = matched == nil ? 0 : 200
        if let matched { reasons.append("Exact title or alias: " + matched) }
        else {
            let sourceTokens = source.map { Set(AnimeTitleNormalizer.normalize($0).split(separator: " ")) }
            let similar = item.titles.contains { title in
                let tokens = Set(AnimeTitleNormalizer.normalize(title).split(separator: " "))
                return sourceTokens.contains {
                    let common = $0.intersection(tokens).count
                    return common >= 2 && Double(common) / Double(max($0.count, tokens.count)) >= 0.65
                }
            }
            if similar { reasons.append("Similar title words; confirmation required"); score += 60 }
            else { warnings.append("No exact title or alias match") }
        }
        let sameYear = anime.year != nil && anime.year == item.year
        if sameYear { reasons.append("Release year matches"); score += 25 }
        else if let expected = anime.year, let actual = item.year {
            warnings.append("Release year differs: Shikimori \(expected), Kinopub \(actual). Check for a remake or sequel.")
            score -= 70
        } else { warnings.append("Release year is not verified") }

        let episodic = ["tv", "ova", "ona", "special", "tv_special"].contains(anime.kind)
        let expected: KinopubFormat? = anime.kind == "movie" ? .movie : (episodic ? .series : nil)
        let actual = item.format ?? (item.seasons.isEmpty ? nil : .series)
        let sameFormat = expected != nil && expected == actual
        if sameFormat { reasons.append(actual == .movie ? "Movie format matches" : "Episode-based format matches"); score += 30 }
        else if expected != nil, actual != nil { warnings.append("Movie and episode-based formats differ"); score -= 150 }
        else { warnings.append("Kinopub format is not verified") }
        if ["ova", "ona", "special", "tv_special"].contains(anime.kind) {
            warnings.append("Confirm this edition and episode numbering for \(anime.kind.uppercased())")
        }
        if item.format == .movie, !item.seasons.isEmpty {
            warnings.append("Movie metadata conflicts with discovered seasons")
        }
        if item.seasons.count > 1 { warnings.append("Multiple Kinopub seasons; choose the correct season") }

        let sourceSeasons = Set(anime.titles.compactMap(AnimeMatchAssessment.seasonNumber))
        let targetSeasons = Set(item.titles.compactMap(AnimeMatchAssessment.seasonNumber))
        let seasonVerified: Bool
        if sourceSeasons.count > 1 || targetSeasons.count > 1 {
            seasonVerified = false
            warnings.append("Conflicting season markers in title aliases")
        } else if let number = sourceSeasons.first {
            seasonVerified = targetSeasons == sourceSeasons || (targetSeasons.isEmpty && item.seasons == [number])
            if seasonVerified { reasons.append("Season marker matches: \(number)") }
            else { warnings.append("Season \(number) is not verified on this Kinopub title"); score -= 60 }
        } else if !targetSeasons.isEmpty {
            seasonVerified = false
            warnings.append("Kinopub has a season marker absent from Shikimori aliases"); score -= 60
        } else { seasonVerified = true }
        self.reasons = reasons
        self.warnings = warnings
        self.score = score
        allowsAutomatic = isExact && sameYear && sameFormat && seasonVerified && anime.kind == "tv"
            && item.seasons.count == 1 && warnings.isEmpty
    }

    static func seasonNumber(_ title: String) -> Int? {
        let normalized = AnimeTitleNormalizer.normalize(title)
        for pattern in ["(?:^| )season ([0-9]{1,3})(?: |$)", "(?:^| )([0-9]{1,3})(?:st|nd|rd|th) season(?: |$)"] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
               let range = Range(match.range(at: 1), in: normalized), let number = Int(normalized[range]), number > 0 { return number }
        }
        return nil
    }
}
