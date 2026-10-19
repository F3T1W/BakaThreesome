import Catalog
import Foundation
import Kinopub
import Matching
import Observation
import ShikimoriBridge

@MainActor
@Observable
final class KinopubMatchModel {
    let anime: AnimeSummary
    private(set) var identity: AnimeIdentity?
    private(set) var result: AnimeMatchResult?
    private(set) var selected: KinopubTitle?
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private var searchedAlternativeTitles: [String] = []
    var season = 0
    var alternativeTitle = ""
    var manualAddress = ""
    private let client: ShikimoriClient
    private let catalog = KinopubWebsiteCatalog()
    private let store: EpisodeMappingStore
    private let origin: URL

    init(anime: AnimeSummary, client: ShikimoriClient, store: EpisodeMappingStore, origin: URL) {
        self.anime = anime
        self.client = client
        self.store = store
        self.origin = origin
    }

    var googleURL: URL {
        var url = URLComponents(string: "https://www.google.com/search")!
        url.queryItems = [URLQueryItem(name: "q", value: "\(anime.title) anime alternative titles")]
        return url.url!
    }

    func find(useSaved: Bool, allowAutomatic: Bool = true) async -> EpisodeMapping? {
        guard !isWorking else { return nil }
        isWorking = true
        errorMessage = nil
        selected = nil
        defer { isWorking = false }
        do {
            if useSaved, let mapping = try await store.mapping(for: anime.id) {
                try Task.checkCancellation()
                return mapping
            }
            try catalog.configure(origin: origin)
            if identity == nil {
                let detail = try await client.details(anime.id, accessToken: nil)
                identity = detail.identity ?? AnimeIdentity(id: anime.id, titles: [anime.title], year: nil, kind: anime.kind)
            }
            guard let identity else { return nil }
            let aliases = alternativeTitle.isEmpty ? [] : [alternativeTitle]
            let value = try await AnimeMatcher(catalog: catalog).find(
                identity, additionalTitles: aliases, allowAutomatic: allowAutomatic
            )
            try Task.checkCancellation()
            searchedAlternativeTitles = aliases
            result = value
            if let mapping = value.automatic {
                try await store.save(mapping)
                try Task.checkCancellation()
                return mapping
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { errorMessage = message(error) }
        }
        return nil
    }

    func select(_ item: KinopubTitle) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let value = try await catalog.details(item)
            try Task.checkCancellation()
            selected = value
            season = value.seasons.first ?? 0
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { errorMessage = message(error) }
        }
    }

    func selectManualAddress() async {
        guard let url = URL(string: manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port,
              url.user == nil, url.password == nil else {
            errorMessage = "Enter a title URL from your configured Kinopub mirror."
            return
        }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 3, parts[0] == "item", parts[1] == "view",
              let id = Int64(parts[2]), id > 0 else {
            errorMessage = "Use a Kinopub title page URL containing /item/view/ followed by its ID."
            return
        }
        await select(KinopubTitle(id: id, titles: ["Manually selected title"], year: nil))
    }

    func confirm() async -> EpisodeMapping? {
        guard !isWorking, let selected, selected.seasons.contains(season) || season == 0 else { return nil }
        isWorking = true
        defer { isWorking = false }
        let mapping = EpisodeMapping(animeID: AnimeID(rawValue: anime.id), kinopubItemID: selected.id,
                                     season: season, episodeOffset: 0)
        do {
            try Task.checkCancellation()
            try await store.save(mapping)
            return mapping
        } catch {
            errorMessage = "The title match could not be saved. Check access to Application Support and try again."
            return nil
        }
    }

    func assessment(for item: KinopubTitle) -> AnimeMatchAssessment {
        AnimeMatchAssessment(item: item, anime: identity ?? AnimeIdentity(id: anime.id, titles: [anime.title],
                                                                        year: nil, kind: anime.kind),
                             additionalTitles: searchedAlternativeTitles)
    }

    func clearSelection() { selected = nil }
    func close() { catalog.shutdown() }

    private func message(_ error: Error) -> String {
        if let error = error as? KinopubSearchError { return error.localizedDescription }
        if let error = error as? ShikimoriError { return error.localizedDescription }
        return "The match could not be read or saved. Check your connection and local storage, then try again."
    }
}
