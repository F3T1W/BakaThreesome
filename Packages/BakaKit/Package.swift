// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BakaKit",
    platforms: [.macOS(.v26)],
    products: [.library(name: "BakaUI", targets: ["BakaUI"])],
    targets: [
        .target(name: "Accounts"),
        .target(name: "Catalog"),
        .target(name: "Matching", dependencies: ["Catalog"]),
        .target(name: "Playback"),
        .target(name: "Tracking", dependencies: ["Catalog", "Playback"]),
        .target(name: "ShikimoriBridge"),
        .target(
            name: "BakaUI",
            dependencies: ["Accounts", "Catalog", "Matching", "Playback", "Tracking", "ShikimoriBridge"]
        ),
        .testTarget(name: "ShikimoriBridgeTests", dependencies: ["ShikimoriBridge"]),
        .testTarget(name: "PlaybackTests", dependencies: ["Playback"])
    ]
)
