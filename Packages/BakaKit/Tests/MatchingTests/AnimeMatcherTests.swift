import Catalog
import Foundation
import Kinopub
import Matching
import Testing

private let identity = AnimeIdentity(id: 1, titles: ["Original Title", "Alternative Title"], year: 2002, kind: "tv")

@Test func normalizesPunctuationAndAccentsButPreservesSeasonNumbers() {
    #expect(AnimeTitleNormalizer.normalize("  Títle: Season ２! ") == "title season 2")
    #expect(AnimeTitleNormalizer.normalize("\u{304C}") != AnimeTitleNormalizer.normalize("\u{304B}"))
    #expect(AnimeTitleNormalizer.normalize("\u{0439}") != AnimeTitleNormalizer.normalize("\u{0438}"))
    #expect(AnimeTitleNormalizer.normalize("Title 2") != AnimeTitleNormalizer.normalize("Title"))
    #expect(AnimeTitleNormalizer.unique(["Title!", " title ", "", "Title 2"]) == ["Title!", "Title 2"])
}

@Test func triesAliasesAndAutomaticallyMapsOnlyAnExactUniqueVerifiedSeason() async throws {
    let catalog = StubCatalog(results: ["Alternative Title": [title()]], details: [10: title(seasons: [1])])
    let result = try await AnimeMatcher(catalog: catalog).find(identity)
    #expect(result.queries == ["Original Title", "Alternative Title"])
    #expect(result.automatic?.kinopubItemID == 10)
    #expect(result.automatic?.season == 1)
}

@Test func changingASavedMatchNeverAutomaticallyReopensTheSameCandidate() async throws {
    let item = title(seasons: [1])
    let catalog = StubCatalog(results: ["Original Title": [item]])
    let result = try await AnimeMatcher(catalog: catalog).find(identity, allowAutomatic: false)
    #expect(result.automatic == nil)
    #expect(result.candidates.first?.id == 10)
}

@Test func ambiguousYearsSeasonsAndIncompleteResultsRequireConfirmation() async throws {
    for item in [title(year: 2003, seasons: [1]), title(seasons: [1, 2]), title(seasons: [])] {
        let catalog = StubCatalog(results: ["Original Title": [item]], details: [10: item])
        #expect(try await AnimeMatcher(catalog: catalog).find(identity).automatic == nil)
    }
    let duplicate = KinopubTitle(id: 11, titles: ["Alternative Title"], year: 2002, seasons: [1])
    let ambiguous = StubCatalog(results: ["Original Title": [title(seasons: [1]), duplicate]])
    #expect(try await AnimeMatcher(catalog: ambiguous).find(identity).automatic == nil)
    let truncated = StubCatalog(results: ["Original Title": [title(seasons: [1])]], complete: false)
    let result = try await AnimeMatcher(catalog: truncated).find(identity)
    #expect(result.automatic == nil)
    #expect(!result.isComplete)
}

@Test func searchFailureIsNotReportedAsAnEmptyCatalog() async {
    let catalog = StubCatalog(fails: true)
    await #expect(throws: KinopubSearchError.self) { try await AnimeMatcher(catalog: catalog).find(identity) }
}

@Test func manualAliasParticipatesInSearchAndCancellationStopsFurtherQueries() async throws {
    let catalog = StubCatalog(results: ["New Name": [KinopubTitle(id: 10, titles: ["New Name"], year: 2002, seasons: [1])]])
    let result = try await AnimeMatcher(catalog: catalog).find(identity, additionalTitles: ["New Name"])
    #expect(result.queries.first == "New Name")
    #expect(result.automatic != nil)
    let task = Task { try await AnimeMatcher(catalog: catalog).find(identity) }
    task.cancel()
    do { _ = try await task.value; Issue.record("Expected cancellation") }
    catch is CancellationError { }
}

@Test func confirmedMappingsPersistAndRejectCorruptOrInvalidRecords() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("mappings.json")
    let store = EpisodeMappingStore(file: file)
    try await store.save(EpisodeMapping(animeID: AnimeID(rawValue: 1), kinopubItemID: 10, season: 2, episodeOffset: 0))
    let reopened = EpisodeMappingStore(file: file)
    #expect(try await reopened.mapping(for: 1)?.season == 2)
    try await reopened.save(EpisodeMapping(animeID: AnimeID(rawValue: 1), kinopubItemID: 11, season: 0, episodeOffset: 0))
    #expect(try await store.mapping(for: 1)?.kinopubItemID == 11)
    await #expect(throws: (any Error).self) {
        try await store.save(EpisodeMapping(animeID: AnimeID(rawValue: -1), kinopubItemID: 10, season: 1, episodeOffset: 0))
    }
    try Data("invalid".utf8).write(to: file)
    await #expect(throws: (any Error).self) { try await store.mapping(for: 1) }
}

private func title(year: Int = 2002, seasons: [Int] = []) -> KinopubTitle {
    KinopubTitle(id: 10, titles: ["Alternative Title"], year: year, seasons: seasons)
}

