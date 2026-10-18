import Foundation

struct OwnedTemporaryDirectory: Sendable {
    let url: URL

    init() throws {
        // Keep Unix socket paths below Darwin's sun_path limit, independently of TMPDIR.
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("bakathreesome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
