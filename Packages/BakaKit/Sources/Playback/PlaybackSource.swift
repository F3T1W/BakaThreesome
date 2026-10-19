import Foundation

public struct PlaybackSource: Sendable {
    public let usesFastHLSStartup: Bool
    public let startSeconds: Double?
    public let url: URL
    public let audioURL: URL?
    public let referrer: URL?
    public let origin: URL?
    public let userAgent: String?

    public init(url: URL, referrer: URL? = nil, userAgent: String? = nil, audioURL: URL? = nil, origin: URL? = nil, startSeconds: Double? = nil, fastHLSStartup: Bool = true) throws {
        guard url.isFileURL || (["http", "https"].contains(url.scheme?.lowercased() ?? "")
                               && url.host != nil && url.user == nil && url.password == nil),
              referrer.map({ $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil }) ?? true,
              userAgent.map({ !$0.isEmpty && $0.utf8.count < 1024 && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }) ?? true
        else { throw PlaybackError.invalidMediaURL }
        if let audioURL {
            guard audioURL.isFileURL || (["http", "https"].contains(audioURL.scheme?.lowercased() ?? "")
                                        && audioURL.host != nil && audioURL.user == nil && audioURL.password == nil)
            else { throw PlaybackError.invalidMediaURL }
        }
        if let origin {
            guard origin.scheme == "https", origin.host != nil, origin.user == nil, origin.password == nil,
                  origin.query == nil, origin.fragment == nil, ["", "/"].contains(origin.path)
            else { throw PlaybackError.invalidMediaURL }
        }
        if let startSeconds, !startSeconds.isFinite || startSeconds < 0 { throw PlaybackError.invalidSeek }
        usesFastHLSStartup = fastHLSStartup && !url.isFileURL && url.pathExtension.lowercased() == "m3u8"
        self.startSeconds = startSeconds
        self.url = url
        self.audioURL = audioURL
        self.referrer = referrer
        self.origin = origin
        self.userAgent = userAgent
    }

    public func conservativeStartup() throws -> PlaybackSource {
        try PlaybackSource(url: url, referrer: referrer, userAgent: userAgent, audioURL: audioURL,
                           origin: origin, startSeconds: startSeconds, fastHLSStartup: false)
    }

    var mpvOptions: [String: MPVValue] {
        var options: [String: MPVValue] = ["ytdl": .string("no"), "force-media-title": .string("BakaThreesome")]
        if usesFastHLSStartup {
            options["demuxer-lavf-probe-info"] = .string("nostreams")
            options["demuxer-lavf-o"] = .string("http_persistent=1,http_multiple=1")
        } else {
            options["demuxer-lavf-probe-info"] = .string("auto")
            options["demuxer-lavf-o"] = .string("http_persistent=0,http_multiple=0")
        }
        if let startSeconds { options["start"] = .string(String(startSeconds)) }
        if let referrer { options["referrer"] = .string(referrer.absoluteString) }
        if let origin {
            let value = origin.absoluteString.hasSuffix("/") ? String(origin.absoluteString.dropLast()) : origin.absoluteString
            options["http-header-fields-append"] = .string("Origin: " + value)
        }
        if let userAgent { options["user-agent"] = .string(userAgent) }
        if let audioURL {
            let value = audioURL.isFileURL ? audioURL.path : audioURL.absoluteString
            options["audio-files-append"] = .string(value)
        }
        return options
    }
}
