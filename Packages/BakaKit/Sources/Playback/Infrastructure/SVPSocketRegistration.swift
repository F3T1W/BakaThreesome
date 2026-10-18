import Darwin
import Foundation
import Synchronization

/// Advertises only this player's private socket using SVP's mpvSockets discovery convention.
final class SVPSocketRegistration: Sendable {
    private let directory: URL
    private let published = Mutex<(link: URL, socket: URL)?>(nil)

    init(directory: URL = URL(fileURLWithPath: "/tmp/mpvSockets", isDirectory: true)) throws {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            // An existing directory is shared with other mpv instances; never replace or chmod it.
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              info.st_mode & 0o022 == 0 else { throw PlaybackError.svpRegistrationFailed }
    }

    func publish(socket: URL, processID: Int32) throws {
        try published.withLock { current in
            guard current == nil, processID > 0 else { throw PlaybackError.svpRegistrationFailed }
            // SVP recognizes numeric filenames. Never overwrite an existing registration.
            let link = directory.appendingPathComponent(String(processID))
            do {
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: socket)
                current = (link, socket)
            } catch {
                throw PlaybackError.svpRegistrationFailed
            }
        }
    }

    func remove() {
        published.withLock { current in
            guard let owned = current else { return }
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: owned.link.path)) == owned.socket.path {
                try? FileManager.default.removeItem(at: owned.link)
            }
            current = nil
        }
    }
}
