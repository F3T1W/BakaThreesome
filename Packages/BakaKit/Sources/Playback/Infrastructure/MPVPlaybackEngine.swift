import Foundation
import OSLog

public actor MPVPlaybackEngine: PlaybackEngine {
    struct Session: Sendable {
        let id = UUID()
        let directory: OwnedTemporaryDirectory
        let process: ManagedProcess
        let connection: MPVConnection
        let registration: SVPSocketRegistration?
    }

    private let executable: URL
    private let headless: Bool
    private let enableSVP: Bool
    private let networkDiagnosticsEnabled: Bool
    private var session: Session?
    private var ready = false
    private var startupNote: String?
    private var stopTask: Task<Void, Never>?

    public init(executable: URL, headless: Bool = false, enableSVP: Bool = false, networkDiagnostics: Bool = false) {
        self.executable = executable
        self.headless = headless
        self.enableSVP = enableSVP && !headless
        networkDiagnosticsEnabled = networkDiagnostics
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
            "--no-config", "--idle=yes", "--force-window=\(headless ? "no" : "immediate")", "--terminal=no",
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
            if networkDiagnosticsEnabled {
                _ = try await owned.connection.request([.string("request_log_messages"), .string("debug")])
            }
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
        let selection: HLSMasterSelection?
        var rejection: String?
        do { selection = try await HLSMasterSelection.fetch(source) }
        catch let error as HLSMasterSelection.Rejection {
            selection = nil; rejection = error.rawValue
        } catch {
            selection = nil; rejection = "master request failed"
        }
        try Task.checkCancellation()
        try ensureCurrent(owned.id)
        startupNote = selection.map { "HLS selected program: \($0.programCount) → 1; \($0.renditionCount) renditions retained" }
            ?? (source.hlsStartupMode == .selectedProgram ? "HLS selected program: original master retained (\(rejection ?? "not eligible"))" : nil)
        if let startupNote {
            Logger(subsystem: "dev.bakathreesome", category: "PlaybackStartup")
                .notice("\(startupNote, privacy: .public)")
        }
        let location = selection.map { "data://application/vnd.apple.mpegurl;base64," + Data($0.content.utf8).base64EncodedString() }
            ?? (source.url.isFileURL ? source.url.path : source.url.absoluteString)
        var options = source.mpvOptions
        var paused: Bool?
        if selection != nil {
            options["demuxer"] = .string("lavf")
            options["demuxer-lavf-format"] = .string("hls")
            if let start = source.startSeconds, start > 0 {
                guard case .bool(let value) = try await command([.string("get_property"), .string("pause")]) else {
                    throw PlaybackError.invalidResponse
                }
                paused = value
                options["pause"] = .string("yes")
                options.removeValue(forKey: "start")
            }
        }
        _ = try await owned.connection.request([
            .string("loadfile"), .string(location), .string("replace"), .number(-1), .object(options)
        ], awaitFileLoaded: true)
        if let paused, let start = source.startSeconds {
            try await restoreResumePosition(to: start, paused: paused)
        }
        try ensureCurrent(owned.id)
        if owned.registration != nil, try await optionalString("video-codec") != nil {
            try await advertiseVideo(owned)
        }
    }

    /// Restore transport state before confirmation: a visible decoder may need playback to finish a seek.
    func restoreResumePosition(to seconds: Double, paused: Bool) async throws {
        let owned = try runningSession()
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        let duration = try await resumeNumber("duration", until: deadline, sessionID: owned.id)
        if let duration, seconds >= duration - 1 {
            // The caller reports an out-of-range saved position.
            _ = try await resumeCommand([.string("set_property"), .string("pause"), .bool(paused)], until: deadline, sessionID: owned.id)
            return
        }
        _ = try await resumeCommand([.string("seek"), .number(seconds), .string("absolute+exact")], until: deadline, sessionID: owned.id)
        let sought = ContinuousClock.now
        _ = try await resumeCommand([.string("set_property"), .string("pause"), .bool(paused)], until: deadline, sessionID: owned.id)
        var position = -1.0
        var seeking = false
        while true {
            try Task.checkCancellation()
            try ensureCurrent(owned.id)
            do {
                position = try await resumeNumber("time-pos", until: deadline, sessionID: owned.id) ?? -1
                let elapsed = sought.duration(to: .now).components
                let drift = paused ? 0 : Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                // Seeking can remain true until the first rendered/filter frame. Do not block SVP registration on it.
                if position >= seconds - 0.25, position <= seconds + drift + 0.25 { return }
                seeking = try await resumeCommand([.string("get_property"), .string("seeking")], until: deadline, sessionID: owned.id) == .bool(true)
            } catch PlaybackError.timedOut { }
            guard ContinuousClock.now < deadline else {
                Logger(subsystem: "dev.bakathreesome", category: "PlaybackStartup")
                    .notice("HLS resume confirmation timed out: requested=\(seconds, privacy: .public), position=\(position, privacy: .public), seeking=\(seeking, privacy: .public)")
                throw PlaybackError.timedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func resumeNumber(_ property: String, until deadline: ContinuousClock.Instant, sessionID: UUID) async throws -> Double? {
        do {
            switch try await resumeCommand([.string("get_property"), .string(property)], until: deadline, sessionID: sessionID) {
            case .number(let value): return value
            case .null: return nil
            default: throw PlaybackError.invalidResponse
            }
        } catch PlaybackError.propertyUnavailable { return nil }
    }

    private func resumeCommand(_ arguments: [MPVValue], until deadline: ContinuousClock.Instant, sessionID: UUID) async throws -> MPVValue {
        while true {
            try Task.checkCancellation()
            try ensureCurrent(sessionID)
            do { return try await command(arguments) }
            catch PlaybackError.timedOut {
                guard ContinuousClock.now < deadline else { throw PlaybackError.timedOut }
            }
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
        let speed = try await optionalNumber("speed")
        let seeking: MPVValue
        do { seeking = try await command([.string("get_property"), .string("seeking")]) }
        catch PlaybackError.propertyUnavailable { seeking = .bool(true) }
        let eof: MPVValue
        do { eof = try await command([.string("get_property"), .string("eof-reached")]) }
        catch PlaybackError.propertyUnavailable { eof = .bool(false) }
        var hasFailed = try await current.connection.mediaHasFailed()
        // mpv can report EOF for a truncated network stream. Only infer an
        // interruption when a valid position is clearly short of a known total.
        if eof == .bool(true), let seconds, let duration, seconds.isFinite, duration.isFinite,
           seconds >= 0, duration > 0, duration - seconds > max(5, duration * 0.005) {
            hasFailed = true
        }
        try ensureCurrent(current.id)
        guard case .bool(let isPaused) = pause, case .bool(let isIdle) = idle else {
            throw PlaybackError.invalidResponse
        }
        if videoCodec != nil, !isIdle { try await advertiseVideo(current) }
        return PlaybackSnapshot(
            isPaused: isPaused, isIdle: isIdle,
            position: PlaybackPosition(seconds: seconds ?? 0, duration: duration),
            videoCodec: videoCodec, audioCodec: audioCodec,
            hasEnded: eof == .bool(true) && !hasFailed, hasFailed: hasFailed,
            speed: speed ?? 0, isSeeking: seeking != .bool(false)
        )
    }

    public func networkDiagnostics() async -> [String] {
        guard let session else { return [] }
        return [startupNote].compactMap { $0 } + (await session.connection.networkDiagnostics())
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

    private func advertiseVideo(_ current: Session) async throws {
        guard let registration = current.registration else { return }
        let processID = await current.process.identifier
        try ensureCurrent(current.id)
        try Task.checkCancellation()
        try registration.publish(socket: current.directory.url.appendingPathComponent("mpv.sock"), processID: processID)
    }

    func command(_ arguments: [MPVValue]) async throws -> MPVValue {
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

    func runningSession() throws -> Session {
        guard ready, let session, stopTask == nil else { throw PlaybackError.notRunning }
        return session
    }

    func ensureCurrent(_ id: UUID) throws {
        guard session?.id == id, stopTask == nil else { throw PlaybackError.notRunning }
    }
}
