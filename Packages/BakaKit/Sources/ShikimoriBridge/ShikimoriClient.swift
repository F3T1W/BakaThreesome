import Catalog
import Foundation
import Tracking

public struct ShikimoriProfile: Codable, Sendable {
    public let id: Int64
    public let nickname: String
}

public struct ShikimoriCredentials: Codable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public init(clientID: String, clientSecret: String) throws {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !clientSecret.isEmpty else { throw ShikimoriError.invalidValues }
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret
    }
    public var authorizationURL: URL {
        var components = URLComponents(string: "https://shikimori.io/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "urn:ietf:wg:oauth:2.0:oob"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "user_rates")
        ]
        return components.url!
    }
}

public struct ShikimoriTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Double
}

public struct ShikimoriClient: Sendable {
    private let transport: any BridgeTransport
    public init(transport: any BridgeTransport = BridgeProcessTransport()) { self.transport = transport }

    public func search(_ query: String, page: Int) async throws -> [AnimeSummary] {
        try await call("catalog.search", ["query": query, "page": String(page)])
    }

    public func details(_ id: Int64, accessToken: String?) async throws -> AnimeDetails {
        try await call("anime.details", ["animeID": String(id), "accessToken": accessToken])
    }

    public func whoami(_ token: String) async throws -> ShikimoriProfile {
        try await call("account.whoami", ["accessToken": token])
    }

    public func exchange(code: String, credentials: ShikimoriCredentials) async throws -> ShikimoriTokens {
        try await call("account.exchange", [
            "code": code, "clientID": credentials.clientID, "clientSecret": credentials.clientSecret
        ])
    }

    public func refresh(token: String, credentials: ShikimoriCredentials) async throws -> ShikimoriTokens {
        try await call("account.refresh", [
            "refreshToken": token, "clientID": credentials.clientID, "clientSecret": credentials.clientSecret
        ])
    }

    public func list(userID: Int64, status: WatchStatus?, page: Int, token: String) async throws -> [AnimeListEntry] {
        try await call("watchlist.list", [
            "userID": String(userID), "status": status?.rawValue,
            "page": String(page), "accessToken": token
        ])
    }

    public func save(
        animeID: Int64, rateID: Int64?, userID: Int64, status: WatchStatus,
        episodes: Int, score: Int, token: String
    ) async throws -> AnimeUserRate {
        guard episodes >= 0, (0...10).contains(score) else { throw ShikimoriError.invalidValues }
        return try await call("watchlist.save", [
            "animeID": String(animeID), "rateID": rateID.map(String.init), "userID": String(userID),
            "status": status.rawValue, "episodes": String(episodes), "score": String(score), "accessToken": token
        ])
    }

    public func shutdown() async { await transport.shutdown() }

    private func call<Result: Decodable & Sendable>(
        _ method: String, _ values: [String: String?]
    ) async throws -> Result {
        let id = UUID().uuidString
        let numbers: Set<String> = ["page", "animeID", "rateID", "userID", "episodes", "score"]
        var parameters: [String: WireValue] = [:]
        for (key, value) in values {
            guard let value else { continue }
            if numbers.contains(key), let number = Int64(value) { parameters[key] = .number(number) }
            else { parameters[key] = .string(value) }
        }
        let request = WireRequest(version: 1, id: id, method: method, parameters: parameters)
        let cancelSafe = !["account.exchange", "account.refresh", "watchlist.save"].contains(method)
        let data = try await transport.exchange(JSONEncoder().encode(request), cancelSafe: cancelSafe)
        let response: WireResponse<Result>
        do { response = try JSONDecoder().decode(WireResponse<Result>.self, from: data) }
        catch { throw ShikimoriError.invalidResponse }
        guard response.version == 1, response.id == id else { throw ShikimoriError.invalidResponse }
        if let error = response.error {
            switch error.code {
            case "unauthorized": throw ShikimoriError.unauthorized
            case "forbidden": throw ShikimoriError.forbidden
            case "rate_limited": throw ShikimoriError.rateLimited
            case "invalid_parameters": throw ShikimoriError.invalidValues
            case "timeout": throw ShikimoriError.timeout
            default: throw ShikimoriError.serviceUnavailable
            }
        }
        guard let result = response.result else { throw ShikimoriError.invalidResponse }
        return result
    }
}

private enum WireValue: Encodable {
    case string(String), number(Int64)
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        }
    }
}
private struct WireRequest: Encodable {
    let version: Int
    let id: String
    let method: String
    let parameters: [String: WireValue]
}
private struct WireResponse<Result: Decodable>: Decodable {
    let version: Int
    let id: String?
    let result: Result?
    let error: BridgeError?
}
