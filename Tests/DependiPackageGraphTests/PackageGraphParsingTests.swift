import DependiPackageGraph
import DependiDomain
import DependiTestSupport
import Foundation
import TestHelpers
import Testing

@Suite("Package graph parsing", .timeLimit(.minutes(1)))
struct PackageGraphParsingTests {
    private func manifest(_ fixtureName: String) throws -> PackageManifest {
        let files = try GraphTestSupport.files()
        let runner = FakeProcessRunner(results: [
            GraphTestSupport.success(try GraphTestSupport.fixture(fixtureName))
        ])
        return try GraphTestSupport.reader(files: files, runner: runner).manifest(
            atPackagePath: GraphTestSupport.packagePath)
    }

    private func dependency(
        _ kind: ManifestDependency.Kind, _ name: String, package: String? = nil,
        platforms: [String] = []
    ) -> ManifestDependency {
        ManifestDependency(kind: kind, name: name, packageName: package, platforms: platforms)
    }

    @Test("a small real package parses to the hand-written manifest")
    func smallRealPackage() throws {
        let expected = PackageManifest(
            products: [
                ManifestProduct(name: "Logging", targetNames: ["Logging"]),
                ManifestProduct(name: "InMemoryLogging", targetNames: ["InMemoryLogging"]),
            ],
            targets: [
                ManifestTarget(name: "Logging", kind: .regular, dependencies: []),
                ManifestTarget(
                    name: "InMemoryLogging", kind: .regular,
                    dependencies: [dependency(.byName, "Logging")]),
                ManifestTarget(
                    name: "LoggingTests", kind: .test,
                    dependencies: [dependency(.byName, "Logging")]),
                ManifestTarget(
                    name: "InMemoryLoggingTests", kind: .test,
                    dependencies: [
                        dependency(.byName, "InMemoryLogging"), dependency(.byName, "Logging"),
                    ]),
            ],
            declaredDependencies: [])
        #expect(try manifest("swift-log") == expected)
    }

    @Test("a binary target is read as binary")
    func binaryTarget() throws {
        let expected = PackageManifest(
            products: [ManifestProduct(name: "abseil", targetNames: ["abslWrapper"])],
            targets: [
                ManifestTarget(
                    name: "abslWrapper", kind: .regular, dependencies: [dependency(.byName, "absl")]
                ),
                ManifestTarget(name: "absl", kind: .binary, dependencies: []),
            ],
            declaredDependencies: [])
        #expect(try manifest("abseil-cpp-binary") == expected)
    }

