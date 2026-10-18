import Foundation

public struct PlayerCapabilities: Sendable {
    public let version: String
    public let hasVapourSynth: Bool
}

public struct PlaybackEnvironment: Sendable {
    public let mpvURL: URL?
    public let svpURL: URL?

    public static func discover() -> PlaybackEnvironment {
        let manager = FileManager.default
        let mpv = ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"]
            .first { manager.isExecutableFile(atPath: $0) }
        let svp = [
            "/Applications/SVP 4 Mac.app", "/Applications/SVP.app",
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/SVP 4 Mac.app").path
        ].first { manager.fileExists(atPath: $0) }
        return PlaybackEnvironment(
            mpvURL: mpv.map { URL(fileURLWithPath: $0) },
            svpURL: svp.map { URL(fileURLWithPath: $0) }
        )
    }
}

public struct MPVCapabilityProbe: Sendable {
    private let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public func inspect() async throws -> PlayerCapabilities {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw PlaybackError.playerNotFound
        }
        let versionOutput = try await output(for: ["--no-config", "--version"])
        let filters = try await output(for: ["--no-config", "--vf=help"])
        guard let firstLine = versionOutput.split(separator: "\n").first,
              firstLine.hasPrefix("mpv ") else { throw PlaybackError.probeFailed }
        let version = firstLine.split(separator: " ").prefix(2).joined(separator: " ")
        let hasVapourSynth = filters.split(separator: "\n").contains {
            $0.split(whereSeparator: \.isWhitespace).first == "vapoursynth"
        }
        return PlayerCapabilities(version: version, hasVapourSynth: hasVapourSynth)
    }

    private func output(for arguments: [String]) async throws -> String {
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let outputURL = directory.url.appendingPathComponent("probe.txt")
        let child = try ManagedProcess(executable: executable, arguments: arguments, outputURL: outputURL)
        do {
            try Task.checkCancellation()
            try await child.start()
            guard let status = await child.waitForExit(timeout: .seconds(5)) else {
                throw PlaybackError.timedOut
            }
            try Task.checkCancellation()
            guard status == 0 else { throw PlaybackError.probeFailed }
            await child.stop()
            let handle = try FileHandle(forReadingFrom: outputURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 262_144) ?? Data()
            return String(decoding: data, as: UTF8.self)
        } catch {
            await child.stop()
            throw error
        }
    }
}

public struct PlayerIPCCheck: Sendable {
    public init() {}

    /// Verifies process launch and IPC without loading media or touching SVP's socket.
    public func run(using engine: any PlaybackEngine) async throws {
        var started = false
        do {
            try await engine.start()
            started = true
            try Task.checkCancellation()
            let initial = try await engine.snapshot()
            guard initial.isIdle else { throw PlaybackError.invalidResponse }
            try await engine.setPaused(!initial.isPaused)
            let changed = try await engine.snapshot()
            guard changed.isPaused != initial.isPaused else { throw PlaybackError.invalidResponse }
            try await engine.setPaused(initial.isPaused)
            await engine.stop()
            try Task.checkCancellation()
        } catch {
            if started { await engine.stop() }
            throw error
        }
    }
}
