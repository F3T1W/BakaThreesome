import Foundation

public struct AnimePoster: Codable, Sendable {
    public let animeID: Int64
    public let imageURL: URL?

    public var safeImageURL: URL? {
        guard let imageURL, imageURL.scheme == "https", imageURL.host != nil,
              imageURL.user == nil, imageURL.password == nil else { return nil }
        return imageURL
    }
}
