public enum ServiceAccount: String, CaseIterable, Sendable {
    case shikimori
    case kinopub

    public var displayName: String {
        switch self {
        case .shikimori: "Shikimori"
        case .kinopub: "Kinopub"
        }
    }
}
