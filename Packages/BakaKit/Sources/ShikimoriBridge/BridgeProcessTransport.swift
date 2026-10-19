import Darwin
import Foundation
import Synchronization

public protocol BridgeTransport: Sendable {
    func exchange(_ data: Data, cancelSafe: Bool) async throws -> Data
    func shutdown() async
}

public enum ShikimoriError: Error, LocalizedError, Equatable {
    case helperUnavailable, disconnected, timeout, invalidResponse, invalidValues
    case unauthorized, forbidden, rateLimited, serviceUnavailable, storageFailed, notSignedIn

    public var errorDescription: String? {
        switch self {
        case .helperUnavailable: "The Shikimori helper is unavailable. Build the app and check that .NET 10 is installed."
        case .disconnected: "The Shikimori helper stopped. Reload the list before retrying a change."
        case .timeout: "Shikimori did not respond in time. Reload the list before retrying a change."
        case .invalidResponse: "Shikimori returned an unexpected response."
        case .invalidValues: "Check the supplied values and try again."
        case .unauthorized: "Your Shikimori session has expired. Sign out and sign in again."
        case .forbidden: "Shikimori did not allow this action. Check the user_rates permission."
        case .rateLimited: "The Shikimori request limit was reached. Wait before trying again."
        case .serviceUnavailable: "Shikimori could not be reached. Check your connection and try again."
        case .storageFailed: "The Shikimori session could not be read or saved in Keychain. Unlock your keychain and try again."
        case .notSignedIn: "Sign in to Shikimori in Settings to use your watchlist."
        }
    }
}

/// Process and pipe state is confined to the serial queue. Bounded I/O does not
/// occupy MainActor or Swift's cooperative executor.
public final class BridgeProcessTransport: BridgeTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.bakathreesome.shikimori.bridge")
    private let configuration: (@Sendable () throws -> (URL, [String]))
    private var process: Process?
    private var termination: DispatchSemaphore?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffered = Data()

    public init() {
        configuration = {
            let candidates = ["/usr/local/share/dotnet/dotnet", "/opt/homebrew/bin/dotnet", "/usr/local/bin/dotnet"]
            guard let host = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
                  let dll = Bundle.main.resourceURL?.appendingPathComponent("Bridge/BakaThreesome.ShikimoriBridge.dll"),
                  FileManager.default.fileExists(atPath: dll.path) else { throw ShikimoriError.helperUnavailable }
            return (URL(fileURLWithPath: host), [dll.path])
        }
    }

    public init(executable: URL, arguments: [String]) {
        configuration = { (executable, arguments) }
    }

    public func exchange(_ data: Data, cancelSafe: Bool) async throws -> Data {
        let cancellation = BridgeCancellation(cancelSafe: cancelSafe)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.begin()
                        try self.startIfNeeded()
                        let response = try self.transact(data, cancellation: cancellation)
                        continuation.resume(returning: response)
                    } catch {
                        self.reset()
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    public func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.reset()
                continuation.resume()
            }
        }
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        reset()
        let (executable, arguments) = try configuration()
        let child = Process()
        let exited = DispatchSemaphore(value: 0)
        child.terminationHandler = { _ in exited.signal() }
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
        environment["DOTNET_NOLOGO"] = "1"
        child.environment = environment
        do { try child.run() }
        catch { throw ShikimoriError.helperUnavailable }
        try? stdin.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        process = child
        termination = exited
        guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw ShikimoriError.disconnected
        }
        for handle in [input, output].compactMap({ $0 }) {
            guard fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) == 0 else {
                throw ShikimoriError.disconnected
            }
        }
    }

    private func transact(_ data: Data, cancellation: BridgeCancellation) throws -> Data {
        guard data.count <= 1_048_576, let input, let output else { throw ShikimoriError.invalidValues }
        let deadline = DispatchTime.now().uptimeNanoseconds + 25_000_000_000
        var payload = data
        payload.append(0x0A)
        try payload.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                try wait(input.fileDescriptor, for: Int16(POLLOUT), deadline: deadline, cancellation: cancellation)
                let count = Darwin.write(input.fileDescriptor, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
                if count > 0 { sent += count }
                else if count == -1 && (errno == EAGAIN || errno == EINTR) { continue }
                else { throw ShikimoriError.disconnected }
            }
        }
        while true {
            if let newline = buffered.firstIndex(of: 0x0A) {
                let line = Data(buffered.prefix(upTo: newline))
                buffered.removeSubrange(buffered.startIndex...newline)
                return line
            }
            try wait(output.fileDescriptor, for: Int16(POLLIN), deadline: deadline, cancellation: cancellation)
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count > 0 {
                guard buffered.count + count <= 4_194_304 else { throw ShikimoriError.invalidResponse }
                buffered.append(contentsOf: bytes.prefix(count))
            } else if count == 0 { throw ShikimoriError.disconnected }
            else if errno != EINTR && errno != EAGAIN { throw ShikimoriError.disconnected }
        }
    }

    private func wait(_ fd: Int32, for events: Int16, deadline: UInt64, cancellation: BridgeCancellation) throws {
        while true {
            try cancellation.check()
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw ShikimoriError.timeout }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let timeout = Int32(max(1, min(100, (deadline - now) / 1_000_000)))
            let result = Darwin.poll(&descriptor, 1, timeout)
            if result == 0 || (result == -1 && errno == EINTR) { continue }
            guard result > 0, descriptor.revents & events != 0 else { throw ShikimoriError.disconnected }
            return
        }
    }

    private func reset() {
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        buffered.removeAll()
        if let process, process.isRunning {
            process.terminate()
            if termination?.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = termination?.wait(timeout: .now() + 1)
            }
        }
        process = nil
        termination = nil
    }
}

private final class BridgeCancellation: Sendable {
    private struct State { var started = false; var cancelled = false }
    private let state = Mutex(State())
    private let cancelSafe: Bool
    init(cancelSafe: Bool) { self.cancelSafe = cancelSafe }
    func begin() throws {
        try state.withLock {
            if $0.cancelled { throw CancellationError() }
            $0.started = true
        }
    }
    func cancel() {
        state.withLock { if !$0.started || cancelSafe { $0.cancelled = true } }
    }
    func check() throws {
        if state.withLock({ $0.cancelled }) { throw CancellationError() }
    }
}
