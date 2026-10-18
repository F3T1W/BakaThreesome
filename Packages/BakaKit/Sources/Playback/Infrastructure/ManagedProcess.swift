import Darwin
import Foundation

actor ManagedProcess {
    private let process = Process()
    private var output: FileHandle?
    private var exitStatus: Int32?
    private var waiters: [UUID: CheckedContinuation<Int32?, Never>] = [:]

    init(executable: URL, arguments: [String], outputURL: URL? = nil) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let outputURL {
            guard FileManager.default.createFile(
                atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]
            ) else {
                throw PlaybackError.launchFailed
            }
            let handle = try FileHandle(forWritingTo: outputURL)
            output = handle
            process.standardOutput = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
    }

    func start() throws {
        process.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { await self?.recordExit(status) }
        }
        do {
            try process.run()
        } catch {
            try? output?.close()
            throw PlaybackError.launchFailed
        }
    }

    var isRunning: Bool { process.isRunning }

    func waitForExit(timeout: Duration) async -> Int32? {
        if let exitStatus { return exitStatus }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task {
                try? await Task.sleep(for: timeout)
                expireWaiter(id)
            }
        }
    }

    func stop() async {
        if process.isRunning {
            process.terminate()
            if await waitForExit(timeout: .seconds(1)) == nil, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = await waitForExit(timeout: .seconds(1))
            }
        }
        try? output?.close()
        output = nil
    }

    private func recordExit(_ status: Int32) {
        exitStatus = status
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending {
            continuation.resume(returning: status)
        }
    }

    private func expireWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(returning: nil)
    }
}
