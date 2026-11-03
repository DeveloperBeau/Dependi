import DependiInit
import Foundation
import Testing

@Suite("Wrapper script", .timeLimit(.minutes(5)))
struct WrapperScriptTests {
    static let version = "1.2.3"
    static let commit = String(repeating: "a", count: 40)

    private func world(config: [String: Any]? = nil) throws -> WrapperWorld {
        let world = try WrapperWorld()
        try world.writeConfig(config ?? ["version": Self.version, "commit": Self.commit])
        return world
    }

    private func inXcode(_ world: WrapperWorld, action: String, configuration: String) -> [String:
        String]
    {
        world.baseEnvironment([
            "ACTION": action, "CONFIGURATION": configuration, "TARGET_BUILD_DIR": "/x",
        ])
    }

    // MARK: Pre-gate

    @Test("a Debug build is skipped with one line and no git or xcrun call")
    func debugBuildSkipsBeforeAnyCall() throws {
        let world = try world()
        let run = try world.run(
            environment: inXcode(world, action: "build", configuration: "Debug"))
        #expect(run.status == 0)
        #expect(run.stdout == "Dependi: skipped. configuration Debug is not in the gate list\n")
        #expect(world.calls().isEmpty)
        #expect(world.cacheEntries().isEmpty)
    }

    @Test("a missing config file skips Debug and still runs Release")
    func missingConfigDefaultsToRelease() throws {
        let world = try WrapperWorld()
        try world.installProjectBinary(version: Self.version)
        let skipped = try world.run(
            environment: inXcode(world, action: "build", configuration: "Debug"))
        #expect(skipped.status == 0)
        #expect(skipped.stdout.hasPrefix("Dependi: skipped."))
        #expect(world.calls().isEmpty)
        // Release passes the gate, then the missing config fails validation.
        let release = try world.run(
            environment: inXcode(world, action: "build", configuration: "Release"))
        #expect(release.status == 1)
        #expect(release.stderr.hasPrefix("error:"))
    }

    @Test("a config without a gate list defaults to Release and Release is not skipped")
    func missingGateListDefaultsToRelease() throws {
        let world = try world()
        try world.installProjectBinary(version: Self.version)
        let run = try world.run(
            environment: inXcode(world, action: "build", configuration: "Release"),
            arguments: ["generate"])
        #expect(run.status == 0)
        #expect(run.stdout == "installed-marker generate\n")
    }

    @Test("gate names are matched as plain strings, not as patterns")
    func gateNamesAreNotPatterns() throws {
        let world = try world(config: [
            "version": Self.version, "commit": Self.commit,
            "gateConfigurations": ["Rel.*", "A/B", "[Z]"],
        ])
        try world.installProjectBinary(version: Self.version)
        for name in ["Release", "Rel", "AxB", "Z", "*"] {
            let run = try world.run(
                environment: inXcode(world, action: "build", configuration: name))
            #expect(run.stdout.hasPrefix("Dependi: skipped."), "\(name) must skip")
        }
        for name in ["Rel.*", "A/B", "[Z]"] {
            let run = try world.run(
                environment: inXcode(world, action: "build", configuration: name))
            #expect(run.stdout.hasPrefix("installed-marker"), "\(name) must run")
        }
    }

    @Test("an empty gate list runs only for archive")
    func emptyGateListMeansArchiveOnly() throws {
        let world = try world(config: [
            "version": Self.version, "commit": Self.commit, "gateConfigurations": [String](),
        ])
        try world.installProjectBinary(version: Self.version)
        let build = try world.run(
            environment: inXcode(world, action: "build", configuration: "Release"))
        #expect(build.stdout.hasPrefix("Dependi: skipped."))
        let archive = try world.run(
            environment: inXcode(world, action: "install", configuration: "Debug"))
        #expect(archive.stdout.hasPrefix("installed-marker"))
    }

    @Test("a run outside Xcode with no ACTION skips with a line")
    func noActionOutsideXcodeSkips() throws {
        let world = try world()
        let run = try world.run(environment: world.baseEnvironment())
        #expect(run.status == 0)
        #expect(run.stdout.hasPrefix("Dependi: skipped."))
        #expect(world.calls().isEmpty)
    }

    // MARK: Project copy and cache

    @Test("an archive with a matching VERSION runs the project binary with the arguments")
    func matchingVersionRunsProjectBinary() throws {
        let world = try world()
        try world.installProjectBinary(version: Self.version)
        let run = try world.run(
            environment: world.baseEnvironment(["ACTION": "install", "CONFIGURATION": "Debug"]),
            arguments: ["generate", "--flag", "two words"])
        #expect(run.status == 0)
        #expect(run.stdout == "installed-marker generate --flag two words\n")
        #expect(world.calls() == ["dependi generate --flag two words"])
    }

