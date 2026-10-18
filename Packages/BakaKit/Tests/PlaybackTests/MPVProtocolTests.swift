import Darwin
import Foundation
@testable import Playback
import Testing

@Test func framesPartialMessagesAndUnsolicitedEvents() throws {
    var buffer = MPVLineBuffer()
    try buffer.append(Data(#"{"event":"idle"}"#.utf8))
    let incomplete = try buffer.nextMessage()
    #expect(incomplete == nil)
    try buffer.append(Data("\n{\"request_id\":7,\"error\":\"success\",\"data\":false}\n".utf8))
    let event = try buffer.nextMessage()
    #expect(event?.request_id == nil)
    let next = try buffer.nextMessage()
    let response = try #require(next)
    #expect(response.request_id == 7)
    #expect(response.data == .bool(false))
    let trailing = try buffer.nextMessage()
    #expect(trailing == nil)
}

@Test func rejectsMalformedAndOversizedMessages() throws {
    var malformed = MPVLineBuffer()
    try malformed.append(Data("not-json\n".utf8))
    #expect(throws: PlaybackError.invalidResponse) { try malformed.nextMessage() }
    var oversized = MPVLineBuffer()
    #expect(throws: PlaybackError.invalidResponse) {
        try oversized.append(Data(repeating: 0x20, count: 1_048_577))
    }
}

@Test func unavailableExecutableProducesActionableFailure() async {
    let executable = URL(fileURLWithPath: "/nonexistent/bakathreesome-mpv")
    await #expect(throws: PlaybackError.playerNotFound) {
        try await MPVCapabilityProbe(executable: executable).inspect()
    }
}

@Test func rejectsCommandsWithoutAnActiveSession() async {
    let engine = MPVPlaybackEngine(executable: URL(fileURLWithPath: "/usr/bin/true"))
    await #expect(throws: PlaybackError.notRunning) { try await engine.setPaused(true) }
    await #expect(throws: PlaybackError.invalidSeek) { try await engine.seek(to: .nan) }
    await #expect(throws: PlaybackError.invalidSeek) { try await engine.seek(to: -1) }
    await #expect(throws: PlaybackError.invalidMediaURL) {
        try await engine.load(URL(string: "blob:https://example.com/media")!)
    }
    await engine.stop()
}

@Test func earlyExitDoesNotLeaveAnActiveSession() async throws {
    let engine = MPVPlaybackEngine(executable: URL(fileURLWithPath: "/usr/bin/true"), headless: true)
    await #expect(throws: PlaybackError.exitedBeforeReady) { try await engine.start() }
    await #expect(throws: PlaybackError.notRunning) { try await engine.snapshot() }
    await engine.stop()
}

@Test func cancellingStartupTerminatesTheOwnedProcess() async throws {
    let directory = try OwnedTemporaryDirectory()
    defer { directory.remove() }
    let marker = directory.url.appendingPathComponent("pid")
    let executable = directory.url.appendingPathComponent("waiting-player")
    let script = "#!/bin/sh\necho $$ > '\(marker.path)'\nexec /bin/sleep 30\n"
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let engine = MPVPlaybackEngine(executable: executable, headless: true)
    let startup = Task { try await engine.start() }
    do {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pidText = try String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(Int32(pidText))
        startup.cancel()
        await #expect(throws: CancellationError.self) { try await startup.value }
        #expect(Darwin.kill(pid, 0) == -1)
        #expect(errno == ESRCH)
        await #expect(throws: PlaybackError.notRunning) { try await engine.snapshot() }
    } catch {
        startup.cancel()
        await engine.stop()
        _ = try? await startup.value
        throw error
    }
}
