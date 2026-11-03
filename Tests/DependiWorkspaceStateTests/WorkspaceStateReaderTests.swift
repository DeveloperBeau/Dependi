import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import TestHelpers
import Testing

@testable import DependiWorkspaceState

// Real files: `real-v7-remote` and `real-v7-local` come from folders that Xcode 27.2 (build 27B52)
// and SwiftPM wrote on this machine. Both carry the file's own `"version" : 7`. Paths are scrubbed
// to `$ROOT`. The v5 and v6 files are written by hand from the SwiftPM history of this format.

@Suite("Workspace state file")
struct WorkspaceStateReaderTests {
    private func reader(_ fileSystem: InMemoryFileSystem) -> WorkspaceStateReader {
        WorkspaceStateReader(files: fileSystem, directories: fileSystem)
    }

    private func resolve(_ fileSystem: InMemoryFileSystem) throws(DomainError) -> [ResolvedPackage]
    {
        try reader(fileSystem).resolvedPackages(sourcePackagesPath: Support.sourcePackages)
    }

    private func checkout(_ name: String) -> String {
        Support.sourcePackages + "/checkouts/" + name
    }

    @Test("a real version 7 file with remote packages gives the four packages")
    func realVersion7Remote() throws {
        let text = try Support.fixture("real-v7-remote.workspace-state.json")
        let names = ["swift-async-algorithms", "swift-collections", "swift-docc-plugin"]
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.data(text), checkouts: names + ["swift-docc-symbolkit"])
        let packages = try resolve(fileSystem)
        #expect(
            packages == [
                ResolvedPackage(
                    identity: PackageIdentity("swift-async-algorithms"), kind: .remote,
                    normalizedLocation: "apple/swift-async-algorithms", version: "1.1.3",
                    revision: "9d349bcc328ac3c31ce40e746b5882742a0d1272",
                    checkoutPath: checkout("swift-async-algorithms")),
                ResolvedPackage(
                    identity: PackageIdentity("swift-collections"), kind: .remote,
                    normalizedLocation: "apple/swift-collections", version: "1.4.1",
                    revision: "6675bc0ff86e61436e615df6fc5174e043e57924",
                    checkoutPath: checkout("swift-collections")),
                ResolvedPackage(
                    identity: PackageIdentity("swift-docc-plugin"), kind: .remote,
                    normalizedLocation: "apple/swift-docc-plugin", version: "1.4.6",
                    revision: "e977f65879f82b375a044c8837597f690c067da6",
                    checkoutPath: checkout("swift-docc-plugin")),
                ResolvedPackage(
                    identity: PackageIdentity("swift-docc-symbolkit"), kind: .remote,
                    normalizedLocation: "swiftlang/swift-docc-symbolkit", version: "1.0.0",
                    revision: "b45d1f2ed151d057b54504d653e0da5552844e34",
                    checkoutPath: checkout("swift-docc-symbolkit")),
            ])
    }

    @Test("a real version 7 file with a file system package maps it to local with its path")
    func localPackageIsLocal() throws {
        let text = try Support.fixture("real-v7-local.workspace-state.json")
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.data(text), checkouts: ["GRDB.swift"])
        let packages = try resolve(fileSystem)
        #expect(
            packages == [
                ResolvedPackage(
                    identity: PackageIdentity("geomodels"), kind: .local,
                    normalizedLocation: "/work/packages/core/geomodels", version: nil,
                    revision: nil, checkoutPath: "/work/Packages/Core/GeoModels"),
                ResolvedPackage(
                    identity: PackageIdentity("grdb.swift"), kind: .remote,
                    normalizedLocation: "groue/grdb.swift", version: "7.8.0",
                    revision: "18497b68fdbb3a09528d260a0a0e1e7e61c8c53d",
                    checkoutPath: checkout("GRDB.swift")),
            ])
    }

    @Test("a version 5 file with the old checkout state name is read")
    func version5() throws {
        let text = try Support.fixture("hand-v5.workspace-state.json")
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.data(text), checkouts: ["Alpha-Kit"])
        #expect(
            try resolve(fileSystem) == [
                ResolvedPackage(
                    identity: PackageIdentity("alpha-kit"), kind: .remote,
                    normalizedLocation: "example/alpha-kit", version: "2.3.4",
                    revision: "1111111111111111111111111111111111111111",
                    checkoutPath: checkout("Alpha-Kit"))
            ])
    }

    @Test("a version 6 file reads a branch checkout and a local source control package")
    func version6() throws {
        let text = try Support.fixture("hand-v6.workspace-state.json")
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.data(text), checkouts: ["Beta-Kit", "Gamma"])
        #expect(
            try resolve(fileSystem) == [
                ResolvedPackage(
                    identity: PackageIdentity("beta-kit"), kind: .remote,
                    normalizedLocation: "example/beta-kit", version: nil,
                    revision: "2222222222222222222222222222222222222222",
                    checkoutPath: checkout("Beta-Kit")),
                ResolvedPackage(
                    identity: PackageIdentity("gamma"), kind: .local,
                    normalizedLocation: "/work/packages/gamma", version: nil, revision: nil,
                    checkoutPath: "/work/Packages/Gamma"),
            ])
    }

    @Test("unknown extra fields and a newer version number are tolerated")
    func unknownFieldsAreTolerated() throws {
        let body = Support.remote()
            .replacingOccurrences(
                of: "\"basedOn\":null,", with: "\"basedOn\":null,\"future\":{\"a\":[1,2]},")
        let text =
            "{\"extra\":true,\"object\":{\"prebuilts\":[],\"dependencies\":[\(body)]},\"version\":9}"
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.data(text), checkouts: ["kit"])
        let packages = try resolve(fileSystem)
        #expect(packages.map(\.identity.value) == ["kit"])
        #expect(packages.first?.version == "1.0.0")
    }

    @Test("an empty dependency list gives an empty result")
    func emptyDependencies() throws {
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.state(dependencies: []), checkouts: [])
        #expect(try resolve(fileSystem).isEmpty)
    }

    @Test("a dependency that was removed from the file is not listed")
    func removedDependencyIsNotListed() throws {
        let state = Support.state(dependencies: [
            Support.remote(identity: "kept", location: "https://h/o/kept", subpath: "kept")
        ])
        let fileSystem = try Support.sourcePackagesTree(
            state: state, checkouts: ["kept", "removed"])
        #expect(try resolve(fileSystem).map(\.identity.value) == ["kept"])
    }

    @Test("a nested subpath is listed with its full checkout path")
    func nestedSubpathIsListed() throws {
        let state = Support.state(dependencies: [Support.remote(subpath: "scope/kit")])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: ["scope/kit"])
        #expect(try resolve(fileSystem).map(\.checkoutPath) == [checkout("scope/kit")])
    }

    @Test("the identity comes from the location and not from the identity field")
    func identityFromLocation() throws {
        let state = Support.state(dependencies: [
            Support.remote(
                identity: "wrong-name", location: "https://github.com/Owner/Right-Name.git",
                subpath: "k")
        ])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: ["k"])
        #expect(try resolve(fileSystem).map(\.identity.value) == ["right-name"])
    }

    @Test("the identity field is used when the location is empty")
    func identityFieldWhenLocationEmpty() throws {
        let state = Support.state(dependencies: [
            Support.remote(identity: "Fallback", location: "", subpath: "k")
        ])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: ["k"])
        #expect(try resolve(fileSystem).map(\.identity.value) == ["fallback"])
    }

    @Test("a remote package in the state of an edited package is read as local")
    func editedPackageIsLocal() throws {
        let body =
            "{\"packageRef\":{\"identity\":\"kit\",\"kind\":\"remoteSourceControl\",\"location\":\"https://h/o/kit\"},\"state\":{\"name\":\"edited\",\"path\":\"/work/Edits/kit\"},\"subpath\":\"kit\"}"
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.state(dependencies: [body]), checkouts: [])
        let packages = try resolve(fileSystem)
        #expect(packages.map(\.kind) == [.local])
        #expect(packages.map(\.checkoutPath) == ["/work/Edits/kit"])
    }

    @Test("a registry package is skipped and the other packages are still read")
    func registryPackageIsSkipped() throws {
        let body =
            "{\"packageRef\":{\"identity\":\"scope.kit\",\"kind\":\"registry\",\"location\":\"\"},\"state\":{\"name\":\"registryDownload\",\"version\":\"1.0.0\"},\"subpath\":\"scope/kit\"}"
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.state(dependencies: [body, Support.remote()]), checkouts: ["kit"])
        let packages = try resolve(fileSystem)
        #expect(packages.map(\.identity) == [PackageIdentity("kit")])
    }

    @Test("a package of an unknown kind is still refused and the reason names the kind")
    func unknownKindIsRefused() throws {
        let body =
            "{\"packageRef\":{\"identity\":\"kit\",\"kind\":\"mystery\",\"location\":\"\"},\"state\":{\"name\":\"x\"},\"subpath\":\"kit\"}"
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.state(dependencies: [body]), checkouts: [])
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        guard case .fileUnreadable(_, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(reason.contains("mystery"))
    }

    @Test("a remote package with no checkout state fails")
    func remoteWithoutCheckoutState() throws {
        let body =
            "{\"packageRef\":{\"identity\":\"kit\",\"kind\":\"remoteSourceControl\",\"location\":\"https://h/o/kit\"},\"state\":{\"name\":\"other\"},\"subpath\":\"kit\"}"
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.state(dependencies: [body]), checkouts: ["kit"])
        #expect(throws: DomainError.self) { try resolve(fileSystem) }
    }

    @Test("a missing dependencies field fails and names the file and the version")
    func missingDependenciesNamesFileAndVersion() throws {
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.data("{\"object\":{},\"version\":6}"), checkouts: [])
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        guard case .fileUnreadable(let path, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(path == Support.sourcePackages + "/workspace-state.json")
        #expect(reason.contains("version 6"))
        #expect(reason.contains("dependencies"))
    }

    @Test("a missing package reference fails and names the version")
    func missingPackageRef() throws {
        let fileSystem = try Support.sourcePackagesTree(
            state: Support.data(
                "{\"object\":{\"dependencies\":[{\"subpath\":\"k\"}]},\"version\":7}"),
            checkouts: ["k"])
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        guard case .fileUnreadable(_, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(reason.contains("version 7"))
        #expect(reason.contains("packageRef"))
    }

    @Test("a missing state file fails with file not found naming it")
    func missingStateFile() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: Support.sourcePackages)
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        #expect(error == .fileNotFound(path: Support.sourcePackages + "/workspace-state.json"))
    }

    @Test("a file over the size cap fails but a file at the cap is read")
    func sizeCap() throws {
        let valid = Support.state(dependencies: [])
        let cap = WorkspaceStateReader.maximumBytes
        let atCap = valid + Data(repeating: 0x20, count: cap - valid.count)
        let over = atCap + Data([0x20])
        let allowed = try Support.sourcePackagesTree(state: atCap, checkouts: [])
        #expect(try resolve(allowed).isEmpty)
        let refused = try Support.sourcePackagesTree(state: over, checkouts: [])
        #expect(throws: DomainError.self) { try resolve(refused) }
    }

    // MARK: Subpath and containment

    @Test(
        "a subpath that goes up a folder is refused",
        arguments: ["../..", "../x", "a/../../x", ".."])
    func subpathTraversalIsRefused(subpath: String) throws {
        let state = Support.state(dependencies: [Support.remote(subpath: subpath)])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: ["x"])
        try fileSystem.addDirectory(at: Support.sourcePackages + "/x")
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        guard case .fileUnreadable(_, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(reason.contains("goes up"))
    }

    @Test("an absolute subpath is refused")
    func absoluteSubpathIsRefused() throws {
        let state = Support.state(dependencies: [
            Support.remote(subpath: "/work/DD/SourcePackages/checkouts/kit")
        ])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: ["kit"])
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        guard case .fileUnreadable(_, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(reason.contains("absolute"))
    }

    @Test("an empty subpath is refused")
    func emptySubpathIsRefused() throws {
        let state = Support.state(dependencies: [Support.remote(subpath: "")])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: [])
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        guard case .fileUnreadable(_, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(reason.contains("empty"))
    }

    @Test("a subpath with dots in a name that is not a parent reference is accepted")
    func dottedNamesAreAccepted() throws {
        let state = Support.state(dependencies: [Support.remote(subpath: "kit..v2")])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: ["kit..v2"])
        #expect(try resolve(fileSystem).map(\.checkoutPath) == [checkout("kit..v2")])
    }

    @Test("a checkout link into a sibling folder with a similar name is refused")
    func siblingWithSimilarNameIsRefused() throws {
        let state = Support.state(dependencies: [Support.remote(subpath: "kit")])
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: Support.sourcePackages + "/checkouts")
        try fileSystem.addDirectory(at: Support.sourcePackages + "/checkouts-evil/kit")
        try fileSystem.addSymlink(
            at: Support.sourcePackages + "/checkouts/kit",
            pointingTo: Support.sourcePackages + "/checkouts-evil/kit")
        try fileSystem.addFile(
            at: Support.sourcePackages + "/workspace-state.json", contents: state)
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        guard case .fileUnreadable(let path, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(path == checkout("kit"))
        #expect(reason.contains("outside"))
    }

    @Test("a checkout link that stays inside the checkouts folder is accepted")
    func linkInsideCheckoutsIsAccepted() throws {
        let state = Support.state(dependencies: [Support.remote(subpath: "kit")])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: ["real"])
        try fileSystem.addSymlink(at: checkout("kit"), pointingTo: checkout("real"))
        #expect(try resolve(fileSystem).map(\.checkoutPath) == [checkout("kit")])
    }

    @Test("a checkout link to the checkouts folder itself is refused")
    func linkToCheckoutsRootIsRefused() throws {
        let state = Support.state(dependencies: [Support.remote(subpath: "kit")])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: [])
        try fileSystem.addSymlink(
            at: checkout("kit"), pointingTo: Support.sourcePackages + "/checkouts")
        #expect(throws: DomainError.self) { try resolve(fileSystem) }
    }

    @Test("a missing checkout folder fails with file not found naming it")
    func missingCheckoutFolder() throws {
        let state = Support.state(dependencies: [Support.remote(subpath: "kit")])
        let fileSystem = try Support.sourcePackagesTree(state: state, checkouts: [])
        let error = #expect(throws: DomainError.self) { try resolve(fileSystem) }
        #expect(error == .fileNotFound(path: checkout("kit")))
    }

    // MARK: Fuzz

    @Test("random bytes and cut files always fail with a domain error and never crash")
    func fuzzNeverCrashes() throws {
        var generator = SeededGenerator()
        let valid = Data(try Support.fixture("real-v7-local.workspace-state.json").utf8)
        for round in 0..<300 {
            let length = Int.random(in: 0..<200, using: &generator)
            let bytes = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
            let cut = valid.prefix(Int.random(in: 0..<(valid.count - 2), using: &generator))
            for input in [bytes, Data(cut)] {
                let fileSystem = try Support.sourcePackagesTree(
                    state: input, checkouts: ["GRDB.swift"])
                do {
                    _ = try resolve(fileSystem)
                    Issue.record(
                        "round \(round) accepted bad input, seed \(SeededGenerator.defaultSeed)")
                } catch {
                    #expect(error is DomainError)
                }
            }
        }
    }

    @Test("flipped bytes in a valid file give a result or a domain error and never crash")
    func fuzzFlippedBytes() throws {
        var generator = SeededGenerator(seed: 42)
        let valid = Data(try Support.fixture("real-v7-remote.workspace-state.json").utf8)
        for _ in 0..<300 {
            var copy = valid
            for _ in 0..<3 {
                copy[Int.random(in: 0..<copy.count, using: &generator)] = UInt8.random(
                    in: 0...255, using: &generator)
            }
            let fileSystem = try Support.sourcePackagesTree(
                state: copy,
                checkouts: [
                    "swift-async-algorithms", "swift-collections", "swift-docc-plugin",
                    "swift-docc-symbolkit",
                ])
            _ = try? resolve(fileSystem)
        }
    }
}
