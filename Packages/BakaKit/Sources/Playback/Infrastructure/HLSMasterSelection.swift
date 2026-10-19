import Foundation

/// A reduced master keeps one quality program only when its rendition set is complete.
struct HLSMasterSelection: Sendable {
    enum Rejection: String, Error {
        case notMaster = "not a master playlist"
        case unsupportedTag = "unsupported master tag"
        case malformedVariant = "malformed variant"
        case invalidPrograms = "invalid quality programs"
        case uniqueRenditions = "rendition groups differ"
        case invalidGroups = "incomplete rendition references"
        case invalidChild = "invalid child address"
    }
    let content: String
    let programCount: Int
    let renditionCount: Int

    static func fetch(_ source: PlaybackSource) async throws -> HLSMasterSelection? {
        guard source.hlsStartupMode == .selectedProgram, source.url.scheme == "https" || source.url.host == "127.0.0.1" else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source.url)
        request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(source.referrer?.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(source.origin?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, let base = response.url,
              source.url.scheme != "https" || base.scheme == "https" else { return nil }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 262144 else { return nil }
            data.append(byte)
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return try parse(text, base: base)
    }

    static func reduce(_ text: String, base: URL) -> HLSMasterSelection? {
        try? parse(text, base: base)
    }

    private static func parse(_ text: String, base: URL) throws -> HLSMasterSelection {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first == "#EXTM3U" else { throw Rejection.notMaster }
        var globals: [String] = []
        var media: [(line: String, attributes: [String: String])] = []
        var variants: [(line: String, attributes: [String: String], url: URL)] = []
        var pending: (String, [String: String])?
        for line in lines.dropFirst() {
            if line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") {
                // Trick-play thumbnails are independent of the normal video/audio program.
                guard pending == nil, let values = attributes(line), let uri = values["URI"],
                      address(uri, base: base) != nil else { throw Rejection.invalidChild }
                continue
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                guard pending == nil, let attributes = attributes(line),
                      ["AUDIO", "SUBTITLES", "CLOSED-CAPTIONS"].contains(attributes["TYPE"] ?? "") else { throw Rejection.malformedVariant }
                media.append((line, attributes))
            } else if line.hasPrefix("#EXT-X-STREAM-INF:") {
                guard pending == nil, let attributes = attributes(line), attributes["VIDEO"] == nil else { throw Rejection.malformedVariant }
                pending = (line, attributes)
            } else if !line.hasPrefix("#") {
                guard let current = pending, let url = address(line, base: base) else { throw Rejection.malformedVariant }
                variants.append((current.0, current.1, url))
                pending = nil
            } else if line.hasPrefix("#EXT-X-VERSION:") || line == "#EXT-X-INDEPENDENT-SEGMENTS" {
                guard pending == nil else { throw Rejection.malformedVariant }
                globals.append(line)
            } else if line.hasPrefix("#EXT") {
                throw Rejection.unsupportedTag
            }
        }
        guard pending == nil, (2...20).contains(variants.count),
              variants.allSatisfy({ (Int($0.attributes["BANDWIDTH"] ?? "") ?? 0) > 0 }) else { throw Rejection.invalidPrograms }
        let selected = variants.max { (Int($0.attributes["BANDWIDTH"] ?? "") ?? 0) < (Int($1.attributes["BANDWIDTH"] ?? "") ?? 0) }!
        var retained: [String] = []
        for type in ["AUDIO", "SUBTITLES", "CLOSED-CAPTIONS"] {
            let rows = media.filter { $0.attributes["TYPE"] == type }
            let references = variants.map { $0.attributes[type] ?? "NONE" }
            if references.allSatisfy({ $0 == "NONE" }) {
                guard rows.isEmpty else { throw Rejection.invalidGroups }
                continue
            }
            guard !references.contains("NONE"), let group = selected.attributes[type] else { throw Rejection.invalidGroups }
            let groups = Dictionary(grouping: rows, by: { $0.attributes["GROUP-ID"] ?? "" })
            guard Set(groups.keys) == Set(references), let chosen = groups[group], !chosen.isEmpty else { throw Rejection.invalidGroups }
            let descriptors = chosen.map { descriptor($0.attributes) }.sorted()
            guard groups.values.allSatisfy({ $0.map { descriptor($0.attributes) }.sorted() == descriptors }) else { throw Rejection.uniqueRenditions }
            for row in chosen {
                if let uri = row.attributes["URI"] {
                    guard row.line.contains("URI=\"" + uri + "\""), let url = address(uri, base: base) else { throw Rejection.invalidChild }
                    retained.append(row.line.replacingOccurrences(of: "URI=\"" + uri + "\"", with: "URI=\"" + url.absoluteString + "\""))
                } else {
                    guard type == "CLOSED-CAPTIONS" else { throw Rejection.malformedVariant }
                    retained.append(row.line)
                }
            }
        }
        return HLSMasterSelection(content: (["#EXTM3U"] + globals + retained + [selected.line, selected.url.absoluteString, ""]).joined(separator: "\n"),
                                  programCount: variants.count, renditionCount: retained.count)
    }

    private static func descriptor(_ values: [String: String]) -> String {
        values.filter { !["GROUP-ID", "URI", "DEFAULT", "AUTOSELECT"].contains($0.key) }
            .map { key, value in
                let value = key == "NAME" ? value.replacingOccurrences(of: "^\\d+\\.\\s+", with: "", options: .regularExpression) : value
                return key + "=" + value
            }.sorted().joined(separator: "\n")
    }

    private static func address(_ value: String, base: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil,
              base.scheme != "https" || url.scheme == "https" else { return nil }
        return url
    }

    private static func attributes(_ line: String) -> [String: String]? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let value = String(line[line.index(after: colon)...])
        let regex = try! NSRegularExpression(pattern: #"([A-Z0-9-]+)=("[^"]*"|[^,]+)(?:,|$)"#)
        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)
        var result: [String: String] = [:]
        var offset = 0
        for match in matches {
            guard match.range.location == offset, let keyRange = Range(match.range(at: 1), in: value),
                  let valueRange = Range(match.range(at: 2), in: value) else { return nil }
            let key = String(value[keyRange])
            guard result[key] == nil else { return nil }
            var item = String(value[valueRange])
            if item.first == "\"", item.last == "\"" { item = String(item.dropFirst().dropLast()) }
            result[key] = item
            offset = NSMaxRange(match.range)
        }
        return offset == range.length && !result.isEmpty ? result : nil
    }
}