    @Test(
        "plugin, executable, binary, platform conditions, product packages and declared dependencies are read"
    )
    func syntheticPackage() throws {
        let result = try manifest("synth")
        let expectedTargets = [
            ManifestTarget(
                name: "Synth", kind: .regular,
                dependencies: [
                    dependency(.byName, "Shared"),
                    dependency(.product, "HelperKit", package: "Helper-Kit"),
                    dependency(.product, "MacOnly", package: "Helper-Kit", platforms: ["macos"]),
                    dependency(.product, "LocalProduct", package: "LocalKit"),
                    dependency(.target, "Frame", platforms: ["ios", "visionos"]),
                ]),
            ManifestTarget(name: "Shared", kind: .regular, dependencies: []),
            ManifestTarget(
                name: "SynthPlugin", kind: .plugin, dependencies: [dependency(.byName, "Tool")]),
            ManifestTarget(name: "Tool", kind: .executable, dependencies: []),
            ManifestTarget(name: "Frame", kind: .binary, dependencies: []),
            ManifestTarget(
                name: "SynthTests", kind: .test, dependencies: [dependency(.byName, "Synth")]),
        ]
        #expect(result.targets == expectedTargets)
        #expect(
            result.products == [
                ManifestProduct(name: "Synth", targetNames: ["Synth"]),
                ManifestProduct(name: "SynthPlugin", targetNames: ["SynthPlugin"]),
            ])
        #expect(result.declaredDependencies == ["helper-kit", "localkit"])
    }

    @Test("a macro target and its product dependencies are read")
    func macroTarget() throws {
        let result = try manifest("macro")
        let macro = try #require(result.targets.first { $0.name == "MacroTplMacros" })
        #expect(macro.kind == .macro)
        #expect(
            macro.dependencies == [
                dependency(.product, "SwiftSyntaxMacros", package: "swift-syntax"),
                dependency(.product, "SwiftCompilerPlugin", package: "swift-syntax"),
            ])
        #expect(result.declaredDependencies == ["swift-syntax"])
        #expect(
            result.targets.first { $0.name == "MacroTpl" }?.dependencies == [
                dependency(.byName, "MacroTplMacros")
            ])
    }

    @Test(
        "a real package with plugins keeps product packages named in other case and platform lists")
    func pluginPackage() throws {
        let result = try manifest("swift-openapi-generator")
        #expect(result.declaredDependencies.contains("openapikit"))
        #expect(result.declaredDependencies.contains("swift-algorithms"))
        let core = try #require(result.targets.first { $0.name == "_OpenAPIGeneratorCore" })
        #expect(
            core.dependencies.contains(dependency(.product, "OpenAPIKit30", package: "OpenAPIKit")))
        let tests = try #require(result.targets.first { $0.name == "OpenAPIGeneratorTests" })
        #expect(
            tests.dependencies.contains(
                dependency(
                    .target, "swift-openapi-generator",
                    platforms: ["android", "linux", "macos", "openbsd", "wasi", "freebsd"])))
        #expect(result.products.contains { $0.name == "OpenAPIGenerator" })
    }

    @Test("a large real package parses and every product target exists")
    func largeRealPackage() throws {
        let result = try manifest("swift-nio")
        #expect(result.products.count == 14)
        #expect(result.targets.count == 60)
        let names = Set(result.targets.map(\.name))
        for product in result.products {
            #expect(product.targetNames.allSatisfy(names.contains), "product \(product.name)")
        }
    }

    @Test("a package with a versioned manifest parses")
    func versionedManifestPackage() throws {
        let result = try manifest("swift-argument-parser")
        #expect(result.products.contains { $0.name == "ArgumentParser" })
    }

    @Test("a dependency of an unknown shape is ignored and the rest is kept")
    func unknownDependencyShapeIgnored() throws {
        let json = """
            {"products":[{"name":"P","targets":["T"]}],
             "targets":[{"name":"T","type":"regular","dependencies":[{"strange":["x"]},{"byName":["U",null]}]}],
             "dependencies":[{"registry":[{"identity":"Scope.Name"}]}]}
            """
        let files = try GraphTestSupport.files()
        let runner = FakeProcessRunner(results: [GraphTestSupport.success(Data(json.utf8))])
        let result = try GraphTestSupport.reader(files: files, runner: runner).manifest(
            atPackagePath: GraphTestSupport.packagePath)
        #expect(result.targets.first?.dependencies == [dependency(.byName, "U")])
        #expect(result.declaredDependencies == ["scope.name"])
    }

    @Test("local dependency folders are read, and a relative one is resolved against the package")
    func localDependencyPaths() throws {
        let json = """
            {"products":[],"targets":[],
             "dependencies":[
               {"fileSystem":[{"identity":"shared","path":"../shared"}]},
               {"fileSystem":[{"identity":"core","path":"/work/core/"}]},
               {"sourceControl":[{"identity":"remote-kit","location":{"remote":[{"urlString":"https://example.com/remote-kit"}]}}]},
               {"fileSystem":[{"identity":"empty","path":""}]}]}
            """
        let files = try GraphTestSupport.files()
        let runner = FakeProcessRunner(results: [GraphTestSupport.success(Data(json.utf8))])
        let result = try GraphTestSupport.reader(files: files, runner: runner).manifest(
            atPackagePath: GraphTestSupport.packagePath)
        #expect(result.localDependencyPaths == ["/checkouts/shared", "/work/core"])
        #expect(result.declaredDependencies == ["shared", "core", "remote-kit", "empty"])
    }

    @Test("an output of about five megabytes parses")
    func fiveMegabyteOutput() throws {
        var targets: [String] = []
        for index in 0..<30_000 {
            targets.append(
                "{\"name\":\"T\(index)\",\"type\":\"regular\",\"dependencies\":[{\"byName\":[\"T0\",null]}],\"padding\":\"\(String(repeating: "x", count: 120))\"}"
            )
        }
        let json =
            "{\"products\":[{\"name\":\"P\",\"targets\":[\"T0\"]}],\"targets\":[\(targets.joined(separator: ","))],\"dependencies\":[]}"
        #expect(json.utf8.count > 4_500_000)
        let files = try GraphTestSupport.files()
        let runner = FakeProcessRunner(results: [GraphTestSupport.success(Data(json.utf8))])
        let result = try GraphTestSupport.reader(files: files, runner: runner).manifest(
            atPackagePath: GraphTestSupport.packagePath)
        #expect(result.targets.count == 30_000)
    }

    @Test("fuzz: truncated and corrupted real output always gives a domain error and never crashes")
    func fuzzCorruptedOutput() throws {
        let original = try GraphTestSupport.fixture("swift-log")
        var generator = SeededGenerator()
        for index in 0..<120 {
            var data = original
            if index % 2 == 0 {
                data = data.prefix(Int.random(in: 0..<(original.count - 1), using: &generator))
            } else {
                for _ in 0..<Int.random(in: 1...6, using: &generator) {
                    data[Int.random(in: 0..<data.count, using: &generator)] = UInt8.random(
                        in: 0...255, using: &generator)
                }
            }
            let files = try GraphTestSupport.files()
            let runner = FakeProcessRunner(results: [GraphTestSupport.success(data)])
            let reader = GraphTestSupport.reader(files: files, runner: runner)
            do {
                _ = try reader.manifest(atPackagePath: GraphTestSupport.packagePath)
            } catch {
                #expect(error is DomainError)
            }
        }
    }

    @Test(
        "output that is not a manifest is refused with the package path",
        arguments: [
            "", "not json", "[]", "{}", "{\"products\":[]}", "{\"targets\":[]}", "null",
            "{\"products\":[{}],\"targets\":[]}",
            "{\"products\":[],\"targets\":[{\"type\":\"regular\"}]}",
        ])
    func malformedOutputRefused(text: String) throws {
        let files = try GraphTestSupport.files()
        let runner = FakeProcessRunner(results: [GraphTestSupport.success(Data(text.utf8))])
        do {
            _ = try GraphTestSupport.reader(files: files, runner: runner).manifest(
                atPackagePath: GraphTestSupport.packagePath)
            Issue.record("accepted: \(text)")
        } catch DomainError.processFailed(let command, let reason) {
            #expect(command == "swift package dump-package")
            #expect(reason.contains("/checkouts/kit"))
        }
    }
}
