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

@Test func cancellingMediaLoadDoesNotWaitForTheLongHLSDeadline() async throws {
    let directory = try OwnedTemporaryDirectory()
    defer { directory.remove() }
    let executable = directory.url.appendingPathComponent("waiting-ipc-player")
    let marker = directory.url.appendingPathComponent("load-started")
    let script = """
    #!/usr/bin/python3
    import json,os,socket,sys,threading
    path=next(x.split('=',1)[1] for x in sys.argv if x.startswith('--input-ipc-server='))
    server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    server.bind(path);server.listen(1)
    client,_=server.accept()
    for line in client.makefile('rb'):
        request=json.loads(line)
        client.sendall((json.dumps({'request_id':request['request_id'],'error':'success','data':'test'})+'\\n').encode())
        if request['command'][0]=='loadfile':
            open(os.path.join(os.path.dirname(__file__),'load-started'),'w').close()
            threading.Timer(5,lambda:os._exit(0)).start()
    """
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let engine = MPVPlaybackEngine(executable: executable, headless: true)
    try await engine.start()
    let load = Task { try await engine.load(directory.url.appendingPathComponent("synthetic.mkv")) }
    do {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: marker.path))
        let cancelledAt = ContinuousClock.now
        load.cancel()
        await #expect(throws: CancellationError.self) { try await load.value }
        await engine.stop()
        #expect(cancelledAt.duration(to: .now) < .seconds(2))
    } catch {
        load.cancel()
        await engine.stop()
        _ = try? await load.value
        throw error
    }
}

@Test func streamErrorSurvivesOrdinaryRepliesAndANewLoadClearsIt() async throws {
    let directory = try OwnedTemporaryDirectory()
    defer { directory.remove() }
    let executable = directory.url.appendingPathComponent("media-outcome-player")
    let marker = directory.url.appendingPathComponent("outcome")
    let script = """
    #!/usr/bin/python3
    import json,os,socket,sys
    path=next(x.split('=',1)[1] for x in sys.argv if x.startswith('--input-ipc-server='))
    marker=os.path.join(os.path.dirname(__file__),'outcome')
    server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    server.bind(path);server.listen(1)
    client,_=server.accept()
    outcome=None
    def send(value):
        client.sendall((json.dumps(value)+'\\n').encode())
    for line in client.makefile('rb'):
        request=json.loads(line)
        command=request['command']
        if command[0]=='loadfile':
            outcome=None
            send({'event':'start-file'})
            send({'request_id':request['request_id'],'error':'success'})
            send({'event':'file-loaded'})
            continue
        if outcome is None and os.path.exists(marker):
            with open(marker) as f: outcome=f.read()
            send({'event':'end-file','reason':'eof' if outcome=='early-eof' else outcome})
        values={'mpv-version':'test','pause':False,'idle-active':outcome=='error',
                'time-pos':0 if outcome=='error' else (1199.5 if outcome=='eof' else 42),'duration':1200,
                'video-codec':None if outcome=='error' else 'h264','audio-codec':'aac',
                'speed':1,'seeking':False,'eof-reached':outcome in ('error','eof','early-eof')}
        send({'request_id':request['request_id'],'error':'success','data':values.get(command[1])})
    """
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let engine = MPVPlaybackEngine(executable: executable, headless: true)
    do {
        try await engine.start()
        try await engine.load(directory.url.appendingPathComponent("synthetic.mkv"))
        #expect(try await engine.snapshot().position.seconds == 42)
        try "error".write(to: marker, atomically: true, encoding: .utf8)
        let failed = try await engine.snapshot()
        #expect(failed.hasFailed)
        #expect(!failed.hasEnded)
        #expect(try await engine.snapshot().hasFailed)
        try FileManager.default.removeItem(at: marker)
        try await engine.load(directory.url.appendingPathComponent("refreshed.mkv"))
        #expect(try await !engine.snapshot().hasFailed)
        try "eof".write(to: marker, atomically: true, encoding: .utf8)
        let ended = try await engine.snapshot()
        #expect(ended.hasEnded)
        #expect(!ended.hasFailed)
        try FileManager.default.removeItem(at: marker)
        try await engine.load(directory.url.appendingPathComponent("truncated.mkv"))
        try "early-eof".write(to: marker, atomically: true, encoding: .utf8)
        let truncated = try await engine.snapshot()
        #expect(truncated.hasFailed)
        #expect(!truncated.hasEnded)
        await engine.stop()
    } catch {
        await engine.stop()
        throw error
    }
}

@Test func networkDiagnosticsNeverExposeAddressesTokensOrHeaders() throws {
    var diagnostics = MPVNetworkDiagnostics()
    let texts = [
        "Opening 'https://user:password@cdn.example.com/path/secret-token/video.m3u8?signature=secret' for reading",
        "Cookie: session=private-cookie", "Authorization: Bearer private-token",
        "TLS handshake failed for https://cdn.example.com/secret-token",
        "HTTP error 403 for https://cdn.example.com/secret-token", "Connection timed out",
        "Failed to open segment https://cdn.example.com/secret-token/1.ts"
    ]
    for text in texts {
        let data = try JSONSerialization.data(withJSONObject: ["event": "log-message", "text": text])
        diagnostics.receive(try JSONDecoder().decode(MPVMessage.self, from: data))
    }
    #expect(diagnostics.lines == ["Opening playlist · cdn.example.com", "TLS negotiation or read failed",
                                  "HTTP request rejected", "Network timeout", "Segment open failed"])
    let report = diagnostics.lines.joined(separator: "\n")
    for secret in ["secret", "private", "password", "user:", "Cookie", "Authorization", "https://"] {
        #expect(!report.contains(secret))
    }
}
