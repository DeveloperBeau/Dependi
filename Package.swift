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
            name: "DependiInit",
            dependencies: ["DependiEntities", "DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiInitTests",
            dependencies: [
                "DependiInit", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiComposition",
            dependencies: [
                "DependiEntities", "DependiDomain", "DependiFileSystem", "DependiEnvironment",
                "DependiConsole", "DependiWorkspaceState", "DependiProjectFile",
                "DependiPackageGraph",
                "DependiSettingsBundle", "DependiGenerate", "DependiCommandLine",
            ],
            swiftSettings: sharedSettings
        ),
        .executableTarget(
            name: "dependi",
            dependencies: ["DependiComposition", "DependiProcess"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiCompositionTests",
            dependencies: [
                "DependiComposition", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            swiftSettings: sharedSettings
        ),
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
        .target(
            name: "DependiProcess",
            dependencies: ["DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiProcessTests",
            dependencies: ["DependiProcess", "DependiDomain", "TestHelpers"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiConsole",
            dependencies: ["DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiConsoleTests",
            dependencies: ["DependiConsole", "DependiDomain", "TestHelpers"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiWorkspaceState",
            dependencies: ["DependiEntities", "DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiWorkspaceStateTests",
            dependencies: [
                "DependiWorkspaceState", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiProjectFile",
            dependencies: ["DependiEntities", "DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiProjectFileTests",
            dependencies: [
                "DependiProjectFile", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiPackageGraph",
            dependencies: ["DependiEntities", "DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiPackageGraphTests",
            dependencies: [
                "DependiPackageGraph", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiSettingsBundle",
            dependencies: ["DependiEntities", "DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiSettingsBundleTests",
            dependencies: [
                "DependiSettingsBundle", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            exclude: ["Fixtures"],
            swiftSettings: sharedSettings
        ),
        .target(name: "DependiCommandLine", swiftSettings: sharedSettings),
        .testTarget(
            name: "DependiCommandLineTests",
            dependencies: ["DependiCommandLine", "TestHelpers"],
            swiftSettings: sharedSettings
        ),
        .target(
            name: "DependiGenerate",
            dependencies: ["DependiEntities", "DependiDomain"],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "DependiGenerateTests",
            dependencies: [
                "DependiGenerate", "DependiDomain", "DependiEntities", "DependiTestSupport",
                "TestHelpers",
            ],
            swiftSettings: sharedSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
