import Foundation

struct UpdateConfiguration {
    static let feedURL = URL(string: "https://github.com/F3T1W/ShikiThreesome/releases/latest/download/appcast.xml")!

    let publicKey: String

    init(publicKey: String) throws {
        guard let data = Data(base64Encoded: publicKey), data.count == 32 else {
            throw ConfigurationError.missingSigningKey
        }
        self.publicKey = publicKey
    }

    enum ConfigurationError: Error {
        case missingSigningKey
    }
}
