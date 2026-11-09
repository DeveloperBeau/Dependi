import DependiDomain
import TestHelpers
import Testing

@Suite("Source packages locator", .timeLimit(.minutes(1)))
struct SourcePackagesLocatorTests {
    private let locator = SourcePackagesLocator()

    @Test("a normal build directory gives the folder next to Build")
    func normalBuild() throws {
        let result = try locator.locate(
            buildDirectory: "/work/DerivedData/App-abc/Build/Products", configuredPath: nil)
        #expect(result == "/work/DerivedData/App-abc/SourcePackages")
    }

    @Test("an archive build directory gives the same folder")
    func archiveBuild() throws {
        let result = try locator.locate(
            buildDirectory:
                "/work/DerivedData/App-abc/Build/Intermediates.noindex/ArchiveIntermediates/App/BuildProductsPath",
            configuredPath: nil)
        #expect(result == "/work/DerivedData/App-abc/SourcePackages")
    }

    @Test("a Build folder earlier in the user path does not cut early")
    func earlierBuildFolderIsIgnored() throws {
        let result = try locator.locate(
            buildDirectory: "/work/Build/Products/DD/App-abc/Build/Products/Debug-iphoneos",
            configuredPath: nil)
        #expect(result == "/work/Build/Products/DD/App-abc/SourcePackages")
    }

    @Test("a scheme named Build inside an archive path does not cut early")
    func schemeNamedBuild() throws {
        let result = try locator.locate(
            buildDirectory:
                "/work/DD/App-abc/Build/Intermediates.noindex/ArchiveIntermediates/Build/BuildProductsPath",
            configuredPath: nil)
        #expect(result == "/work/DD/App-abc/SourcePackages")
    }

    @Test("a configured path wins, and an empty configured path is ignored")
    func configuredPath() throws {
        #expect(
            try locator.locate(buildDirectory: nil, configuredPath: "/ci/SourcePackages")
                == "/ci/SourcePackages")
        #expect(
            try locator.locate(buildDirectory: "/w/DD/Build/Products/x", configuredPath: "")
                == "/w/DD/SourcePackages")
    }

    @Test("a path with no anchor, a relative path and a missing path fail and name what was tried")
    func failures() {
        #expect(throws: DomainError.sourcePackagesNotFound(tried: "/work/build/output")) {
            try locator.locate(buildDirectory: "/work/build/output", configuredPath: nil)
        }
        #expect(throws: DomainError.sourcePackagesNotFound(tried: "Build/Products")) {
            try locator.locate(buildDirectory: "Build/Products", configuredPath: nil)
        }
        #expect(throws: DomainError.sourcePackagesNotFound(tried: "(no build directory)")) {
            try locator.locate(buildDirectory: nil, configuredPath: nil)
        }
        #expect(throws: DomainError.sourcePackagesNotFound(tried: "/w/Build/Other/x")) {
            try locator.locate(buildDirectory: "/w/Build/Other/x", configuredPath: nil)
        }
    }

    @Test(
        "fuzz: the result ends in SourcePackages and is the part of the input before the last anchor"
    )
    func fuzzProperty() throws {
        let names = [
            "work", "Build", "Products", "Intermediates.noindex", "DD", "App", "x", "build",
        ]
        for seed in [SeededGenerator.defaultSeed, 8, 64] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<300 {
                let count = Int.random(in: 1...9, using: &generator)
                let parts = (0..<count).map { _ in names.randomElement(using: &generator)! }
                let path = "/" + parts.joined(separator: "/")
                var anchor: Int?
                for index in parts.indices.dropLast()
                where parts[index] == "Build"
                    && (parts[index + 1] == "Products"
                        || parts[index + 1] == "Intermediates.noindex")
                {
                    anchor = index
                }
                if let anchor {
                    let expected =
                        "/" + (parts[..<anchor] + ["SourcePackages"]).joined(separator: "/")
                    #expect(
                        try locator.locate(buildDirectory: path, configuredPath: nil) == expected,
                        "path \(path)")
                } else {
                    #expect(throws: DomainError.sourcePackagesNotFound(tried: path)) {
                        try locator.locate(buildDirectory: path, configuredPath: nil)
                    }
                }
            }
        }
    }
}
