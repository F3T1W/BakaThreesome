import Foundation

public struct BridgeRequest: Codable, Sendable {
    public let version: Int
    public let id: String
    public let method: String

    public init(id: String, method: String) {
        self.version = 1
        self.id = id
        self.method = method
    }
}

public struct BridgeResponse: Decodable, Sendable {
    public let version: Int
    public let id: String?
    public let result: HandshakeResult?
    public let error: BridgeError?
}

public struct HandshakeResult: Decodable, Sendable {
    public let name: String
    public let capabilities: [String]
}

public struct BridgeError: Decodable, Sendable {
    public let code: String
    public let message: String
}
