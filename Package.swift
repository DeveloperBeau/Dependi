// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dependi",
    platforms: [.macOS(.v14)],
    targets: [
        .testTarget(
            name: "RepositoryChecksTests",
            exclude: ["Fixtures"]
        )
    ]
)
