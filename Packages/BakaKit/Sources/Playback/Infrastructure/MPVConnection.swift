import Darwin
import Foundation

/// The serial queue exclusively owns the socket and framing state. Blocking I/O
/// runs on that queue, never on MainActor or Swift's cooperative executor.
final class MPVConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.bakathreesome.mpv.ipc")
    private var descriptor: Int32 = -1
    private var buffer = MPVLineBuffer()
    private var nextRequestID = 0

    func connect(to path: String) async throws {
        try await perform {
            guard self.descriptor == -1 else { throw PlaybackError.alreadyRunning }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let pathBytes = Array(path.utf8CString)
            guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                throw PlaybackError.connectionUnavailable
            }
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                pathBytes.withUnsafeBytes { destination.copyBytes(from: $0) }
            }
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw PlaybackError.connectionUnavailable }
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else {
                Darwin.close(descriptor)
                throw PlaybackError.connectionUnavailable
            }
            var noSignal: Int32 = 1
            let signalResult = setsockopt(
                descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)
            )
            guard signalResult == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
                Darwin.close(descriptor)
                throw PlaybackError.connectionUnavailable
            }
            self.descriptor = descriptor
        }
    }

    func request(_ command: [MPVValue]) async throws -> MPVValue {
        try Task.checkCancellation()
        let value = try await perform {
            guard self.descriptor >= 0 else { throw PlaybackError.disconnected }
            self.nextRequestID += 1
            let id = self.nextRequestID
            var data = try JSONEncoder().encode(MPVRequest(command: command, request_id: id))
            data.append(0x0A)
            let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
            try self.send(data, deadline: deadline)
            while true {
                while let message = try self.buffer.nextMessage() {
                    // mpv emits unsolicited events on the same connection.
                    guard message.request_id == id else { continue }
                    switch message.error {
                    case "success": return message.data ?? .null
                    case "property unavailable": throw PlaybackError.propertyUnavailable
                    case nil: throw PlaybackError.invalidResponse
                    default: throw PlaybackError.commandRejected
                    }
                }
                try self.wait(for: Int16(POLLIN), deadline: deadline)
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.recv(self.descriptor, &bytes, bytes.count, 0)
                if count > 0 {
                    try self.buffer.append(Data(bytes.prefix(count)))
                } else if count == 0 {
                    throw PlaybackError.disconnected
                } else if errno != EAGAIN && errno != EINTR {
                    throw PlaybackError.disconnected
                }
            }
        }
        try Task.checkCancellation()
        return value
    }

    func close() async {
        _ = try? await perform {
            if self.descriptor >= 0 { Darwin.close(self.descriptor) }
            self.descriptor = -1
            self.buffer = MPVLineBuffer()
        }
    }

    private func perform<T: Sendable>(
        _ action: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try action() })
            }
        }
    }

    private func send(_ data: Data, deadline: UInt64) throws {
        try data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                try wait(for: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                if count > 0 { sent += count }
                else if count == -1 && (errno == EAGAIN || errno == EINTR) { continue }
                else { throw PlaybackError.disconnected }
            }
        }
    }

    private func wait(for events: Int16, deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw PlaybackError.timedOut }
            let milliseconds = Int32(max(1, (deadline - now) / 1_000_000))
            var state = pollfd(fd: descriptor, events: events, revents: 0)
            let result = Darwin.poll(&state, 1, milliseconds)
            if result == -1 && errno == EINTR { continue }
            guard result > 0 else {
                throw result == 0 ? PlaybackError.timedOut : PlaybackError.disconnected
            }
            if state.revents & events != 0 { return }
            throw PlaybackError.disconnected
        }
    }
}
