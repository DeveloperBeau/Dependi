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
        .target(
            name: "DependiDomain",
            dependencies: ["DependiEntities"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiTestSupport",
            dependencies: ["DependiEntities", "DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiDomainTests",
            dependencies: [
                "DependiDomain", "DependiEntities", "DependiTestSupport", "TestHelpers",
            ],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiTestSupportTests",
            dependencies: [
                "DependiTestSupport", "DependiDomain", "DependiEntities", "TestHelpers",
            ],
            swiftSettings: sharedSettings
        ),
        .target(name: "DependiEntities", swiftSettings: sharedSettings),
        .testTarget(
            name: "DependiEntitiesTests",
            dependencies: ["DependiEntities", "TestHelpers"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "TestHelpers",
            path: "Tests/TestHelpers",
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "RepositoryChecksTests",
            dependencies: ["TestHelpers"],
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "MutationRunnerTests",
            dependencies: ["TestHelpers"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "ArchitectureTests",
            dependencies: ["TestHelpers"],
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiFileSystem",
            dependencies: ["DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiFileSystemTests",
            dependencies: [
                "DependiFileSystem", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiEnvironment",
            dependencies: ["DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiEnvironmentTests",
            dependencies: ["DependiEnvironment", "DependiDomain", "TestHelpers"],
            swiftSettings: sharedSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
