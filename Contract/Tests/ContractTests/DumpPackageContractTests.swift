import DependiDomain
import Foundation
import Testing

@Suite("dump-package with the real toolchain", .serialized, .timeLimit(.minutes(40)))
struct DumpPackageContractTests {
    private let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "Probe",
            products: [.library(name: "Probe", targets: ["Probe"])],
            targets: [.target(name: "Probe"), .testTarget(name: "ProbeTests", dependencies: ["Probe"])])
        """

    @Test("reading a package leaves the package folder byte for byte as it was")
    func checkoutStaysIdentical() throws {
        let package = try ContractSupport.makePackage(
            named: "probe", manifest: manifest, targets: ["Probe", "ProbeTests"])
        let scratch = try ContractSupport.temporaryFolder("scratch")
        defer {
            try? FileManager.default.removeItem(at: package);
            try? FileManager.default.removeItem(at: scratch)
        }
        let before = try ContractSupport.fingerprint(of: package)
        let reader = ContractSupport.reader(
            scratch: scratch, swift: try ContractSupport.swiftPath())
        let result = try reader.manifest(atPackagePath: package.path)
        #expect(result.products.map(\.name) == ["Probe"])
        #expect(result.targets.map(\.name) == ["Probe", "ProbeTests"])
        #expect(try ContractSupport.fingerprint(of: package) == before)
    }

    @Test("an inherited iOS SDK breaks the manifest build and the clean environment does not")
    func inheritedSDKBreaksTheBuild() throws {
        let sdk = try #require(ContractSupport.iosSDKPath(), "no iOS SDK installed")
        let package = try ContractSupport.makePackage(
            named: "probe", manifest: manifest, targets: ["Probe", "ProbeTests"])
        let scratch = try ContractSupport.temporaryFolder("scratch")
        defer {
            try? FileManager.default.removeItem(at: package);
            try? FileManager.default.removeItem(at: scratch)
        }
        let swift = try ContractSupport.swiftPath()
        let arguments = [
            "package", "--package-path", package.path, "--scratch-path", scratch.path + "/a",
            "dump-package",
        ]
        var inherited = ContractSupport.cleanEnvironment
        inherited["SDKROOT"] = sdk
        let broken = try ContractSupport.run(swift, arguments, environment: inherited)
        #expect(broken.exitStatus != 0, "the trap is gone: dump-package works with an iOS SDKROOT")
        let clean = try ContractSupport.run(
            swift, Array(arguments.dropLast(2)) + [scratch.path + "/b", "dump-package"],
            environment: ContractSupport.cleanEnvironment)
        #expect(clean.exitStatus == 0)
    }

    @Test("a manifest cannot write a file outside its folder")
    func manifestSandbox() throws {
        let probe = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
            "dependi-contract-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: probe) }
        let evil = """
            // swift-tools-version: 6.0
            import PackageDescription
            import Foundation
            try? "x".write(toFile: "\(probe.path)", atomically: true, encoding: .utf8)
            let package = Package(name: "Evil", targets: [.target(name: "Evil")])
            """
        let package = try ContractSupport.makePackage(
            named: "evil", manifest: evil, targets: ["Evil"])
        let scratch = try ContractSupport.temporaryFolder("scratch")
        defer {
            try? FileManager.default.removeItem(at: package);
            try? FileManager.default.removeItem(at: scratch)
        }
        _ = try? ContractSupport.reader(scratch: scratch, swift: try ContractSupport.swiftPath())
            .manifest(atPackagePath: package.path)
        #expect(
            !FileManager.default.fileExists(atPath: probe.path),
            "the manifest wrote outside its folder")
    }

    @Test("a package with four hundred targets is read in full")
    func largePackage() throws {
        let names = (0..<400).map { "Target\($0)" }
        let targets = names.map { ".target(name: \"\($0)\")" }.joined(separator: ",\n")
        let products = names.map { ".library(name: \"\($0)\", targets: [\"\($0)\"])" }.joined(
            separator: ",\n")
        let big = """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "Big", products: [\(products)], targets: [\(targets)])
            """
        let package = try ContractSupport.makePackage(named: "big", manifest: big, targets: names)
        let scratch = try ContractSupport.temporaryFolder("scratch")
        defer {
            try? FileManager.default.removeItem(at: package);
            try? FileManager.default.removeItem(at: scratch)
        }
        let result = try ContractSupport.reader(
            scratch: scratch, swift: try ContractSupport.swiftPath()
        )
        .manifest(atPackagePath: package.path)
        #expect(result.targets.count == 400)
        #expect(result.products.count == 400)
    }

    @Test("a second read uses the cache and a changed manifest is read again")
    func cacheWithTheRealTool() throws {
        let package = try ContractSupport.makePackage(
            named: "probe", manifest: manifest, targets: ["Probe", "ProbeTests"])
        let scratch = try ContractSupport.temporaryFolder("scratch")
        defer {
            try? FileManager.default.removeItem(at: package);
            try? FileManager.default.removeItem(at: scratch)
        }
        let reader = ContractSupport.reader(
            scratch: scratch, swift: try ContractSupport.swiftPath())
        let first = try reader.manifest(atPackagePath: package.path)
        let scratchFolder = scratch.appendingPathComponent("scratch")
        try FileManager.default.removeItem(at: scratchFolder)
        let second = try reader.manifest(atPackagePath: package.path)
        #expect(first == second)
        #expect(
            !FileManager.default.fileExists(atPath: scratchFolder.path),
            "the second read started the tool again")
        let changed = manifest.replacingOccurrences(
            of: "\"Probe\", targets", with: "\"ProbeRenamed\", targets")
        try changed.write(
            to: package.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let third = try reader.manifest(atPackagePath: package.path)
        #expect(third.products.map(\.name) == ["ProbeRenamed"])
    }
}
