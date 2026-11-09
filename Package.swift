// swift-tools-version: 6.0
import PackageDescription

/// Settings that every target in this package shares.
let sharedSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "Dependi",
    platforms: [.macOS(.v14)],
    targets: [
        .testTarget(
            name: "RepositoryChecksTests",
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "ArchitectureTests",
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
