import Foundation

public actor MPVPlaybackEngine: PlaybackEngine {
    private struct Session: Sendable {
        let id = UUID()
        let directory: OwnedTemporaryDirectory
        let process: ManagedProcess
        let connection: MPVConnection
        let registration: SVPSocketRegistration?
    }

    private let executable: URL
    private let headless: Bool
    private let enableSVP: Bool
    private var session: Session?
    private var ready = false
    private var stopTask: Task<Void, Never>?

    public init(executable: URL, headless: Bool = false, enableSVP: Bool = false) {
        self.executable = executable
        self.headless = headless
        self.enableSVP = enableSVP && !headless
    }

    public func start() async throws {
        guard session == nil else { throw PlaybackError.alreadyRunning }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw PlaybackError.playerNotFound
        }
        let directory = try OwnedTemporaryDirectory()
        let registration: SVPSocketRegistration?
        do {
            registration = enableSVP ? try SVPSocketRegistration() : nil
        } catch {
            directory.remove()
            throw error
        }
        let socket = directory.url.appendingPathComponent("mpv.sock")
        var arguments = [
            "--no-config", "--idle=yes", "--force-window=no", "--terminal=no",
            "--input-terminal=no", "--keep-open=yes", "--no-resume-playback", "--hwdec=auto-copy",
            "--hwdec-codecs=all", "--hr-seek-framedrop=no", "--network-timeout=15",
            "--demuxer-lavf-o=http_persistent=0,http_multiple=0",
            "--input-ipc-server=\(socket.path)"
        ]
        if headless { arguments += ["--vo=null", "--ao=null"] }
        let process: ManagedProcess
        do {
            process = try ManagedProcess(executable: executable, arguments: arguments,
                                         environment: enableSVP ? VapourSynthRuntime.environment() : [:])
        } catch {
            directory.remove()
            throw error
        }
        let owned = Session(directory: directory, process: process, connection: MPVConnection(), registration: registration)
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

    public func load(_ source: PlaybackSource) async throws {
        let owned = try runningSession()
        // Long HLS startup can make SVP classify an idle player as audio-only.
        // Advertise only after file-loaded confirms that the media is ready.
        owned.registration?.remove()
        let location = source.url.isFileURL ? source.url.path : source.url.absoluteString
        _ = try await owned.connection.request([
            .string("loadfile"), .string(location), .string("replace"), .number(-1), .object(source.mpvOptions)
        ], awaitFileLoaded: true)
        try ensureCurrent(owned.id)
        if let registration = owned.registration, try await optionalString("video-codec") != nil {
            let processID = await owned.process.identifier
            try ensureCurrent(owned.id)
            try Task.checkCancellation()
            try registration.publish(socket: owned.directory.url.appendingPathComponent("mpv.sock"), processID: processID)
        }
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
        let videoCodec = try await optionalString("video-codec")
        let audioCodec = try await optionalString("audio-codec")
        let eof: MPVValue
        do { eof = try await command([.string("get_property"), .string("eof-reached")]) }
        catch PlaybackError.propertyUnavailable { eof = .bool(false) }
        try ensureCurrent(current.id)
        guard case .bool(let isPaused) = pause, case .bool(let isIdle) = idle else {
            throw PlaybackError.invalidResponse
        }
        return PlaybackSnapshot(
            isPaused: isPaused, isIdle: isIdle,
            position: PlaybackPosition(seconds: seconds ?? 0, duration: duration),
            videoCodec: videoCodec, audioCodec: audioCodec, hasEnded: eof == .bool(true)
        )
    }

    public func interpolationStatus() async throws -> SVPInterpolationStatus {
        _ = try runningSession()
        guard enableSVP else { return .disabled }
        let filters = try await command([.string("get_property"), .string("vf")])
        let sourceFPS = try await optionalNumber("container-fps")
        let outputFPS = try await optionalNumber("estimated-vf-fps")
        return SVPInterpolationStatus.inspect(filters: filters, sourceFPS: sourceFPS, outputFPS: outputFPS)
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
            owned.registration?.remove()
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

    private func optionalString(_ property: String) async throws -> String? {
        do {
            switch try await command([.string("get_property"), .string(property)]) {
            case .string(let value): return value
            case .null: return nil
            default: throw PlaybackError.invalidResponse
            }
        } catch PlaybackError.propertyUnavailable { return nil }
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
