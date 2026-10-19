import Foundation

public enum PlaybackTrackKind: String, Codable, Sendable { case audio, subtitle }

public struct PlaybackTrack: Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: PlaybackTrackKind
    public let title: String?
    public let language: String?
    public let isSelected: Bool
    public let isDefault: Bool
    public let isForced: Bool

    public init(id: Int, kind: PlaybackTrackKind, title: String? = nil, language: String? = nil,
                isSelected: Bool = false, isDefault: Bool = false, isForced: Bool = false) {
        self.id = id; self.kind = kind; self.title = title; self.language = language
        self.isSelected = isSelected; self.isDefault = isDefault; self.isForced = isForced
    }

    public var label: String {
        let name = language.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) }
        var parts = [name, title].compactMap { $0 }.filter { !$0.isEmpty }
        if parts.isEmpty { parts = [kind == .audio ? "Audio track \(id)" : "Subtitle track \(id)"] }
        if isForced { parts.append("Forced") }
        return parts.joined(separator: " · ")
    }
}

public protocol PlaybackTrackController: Sendable {
    func tracks() async throws -> [PlaybackTrack]
    func selectTrack(_ id: Int?, kind: PlaybackTrackKind) async throws
}

public struct PlaybackTrackPreference: Codable, Equatable, Sendable {
    public var language: String
    public var title: String?
    public var isEnabled: Bool

    public init(language: String, title: String? = nil, isEnabled: Bool = true) {
        self.language = language; self.title = title; self.isEnabled = isEnabled
    }

    public func preferred(in tracks: [PlaybackTrack], kind: PlaybackTrackKind) -> PlaybackTrack? {
        guard isEnabled else { return nil }
        let candidates = tracks.filter { $0.kind == kind && Self.languageKey($0.language) == Self.languageKey(language) }
        return candidates.sorted { rank($0) == rank($1) ? $0.id < $1.id : rank($0) > rank($1) }.first
    }

    private func rank(_ track: PlaybackTrack) -> Int {
        let titleMatch = title.map { Self.titleKey($0) == Self.titleKey(track.title ?? "") } ?? false
        return (titleMatch ? 100 : 0) + (!track.isForced ? 10 : 0)
            + (track.isSelected ? 4 : 0) + (track.isDefault ? 2 : 0)
    }

    private static func titleKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
    }

    public static func languageKey(_ language: String?) -> String {
        let value = (language ?? "").lowercased().replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init) ?? ""
        switch value {
        case "jpn", "ja": return "ja"
        case "rus", "ru": return "ru"
        case "eng", "en": return "en"
        case "zho", "chi", "zh": return "zh"
        case "kor", "ko": return "ko"
        default: return value
        }
    }
}

public struct PlaybackTrackPreferences: Codable, Equatable, Sendable {
    public var audio: PlaybackTrackPreference
    public var subtitles: PlaybackTrackPreference
    public static let originalWithRussianSubtitles = PlaybackTrackPreferences(
        audio: PlaybackTrackPreference(language: "ja"), subtitles: PlaybackTrackPreference(language: "ru"))

    public init(audio: PlaybackTrackPreference, subtitles: PlaybackTrackPreference) {
        self.audio = audio; self.subtitles = subtitles
    }
}
