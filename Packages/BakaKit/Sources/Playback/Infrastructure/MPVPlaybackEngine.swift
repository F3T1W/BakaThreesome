import Foundation

public actor MPVPlaybackEngine: PlaybackEngine {
    private struct Session: Sendable {
        let id = UUID()
        let directory: OwnedTemporaryDirectory
        let process: ManagedProcess
        let connection: MPVConnection
    }

    private let executable: URL
    private let headless: Bool
    private var session: Session?
    private var ready = false
    private var stopTask: Task<Void, Never>?

    public init(executable: URL, headless: Bool = false) {
        self.executable = executable
        self.headless = headless
    }

    public func start() async throws {
        guard session == nil else { throw PlaybackError.alreadyRunning }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw PlaybackError.playerNotFound
        }
        let directory = try OwnedTemporaryDirectory()
        let socket = directory.url.appendingPathComponent("mpv.sock")
        var arguments = [
            "--no-config", "--idle=yes", "--force-window=no", "--terminal=no",
            "--input-terminal=no", "--no-resume-playback", "--hwdec=auto-copy",
            "--hr-seek-framedrop=no", "--network-timeout=15",
            "--demuxer-lavf-o=http_persistent=0,http_multiple=0",
            "--input-ipc-server=\(socket.path)"
        ]
        if headless { arguments += ["--vo=null", "--ao=null"] }
        let process: ManagedProcess
        do {
            process = try ManagedProcess(executable: executable, arguments: arguments)
        } catch {
            directory.remove()
            throw error
        }
        let owned = Session(directory: directory, process: process, connection: MPVConnection())
        session = owned
        do {
            try Task.checkCancellation()
            try await process.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while true {
                try Task.checkCancellation()
                try ensureCurrent(owned.id)
                guard await process.isRunning else { throw PlaybackError.exitedBeforeReady }
                do {
                    try await owned.connection.connect(to: socket.path)
                    break
                } catch PlaybackError.connectionUnavailable {
                    guard ContinuousClock.now < deadline else { throw PlaybackError.timedOut }
                    try await Task.sleep(for: .milliseconds(40))
                }
            }
            guard case .string = try await owned.connection.request([.string("get_property"), .string("mpv-version")]) else {
                throw PlaybackError.invalidResponse
            }
            try ensureCurrent(owned.id)
            try Task.checkCancellation()
            ready = true
        } catch {
            if session?.id == owned.id { await stop() }
            throw error
        }
    }

    public func load(_ url: URL) async throws {
        guard url.isFileURL || ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw PlaybackError.invalidMediaURL
        }
        _ = try await command([
            .string("loadfile"), .string(url.isFileURL ? url.path : url.absoluteString), .string("replace")
        ])
    }

    public func setPaused(_ paused: Bool) async throws {
        _ = try await command([.string("set_property"), .string("pause"), .bool(paused)])
    }

    public func seek(to seconds: Double) async throws {
        guard seconds.isFinite, seconds >= 0 else { throw PlaybackError.invalidSeek }
        _ = try await command([.string("seek"), .number(seconds), .string("absolute+exact")])
    }

    public func snapshot() async throws -> PlaybackSnapshot {
        let current = try runningSession()
        let pause = try await command([.string("get_property"), .string("pause")])
        let idle = try await command([.string("get_property"), .string("idle-active")])
        let seconds = try await optionalNumber("time-pos")
        let duration = try await optionalNumber("duration")
        try ensureCurrent(current.id)
        guard case .bool(let isPaused) = pause, case .bool(let isIdle) = idle else {
            throw PlaybackError.invalidResponse
        }
        return PlaybackSnapshot(
            isPaused: isPaused, isIdle: isIdle,
            position: PlaybackPosition(seconds: seconds ?? 0, duration: duration)
        )
    }

    public func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard let owned = session else { return }
        ready = false
        let task = Task {
            await owned.connection.close()
            await owned.process.stop()
            owned.directory.remove()
        }
        stopTask = task
        await task.value
        session = nil
        stopTask = nil
    }

    private func command(_ arguments: [MPVValue]) async throws -> MPVValue {
        let current = try runningSession()
        let result = try await current.connection.request(arguments)
        try ensureCurrent(current.id)
        return result
    }

    private func optionalNumber(_ property: String) async throws -> Double? {
        do {
            let value = try await command([.string("get_property"), .string(property)])
            switch value {
            case .number(let number): return number
            case .null: return nil
            default: throw PlaybackError.invalidResponse
            }
        } catch PlaybackError.propertyUnavailable {
            return nil
        }
    }

    private func runningSession() throws -> Session {
        guard ready, let session, stopTask == nil else { throw PlaybackError.notRunning }
        return session
    }

    private func ensureCurrent(_ id: UUID) throws {
        guard session?.id == id, stopTask == nil else { throw PlaybackError.notRunning }
    }
}
