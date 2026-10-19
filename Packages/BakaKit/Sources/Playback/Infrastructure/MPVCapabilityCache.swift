import Foundation

/// Shares successful probes until the resolved executable changes. Failed probes remain retryable.
public actor MPVCapabilityCache {
    private struct Key: Hashable {
        let url: URL
        let modified: Date?
        let size: Int?
    }
    private let probe: @Sendable (URL) async throws -> PlayerCapabilities
    private var values: [Key: PlayerCapabilities] = [:]
    private var pending: [Key: Task<PlayerCapabilities, Error>] = [:]

    public init(probe: @escaping @Sendable (URL) async throws -> PlayerCapabilities = {
        try await MPVCapabilityProbe(executable: $0).inspect()
    }) { self.probe = probe }

    public func inspect(_ executable: URL) async throws -> PlayerCapabilities {
        let url = executable.resolvingSymlinksInPath()
        let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = Key(url: url, modified: attributes.contentModificationDate, size: attributes.fileSize)
        if let value = values[key] { return value }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await probe(url) }
        pending[key] = task
        defer { pending[key] = nil }
        let value = try await task.value
        values = values.filter { $0.key.url != url }
        values[key] = value
        return value
    }

    public func shutdown() async {
        let tasks = Array(pending.values)
        for task in tasks { task.cancel() }
        for task in tasks { _ = try? await task.value }
    }
}
