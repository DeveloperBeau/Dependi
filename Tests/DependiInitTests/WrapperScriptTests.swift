import DependiInit
import Foundation
import Testing

@Suite("Wrapper script")
struct WrapperScriptTests {
    static let version = "1.2.3"
    static let commit = String(repeating: "a", count: 40)
    static let pin = version + "-" + commit

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
        try world.installProjectBinary(contents: Self.pin)
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
        try world.installProjectBinary(contents: Self.pin)
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
        try world.installProjectBinary(contents: Self.pin)
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
        try world.installProjectBinary(contents: Self.pin)
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
        try world.installProjectBinary(contents: Self.pin)
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
        try world.installProjectBinary(contents: "9.9.9-" + Self.commit)
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
        let run = try world.run(environment: world.buildEnvironment(), arguments: ["generate"])
        #expect(run.status == 0)
        #expect(run.stdout == "cached-marker generate\n")
        #expect(world.calls().isEmpty)
    }

    @Test("a VERSION with the right version but another commit is not used")
    func otherCommitIgnoresProjectCopy() throws {
        let world = try world()
        try world.installProjectBinary(
            contents: Self.version + "-" + String(repeating: "b", count: 40))
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
        let run = try world.run(environment: world.buildEnvironment(), arguments: ["generate"])
        #expect(run.status == 0)
        #expect(run.stdout == "cached-marker generate\n")
        #expect(world.calls().isEmpty)
    }

    @Test("a VERSION with only the version, as an old init wrote it, is not used")
    func versionOnlyIgnoresProjectCopy() throws {
        let world = try world()
        try world.installProjectBinary(contents: Self.version)
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.stdout == "cached-marker\n")
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

    // MARK: Cache folder safety

    @Test("the cache folder override is ignored without DEPENDI_TESTING")
    func cacheOverrideNeedsTestingFlag() throws {
        let world = try world()
        let homeCache = world.home.appendingPathComponent("Library/Caches/dependi")
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil, in: homeCache)
        var env = world.buildEnvironment()
        env["DEPENDI_TESTING"] = nil
        let run = try world.run(environment: env)
        #expect(run.stdout == "cached-marker\n")
        #expect(world.cacheEntries().isEmpty)
    }

    @Test("with DEPENDI_TESTING the cache folder override is used")
    func cacheOverrideWorksWhenTesting() throws {
        let world = try world()
        let homeCache = world.home.appendingPathComponent("Library/Caches/dependi")
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil, in: homeCache)
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.stdout == "cached-marker\n")
        #expect(
            !FileManager.default.fileExists(
                atPath: world.cache.appendingPathComponent(
                    "\(Self.version)-\(Self.commit).build-lock"
                ).path))
    }

    @Test("a new cache folder is private to the user")
    func newCacheFolderIsPrivate() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 0, "\(run.stderr)")
        let attributes = try FileManager.default.attributesOfItem(atPath: world.cache.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)
    }

    @Test("a cache folder that other users can write is refused and nothing runs")
    func writableCacheFolderIsRefused() throws {
        for mode in [0o777, 0o775, 0o757, 0o722] {
            let world = try world()
            try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
            try FileManager.default.setAttributes(
                [.posixPermissions: mode], ofItemAtPath: world.cache.path)
            let run = try world.run(environment: world.buildEnvironment())
            #expect(run.status == 1, "mode \(String(mode, radix: 8))")
            #expect(run.stderr.contains("can be written by other users"))
            #expect(run.stdout.isEmpty)
            #expect(world.calls().isEmpty)
        }
    }

    @Test("a cache folder with mode 0755 that the user owns is accepted")
    func ownedReadableCacheFolderIsAccepted() throws {
        let world = try world()
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: world.cache.path)
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.stdout == "cached-marker\n")
    }

    @Test("a cache folder that is a symlink is refused")
    func symlinkCacheFolderIsRefused() throws {
        let world = try world()
        let real = world.root.appendingPathComponent("real-cache")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: world.cache, withDestinationURL: real)
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 1)
        #expect(run.stderr.contains("not a folder that you own"))
        #expect(world.calls().isEmpty)
    }

    @Test(
        "a cache folder that another user owns is refused",
        .enabled(if: geteuid() != 0, "root owns every folder this test could use"))
    func foreignCacheFolderIsRefused() throws {
        let world = try world()
        // /usr is owned by root on every Mac.
        let run = try world.run(
            environment: world.buildEnvironment([
                "DEPENDI_CACHE_ROOT": "/usr", "DEPENDI_LOCK_WAIT_STEPS": "3",
            ]))
        #expect(run.status == 1)
        #expect(run.stderr.contains("not a folder that you own"))
        #expect(world.calls().isEmpty)
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
        #expect(
            calls[0].hasPrefix(
                "git -c core.hooksPath=/dev/null clone --quiet --template= \(world.origin.path) "))
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

    @Test("a second script that starts while the first holds the lock waits and builds nothing")
    func concurrentRunsBuildOnce() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.flag("hold-build")
        defer { try? world.flag("proceed") }
        let first = try world.start(environment: world.buildEnvironment())
        try #require(world.waitForControlFile("building"), "the first build never started")
        let second = try world.start(environment: world.buildEnvironment())
        try #require(world.waitUntilWaitingForLock(second), "the second script never waited")
        try world.flag("proceed")
        let one = first.finish()
        let two = second.finish()
        #expect(one.status == 0)
        #expect(two.status == 0)
        #expect(one.stdout == "built-marker\n")
        #expect(two.stdout == "built-marker\n")
        #expect(world.calls(of: "xcrun").count == 1)
        #expect(world.cacheEntries() == ["\(Self.version)-\(head)"])
    }

    @Test("two scripts that meet a dead owner's lock together build once")
    func concurrentRunsOnDeadLockBuildOnce() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.plantLock(
            version: Self.version, commit: head,
            owner: String(try world.deadProcessIdentifier()))
        try world.flag("hold-build")
        defer { try? world.flag("proceed") }
        let first = try world.start(environment: world.buildEnvironment())
        try #require(world.waitForControlFile("building"), "the first build never started")
        let second = try world.start(environment: world.buildEnvironment())
        try #require(world.waitUntilWaitingForLock(second), "the second script never waited")
        try world.flag("proceed")
        let one = first.finish()
        let two = second.finish()
        #expect(one.status == 0)
        #expect(two.status == 0)
        #expect(world.calls(of: "xcrun").count == 1)
        #expect(world.cacheEntries() == ["\(Self.version)-\(head)"])
    }

    @Test("a lock whose owner process is gone is reclaimed at once")
    func deadOwnerLockIsReclaimed() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.plantLock(
            version: Self.version, commit: head,
            owner: String(try world.deadProcessIdentifier()))
        // Three waits are less than a second. A script that waits for the lock fails.
        let run = try world.run(
            environment: world.buildEnvironment(["DEPENDI_LOCK_WAIT_STEPS": "3"]))
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout == "built-marker\n")
        #expect(world.lockOwner(version: Self.version, commit: head) == nil)
    }

    @Test(
        "a cache folder that cannot take a lock fails at once and does not wait",
        .enabled(if: geteuid() != 0, "a root user can write to any folder"))
    func unwritableCacheFolderFailsAtOnce() throws {
        let world = try world()
        try FileManager.default.createDirectory(at: world.cache, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: world.cache.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: world.cache.path)
        }
        let run = try world.run(
            environment: world.buildEnvironment(["DEPENDI_LOCK_WAIT_STEPS": "5"]))
        #expect(run.status == 1)
        #expect(run.stderr.contains("could not create the build lock"))
        #expect(world.calls().isEmpty)
    }

    @Test("a lock whose owner process is running is respected and left in place")
    func liveOwnerLockIsRespected() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        let owner = String(getpid())
        try world.plantLock(version: Self.version, commit: head, owner: owner)
        let run = try world.run(
            environment: world.buildEnvironment(["DEPENDI_LOCK_WAIT_STEPS": "5"]))
        #expect(run.status == 1)
        #expect(run.stderr.contains("waited for another build"))
        #expect(world.calls().isEmpty)
        #expect(world.lockOwner(version: Self.version, commit: head) == owner)
    }

    @Test("a lock whose owner is running but that is older than 30 minutes is reclaimed")
    func oldLockWithLiveOwnerIsReclaimed() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.plantLock(version: Self.version, commit: head, owner: String(getpid()))
        try world.ageLock(version: Self.version, commit: head, seconds: 40 * 60)
        let run = try world.run(
            environment: world.buildEnvironment(["DEPENDI_LOCK_WAIT_STEPS": "3"]))
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout == "built-marker\n")
    }

    @Test("a lock that is 20 minutes old with a running owner is still respected")
    func recentLockWithLiveOwnerIsRespected() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.plantLock(version: Self.version, commit: head, owner: String(getpid()))
        try world.ageLock(version: Self.version, commit: head, seconds: 20 * 60)
        let run = try world.run(
            environment: world.buildEnvironment(["DEPENDI_LOCK_WAIT_STEPS": "3"]))
        #expect(run.status == 1)
        #expect(world.calls().isEmpty)
    }

    @Test("a lock whose target is not a process id is reclaimed")
    func malformedLockOwnerIsStale() throws {
        for owner in ["abc", "12x", "-1", "../etc", "1 2"] {
            let world = try world()
            let head = try world.makeOrigin()
            try world.writeConfig(["version": Self.version, "commit": head])
            try world.plantLock(version: Self.version, commit: head, owner: owner)
            let run = try world.run(
                environment: world.buildEnvironment(["DEPENDI_LOCK_WAIT_STEPS": "3"]))
            #expect(run.status == 0, "owner \(owner): \(run.stderr)")
            #expect(run.stdout == "built-marker\n", "owner \(owner)")
        }
    }

    @Test("a build that finds another owner on its lock does not remove that lock")
    func releaseKeepsForeignLock() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        try world.flag("hold-build")
        defer { try? world.flag("proceed") }
        let running = try world.start(environment: world.buildEnvironment())
        try #require(world.waitForControlFile("building"), "the build never started")
        let other = String(getpid())
        try world.plantLock(version: Self.version, commit: head, owner: other)
        try world.flag("proceed")
        let run = running.finish()
        #expect(run.status == 0, "\(run.stderr)")
        #expect(world.lockOwner(version: Self.version, commit: head) == other)
    }

    @Test("a finished build removes its own lock")
    func releaseRemovesOwnLock() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 0)
        #expect(world.lockOwner(version: Self.version, commit: head) == nil)
        #expect(world.cacheEntries() == ["\(Self.version)-\(head)"])
    }

    // MARK: Environment and safety

    @Test("the build gets no inherited SDKROOT and keeps HOME and DEVELOPER_DIR")
    func buildEnvironmentIsClean() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        let env = world.buildEnvironment([
            "SDKROOT": "/some/sdk", "OTHER_LDFLAGS": "-x",
        ])
        let run = try world.run(environment: env)
        #expect(run.status == 0, "\(run.stderr)")
        let logged = try String(contentsOf: world.envLog, encoding: .utf8)
        #expect(!logged.contains("SDKROOT"))
        #expect(!logged.contains("OTHER_LDFLAGS"))
        #expect(!logged.contains("DEPENDI_"))
        #expect(logged.contains("DEVELOPER_DIR=\(world.developerDir.path)\n"))
        #expect(logged.contains("HOME=\(world.root.path)/home\n"))
        #expect(logged.contains("PATH=/usr/bin:/bin\n"))
    }

    @Test("git runs with a clean environment, no user config and no hooks")
    func gitEnvironmentIsClean() throws {
        let world = try world()
        let head = try world.makeOrigin()
        try world.writeConfig(["version": Self.version, "commit": head])
        // A user config that sends the origin somewhere that does not exist.
        try """
        [url "file:///nonexistent/"]
            insteadOf = \(world.origin.path)
        """.write(
            to: world.home.appendingPathComponent(".gitconfig"), atomically: true, encoding: .utf8)
        let env = world.buildEnvironment([
            "GIT_DIR": "/nonexistent/other.git", "GIT_WORK_TREE": "/nonexistent/tree",
            "GIT_INDEX_FILE": "/nonexistent/index", "GIT_TEMPLATE_DIR": "/nonexistent/template",
        ])
        let run = try world.run(environment: env)
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout == "built-marker\n")
        let logged = try String(contentsOf: world.gitEnvLog, encoding: .utf8)
        for name in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_TEMPLATE_DIR", "DEPENDI_"] {
            #expect(!logged.contains(name + "="), "\(name) reached git")
            #expect(!logged.contains(name + "\n"), "\(name) reached git")
        }
        #expect(logged.contains("PATH=/usr/bin:/bin\n"))
        #expect(logged.contains("GIT_CONFIG_GLOBAL=/dev/null\n"))
        #expect(logged.contains("GIT_CONFIG_NOSYSTEM=1\n"))
        #expect(!logged.contains("HOME=\(world.home.path)\n"))
        for call in world.calls(of: "git") {
            #expect(call.hasPrefix("git -c core.hooksPath=/dev/null "), "\(call)")
        }
    }

    @Test("a tool placed first on the caller's PATH is not used")
    func callerPathIsIgnored() throws {
        let world = try world()
        try world.seedCache(version: Self.version, commit: Self.commit, sha: nil)
        let decoy = world.stubs.appendingPathComponent("shasum")
        try "#!/bin/sh\necho decoy >> '\(world.callLog.path)'\necho 0000 -\n".write(
            to: decoy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: decoy.path)
        let run = try world.run(environment: world.buildEnvironment())
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout == "cached-marker\n")
        #expect(world.calls().isEmpty)
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
            try world.installProjectBinary(contents: value + "-" + Self.commit)
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
            try world.installProjectBinary(contents: Self.pin)
            let run = try world.run(environment: world.buildEnvironment())
            #expect(run.status == 1, "commit \(value.debugDescription)")
            #expect(run.stderr.hasPrefix("error:"), "commit \(value.debugDescription)")
            #expect(world.calls().isEmpty, "commit \(value.debugDescription)")
            #expect(!FileManager.default.fileExists(atPath: world.cache.path))
        }
    }
}
