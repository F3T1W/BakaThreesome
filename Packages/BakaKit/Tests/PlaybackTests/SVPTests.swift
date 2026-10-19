import Foundation
@testable import Playback
import Testing

@Test func interpolationRequiresAnEnabledSVPFilterAndHigherOutputRate() {
    let filter: MPVValue = .object([
        "name": .string("vapoursynth"), "label": .string("svp"), "enabled": .bool(true)
    ])
    #expect(SVPInterpolationStatus.inspect(filters: .array([]), sourceFPS: 24, outputFPS: 60) == .waiting)
    #expect(SVPInterpolationStatus.inspect(filters: .array([filter]), sourceFPS: 24, outputFPS: nil) == .connected)
    #expect(SVPInterpolationStatus.inspect(filters: .array([filter]), sourceFPS: 24, outputFPS: 24) == .connected)
    #expect(SVPInterpolationStatus.inspect(filters: .array([filter]), sourceFPS: 24, outputFPS: 60)
            == .interpolating(sourceFPS: 24, outputFPS: 60))
    let disabled: MPVValue = .object([
        "name": .string("vapoursynth"), "label": .string("svp"), "enabled": .bool(false)
    ])
    #expect(SVPInterpolationStatus.inspect(filters: .array([disabled]), sourceFPS: 24, outputFPS: 60) == .waiting)
}

@Test func socketRegistrationPreservesOtherPlayersAndRejectsUnsafeDirectories() throws {
    let root = try OwnedTemporaryDirectory()
    defer { root.remove() }
    let discovery = root.url.appendingPathComponent("mpvSockets")
    let first = try SVPSocketRegistration(directory: discovery)
    let second = try SVPSocketRegistration(directory: discovery)
    let socket = root.url.appendingPathComponent("mpv.sock")
    try first.publish(socket: socket, processID: 123)
    try first.publish(socket: socket, processID: 123)
    #expect(throws: PlaybackError.svpRegistrationFailed) { try first.publish(socket: socket, processID: 789) }
    #expect(throws: PlaybackError.svpRegistrationFailed) { try second.publish(socket: socket, processID: 123) }
    try second.publish(socket: socket, processID: 456)
    first.remove()
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: discovery.appendingPathComponent("456").path) == socket.path)
    second.remove()
    #expect(try FileManager.default.contentsOfDirectory(atPath: discovery.path).isEmpty)
    try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: discovery.path)
    #expect(throws: PlaybackError.svpRegistrationFailed) { try SVPSocketRegistration(directory: discovery) }
    let alias = root.url.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.url)
    #expect(throws: PlaybackError.svpRegistrationFailed) { try SVPSocketRegistration(directory: alias) }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_SVP_INTEGRATION"] == "1"))
struct SVPIntegrationTests {
    /// Requires an already running SVP Manager and a local video longer than its minimum duration.
    @Test func installedSVPActuallyIncreasesFrameRateThroughTheEngine() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["BAKA_SVP_TEST_MEDIA"])
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let engine = MPVPlaybackEngine(executable: executable, enableSVP: true)
        do {
            try await engine.start()
            // Exceed SVP's idle-video detection window before media becomes available.
            try await Task.sleep(for: .seconds(30))
            try await engine.load(URL(fileURLWithPath: path))
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            var confirmed = false
            while ContinuousClock.now < deadline {
                if case .interpolating(let source, let output) = try await engine.interpolationStatus() {
                    #expect(output > source + 0.5)
                    let before = try await engine.snapshot().position.seconds
                    try await Task.sleep(for: .seconds(1))
                    #expect(try await engine.snapshot().position.seconds > before)
                    confirmed = true
                    break
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            #expect(confirmed, "SVP did not enable interpolation before the deadline")
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }
}