    @Test("a VERSION mismatch uses the verified cache and builds nothing")
    func versionMismatchUsesCache() throws {
        let world = try world()
        try world.installProjectBinary(version: "9.9.9")
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
        let run = try world.run(environment: world.buildEnvironment(), arguments: ["generate"])
        #expect(run.status == 0)
        #expect(run.stdout == "cached-marker generate\n")
        #expect(world.calls().isEmpty)
    }

    @Test("a cache folder without a sha file is rebuilt and not run")
    func cacheWithoutShaIsRebuilt() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.seedCache(version: Self.version, commit: head, sha: nil, writeSha: false)
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 0)
        #expect(run.stdout == "built-marker\n")
        #expect(world.calls(of: "xcrun").count == 1)
    }

    @Test("a cache binary with a wrong sha is rebuilt and not run")
    func cacheWithWrongShaIsRebuilt() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.seedCache(
            version: Self.version, commit: head, sha: String(repeating: "0", count: 64))
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 0)
        #expect(run.stdout == "built-marker\n")
        #expect(world.calls(of: "xcrun").count == 1)
    }

    // MARK: Build

    @Test("a missing binary clones, builds and runs the cached binary")
    func missingBinaryBuildsAndRuns() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        let run = try world.run(environment: world.buildEnvironment(), arguments: ["generate"])
        #expect(run.status == 0)
        #expect(run.stdout == "built-marker generate\n")
        let calls = world.calls()
        #expect(calls.count == 4)
        #expect(calls[0].hasPrefix("git clone --quiet \(world.origin.path) "))
        #expect(calls[1].contains("checkout --quiet \(head)"))
        #expect(calls[2].contains("rev-parse HEAD"))
        #expect(calls[3].hasPrefix("xcrun swift build -c release --package-path "))
        #expect(calls[3].contains("/src --scratch-path "))
        #expect(calls[3].hasSuffix("/build --product dependi"))
        #expect(world.cacheEntries() == ["\(Self.version)-\(head)"])
        let bin = world.cache.appendingPathComponent("\(Self.version)-\(head)/bin").path
        #expect(FileManager.default.fileExists(atPath: bin + "/dependi"))
        #expect(FileManager.default.fileExists(atPath: bin + "/dependi.sha256"))
    }

    @Test("the second run uses the cache and records no new git or xcrun call")
    func secondRunUsesCache() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        _ = try world.run(environment: world.buildEnvironment())
        let before = world.calls()
        let run = try world.run(environment: world.buildEnvironment(), arguments: ["again"])
        #expect(run.stdout == "built-marker again\n")
        #expect(world.calls() == before)
    }

    @Test("a pinned commit that is not in the origin fails and leaves no cache folder")
    func missingCommitFailsClean() throws {
        let world = try world()
        try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": WrapperWorld.missingCommit])
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status != 0)
        #expect(run.stderr.contains("checkout"))
        #expect(world.calls(of: "xcrun").isEmpty)
        #expect(world.cacheEntries().isEmpty)
    }

    @Test("a checkout whose HEAD is not the pinned commit fails and leaves no cache folder")
    func movedCommitFailsClean() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.flag("lie-head")
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 1)
        #expect(run.stderr.contains("not the pinned commit"))
        #expect(world.calls(of: "xcrun").isEmpty)
        #expect(world.cacheEntries().isEmpty)
    }

    @Test("a failed build exits non-zero, shows the log tail and leaves nothing behind")
    func failedBuildLeavesNothing() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.flag("fail-build")
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status != 0)
        #expect(run.stderr.contains("compile error: boom"))
        #expect(world.cacheEntries().isEmpty)
    }

    @Test("a failed clone exits non-zero and leaves nothing behind")
    func failedCloneLeavesNothing() throws {
        let world = try world()
        try world.flag("fail-clone")
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status != 0)
        #expect(run.stderr.contains("clone refused"))
        #expect(world.cacheEntries().isEmpty)
    }

    @Test("two scripts started together build once and both succeed")
    func concurrentRunsBuildOnce() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.flag("slow-build")
        let first = try world.start(environment: world.buildEnvironment())
        let second = try world.start(environment: world.buildEnvironment())
        let one = first.finish()
        let two = second.finish()
        #expect(one.status == 0)
        #expect(two.status == 0)
        #expect(one.stdout == "built-marker\n")
        #expect(two.stdout == "built-marker\n")
        #expect(world.calls(of: "xcrun").count == 1)
        #expect(world.cacheEntries() == ["\(Self.version)-\(head)"])
    }

    @Test("a stale lock older than ten minutes is removed and the build goes on")
    func staleLockIsRemoved() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        let lock = world.cache.appendingPathComponent("\(Self.version)-\(head).lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-700)], ofItemAtPath: lock.path)
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 0)
        #expect(run.stdout == "built-marker\n")
        #expect(world.cacheEntries() == ["\(Self.version)-\(head)"])
    }

    // MARK: Environment and safety

    @Test("the build gets no inherited SDKROOT and keeps HOME and DEVELOPER_DIR")
    func buildEnvironmentIsClean() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        let env = world.buildEnvironment([
            "SDKROOT": "/some/sdk", "DEVELOPER_DIR": "/some/dev dir", "OTHER_LDFLAGS": "-x",
        ])
        let run = try world.run(environment: env)
        #expect(run.status == 0, "\(run.stderr)")
        let logged = try String(contentsOf: world.envLog, encoding: .utf8)
        #expect(!logged.contains("SDKROOT"))
        #expect(!logged.contains("OTHER_LDFLAGS"))
        #expect(!logged.contains("DEPENDI_"))
        #expect(logged.contains("DEVELOPER_DIR=/some/dev dir\n"))
        #expect(logged.contains("HOME=\(world.root.path)/home\n"))
        #expect(logged.contains("PATH=/usr/bin:/bin\n"))
    }

    @Test("a custom repo URL without DEPENDI_TESTING is ignored")
    func repoOverrideNeedsTestingFlag() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.flag("fail-clone")
        var env = world.buildEnvironment()
        env["DEPENDI_TESTING"] = nil
        let run = try world.run(environment: env)
        #expect(run.status != 0)
        let clone = try #require(world.calls(of: "git").first)
        #expect(clone.contains("https://github.com/Developer" + "Beau/Dependi.git"))
        #expect(!clone.contains(world.origin.path))
        #expect(world.calls(of: "xcrun").isEmpty)
    }

    @Test("the script text has no eval and no shell -c call and is valid sh")
    func scriptTextIsPlain() throws {
        let text = WrapperScript.text
        #expect(text.hasPrefix("#!/bin/sh\n"))
        #expect(text.contains("\nset -eu\n"))
        for word in text.split(whereSeparator: { " \t\n;|&(){}\"'".contains($0) }) {
            #expect(word != "eval")
        }
        for shell in ["sh", "bash", "zsh", "dash"] {
            #expect(!text.contains("\(shell) -c"))
        }
        let world = try world()
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        check.arguments = ["sh", "-n", world.script.path]
        check.environment = ["PATH": "/usr/bin:/bin"]
        try check.run()
        check.waitUntilExit()
        #expect(check.terminationStatus == 0)
    }

    // MARK: Validation

    @Test("bad versions exit 1 before any call or file system change")
    func badVersionsAreRejected() throws {
        let bad = [
            "../../x", "1.0;rm -rf x", "1.0.0 ", "$(id)", "", "1.2", "1.0.0\n", "`id`", "1.2.3.4",
            "v1.2.3",
        ]
        for value in bad {
            let world = try world(config: ["version": value, "commit": Self.commit])
            try world.installProjectBinary(version: value)
            let run = try world.run(environment: world.buildEnvironment())
            #expect(run.status == 1, "version \(value.debugDescription)")
            #expect(run.stderr.hasPrefix("error:"), "version \(value.debugDescription)")
            #expect(world.calls().isEmpty, "version \(value.debugDescription)")
            #expect(!FileManager.default.fileExists(atPath: world.cache.path))
        }
    }

    @Test("bad commits exit 1 before any call or file system change")
    func badCommitsAreRejected() throws {
        let good = String(repeating: "a", count: 40)
        let bad = [
            "../../x", good + ";rm", good + " ", "$(id)", "", "abc", good + "\n", "`id`",
            String(repeating: "A", count: 40), String(repeating: "a", count: 41),
            String(repeating: "g", count: 40),
        ]
        for value in bad {
            let world = try world(config: ["version": Self.version, "commit": value])
            try world.installProjectBinary(version: Self.version)
            let run = try world.run(environment: world.buildEnvironment())
            #expect(run.status == 1, "commit \(value.debugDescription)")
            #expect(run.stderr.hasPrefix("error:"), "commit \(value.debugDescription)")
            #expect(world.calls().isEmpty, "commit \(value.debugDescription)")
            #expect(!FileManager.default.fileExists(atPath: world.cache.path))
        }
    }
}