private actor StubCatalog: KinopubCatalog {
    let results: [String: [KinopubTitle]]
    let enriched: [Int64: KinopubTitle]
    let complete: Bool
    let fails: Bool
    init(results: [String: [KinopubTitle]] = [:], details: [Int64: KinopubTitle] = [:], complete: Bool = true, fails: Bool = false) {
        self.results = results; self.enriched = details; self.complete = complete; self.fails = fails
    }
    func search(_ query: String) throws -> KinopubSearchResults {
        if fails { throw KinopubSearchError.unavailable }
        return KinopubSearchResults(items: results[query] ?? [], isComplete: complete)
    }
    func details(_ item: KinopubTitle) -> KinopubTitle { enriched[item.id] ?? item }
}

@Test func laterAliasesCanRevealAmbiguityBeforeAutomaticOpening() async throws {
    let first = title(seasons: [1])
    let later = KinopubTitle(id: 11, titles: ["Alternative Title"], year: 2002, seasons: [1])
    let catalog = StubCatalog(results: ["Original Title": [first], "Alternative Title": [later]])
    let result = try await AnimeMatcher(catalog: catalog).find(identity)
    #expect(result.queries.count == 2)
    #expect(result.automatic == nil)
    #expect(result.candidates.count == 2)
}

@Test func manualQueryHasPriorityEvenWhenOfficialAliasesExhaustTheBudget() async throws {
    let anime = AnimeIdentity(id: 1, titles: (1...15).map { "Alias \($0)" }, year: 2002, kind: "tv")
    let catalog = StubCatalog(results: ["Manual Name": [title(seasons: [1])]])
    let result = try await AnimeMatcher(catalog: catalog).find(anime, additionalTitles: ["Manual Name"])
    #expect(result.queries.first == "Manual Name")
    #expect(result.queries.count == 12)
    #expect(!result.isComplete)
    #expect(result.automatic == nil)
}

@Test func broaderSeasonQueriesFindCandidatesButDoNotBecomeTrustedAliases() async throws {
    let anime = AnimeIdentity(id: 1, titles: ["Blue Sky Season 2"], year: 2002, kind: "tv")
    let item = KinopubTitle(id: 10, titles: ["Blue Sky"], year: 2002, seasons: [1, 2])
    let catalog = StubCatalog(results: ["Blue Sky": [item]])
    let result = try await AnimeMatcher(catalog: catalog).find(anime)
    #expect(result.queries == ["Blue Sky Season 2", "Blue Sky"])
    #expect(result.candidates.first?.id == 10)
    #expect(result.automatic == nil)
    #expect(!AnimeMatchAssessment(item: item, anime: anime).isExact)
}

@Test func assessmentsExplainRemakesFormatsAndUnverifiedSeasons() async throws {
    let movie = KinopubTitle(id: 10, titles: ["Original Title"], year: 2002, seasons: [1], format: .movie)
    let movieAssessment = AnimeMatchAssessment(item: movie, anime: identity)
    #expect(!movieAssessment.allowsAutomatic)
    #expect(movieAssessment.warnings.contains { $0.contains("formats differ") })
    let remade = AnimeMatchAssessment(item: title(year: 2020, seasons: [1]), anime: identity)
    #expect(remade.warnings.contains { $0.contains("remake") })
    #expect(!remade.allowsAutomatic)
    let anime = AnimeIdentity(id: 1, titles: ["Blue Sky Season 2", "Blue Sky"], year: 2002, kind: "tv")
    let wrongSeason = KinopubTitle(id: 10, titles: ["Blue Sky"], year: 2002, seasons: [1])
    #expect(!AnimeMatchAssessment(item: wrongSeason, anime: anime).allowsAutomatic)
    let rightSeason = KinopubTitle(id: 10, titles: ["Blue Sky Season 2"], year: 2002, seasons: [1])
    #expect(AnimeMatchAssessment(item: rightSeason, anime: anime).allowsAutomatic)
    let special = AnimeIdentity(id: 1, titles: ["Alternative Title"], year: 2002, kind: "special")
    #expect(!AnimeMatchAssessment(item: title(seasons: [1]), anime: special).allowsAutomatic)
    let catalog = StubCatalog(results: ["Original Title": [movie]], details: [10: movie])
    #expect(try await AnimeMatcher(catalog: catalog).find(identity).automatic == nil)
}

@Test func repeatedCardsMergeAliasesAndConflictingYearsCannotAutomaticallyMatch() async throws {
    let unknown = KinopubTitle(id: 10, titles: ["Unrelated card label"], year: nil)
    let exact = title(seasons: [1])
    let catalog = StubCatalog(results: ["Original Title": [unknown], "Alternative Title": [exact]], details: [10: exact])
    #expect(try await AnimeMatcher(catalog: catalog).find(identity).automatic != nil)
    let conflict = StubCatalog(results: ["Original Title": [title(year: 2020)], "Alternative Title": [exact]])
    #expect(try await AnimeMatcher(catalog: conflict).find(identity).automatic == nil)
}
