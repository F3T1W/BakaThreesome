// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BakaKit",
    platforms: [.macOS(.v26)],
    products: [.library(name: "BakaUI", targets: ["BakaUI"])],
    targets: [
        .target(name: "Accounts"),
        .target(name: "Kinopub", resources: [.process("Resources")]),
        .target(name: "Catalog"),
        .target(name: "Matching", dependencies: ["Catalog", "Kinopub"]),
        .target(name: "Playback"),
        .target(name: "Tracking", dependencies: ["Catalog", "Playback"]),
        .target(name: "ShikimoriBridge", dependencies: ["Accounts", "Catalog", "Tracking"]),
        .target(
            name: "BakaUI",
            dependencies: ["Accounts", "Kinopub", "Catalog", "Matching", "Playback", "Tracking", "ShikimoriBridge"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BakaUITests", dependencies: ["BakaUI", "ShikimoriBridge", "Catalog", "Accounts", "Playback", "Tracking", "Kinopub"]),
        .testTarget(name: "ShikimoriBridgeTests", dependencies: ["ShikimoriBridge", "Accounts", "Tracking"]),
        .testTarget(name: "PlaybackTests", dependencies: ["Playback"]),
        .testTarget(name: "KinopubTests", dependencies: ["Kinopub"]),
        .testTarget(name: "AccountsTests", dependencies: ["Accounts"]),
        .testTarget(name: "MatchingTests", dependencies: ["Matching", "Catalog", "Kinopub"]),
        .testTarget(name: "TrackingTests", dependencies: ["Tracking", "Catalog", "Playback"])
    ]
)
