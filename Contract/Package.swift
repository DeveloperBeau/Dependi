// swift-tools-version: 6.0
import PackageDescription

// These tests run the real Swift toolchain and the real file system. They are not part of the
// default test run. Run them with `sh Scripts/contract.sh` before an Xcode or toolchain upgrade.
let package = Package(
    name: "DependiContract",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "Dependi", path: "..")],
    targets: [
        .testTarget(
            name: "ContractTests",
            dependencies: [.product(name: "DependiKit", package: "Dependi")],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        )
    ],
    swiftLanguageModes: [.v6]
)
