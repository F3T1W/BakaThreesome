import Foundation

enum MPVValue: Codable, Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case array([MPVValue])
    case object([String: MPVValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([MPVValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: MPVValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct MPVRequest: Encodable {
    let command: [MPVValue]
    let request_id: Int
}

struct MPVMessage: Decodable {
    let request_id: Int?
    let error: String?
    let data: MPVValue?
}

struct MPVLineBuffer {
    private var bytes = Data()
    private let maximumBytes = 1_048_576

    mutating func append(_ data: Data) throws {
        guard bytes.count + data.count <= maximumBytes else {
            throw PlaybackError.invalidResponse
        }
        bytes.append(data)
    }

    mutating func nextMessage() throws -> MPVMessage? {
        guard let newline = bytes.firstIndex(of: 0x0A) else { return nil }
        let line = Data(bytes.prefix(upTo: newline))
        bytes.removeSubrange(bytes.startIndex...newline)
        do {
            return try JSONDecoder().decode(MPVMessage.self, from: line)
        } catch {
            throw PlaybackError.invalidResponse
        }
    }
}
