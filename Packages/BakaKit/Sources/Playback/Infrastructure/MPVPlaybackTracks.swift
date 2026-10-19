import Foundation

extension MPVPlaybackEngine: PlaybackTrackController {
    public func tracks() async throws -> [PlaybackTrack] {
        let current = try runningSession()
        let value = try await command([.string("get_property"), .string("track-list")])
        try ensureCurrent(current.id)
        return try Self.decodeTracks(value)
    }

    public func selectTrack(_ id: Int?, kind: PlaybackTrackKind) async throws {
        let current = try runningSession()
        if let id {
            guard try await tracks().contains(where: { $0.id == id && $0.kind == kind }) else {
                throw PlaybackError.propertyUnavailable
            }
        }
        try ensureCurrent(current.id)
        _ = try await command([.string("set_property"), .string(kind == .audio ? "aid" : "sid"),
                               id.map { .number(Double($0)) } ?? .string("no")])
        try ensureCurrent(current.id)
        if kind == .subtitle, id != nil {
            _ = try await command([.string("set_property"), .string("sub-visibility"), .bool(true)])
            try ensureCurrent(current.id)
        }
    }

    static func decodeTracks(_ value: MPVValue) throws -> [PlaybackTrack] {
        guard case .array(let items) = value, items.count <= 512 else { throw PlaybackError.invalidResponse }
        return try items.compactMap { item in
            guard case .object(let fields) = item else { throw PlaybackError.invalidResponse }
            let kind: PlaybackTrackKind
            switch fields["type"] {
            case .string("audio"): kind = .audio
            case .string("sub"): kind = .subtitle
            default: return nil
            }
            guard case .number(let number) = fields["id"], number.isFinite,
                  number > 0, number <= Double(Int32.max), number.rounded() == number else {
                throw PlaybackError.invalidResponse
            }
            func text(_ key: String, in values: [String: MPVValue] = fields) -> String? {
                guard case .string(let value) = values[key], !value.contains("://") else { return nil }
                return String(value.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.prefix(256))
            }
            let metadata: [String: MPVValue]
            if case .object(let values) = fields["metadata"] { metadata = values }
            else { metadata = [:] }
            let title = text("title") ?? text("title", in: metadata) ?? text("comment", in: metadata)
            return PlaybackTrack(id: Int(number), kind: kind, title: title, language: text("lang"),
                                 isSelected: fields["selected"] == .bool(true),
                                 isDefault: fields["default"] == .bool(true), isForced: fields["forced"] == .bool(true))
        }
    }
}
