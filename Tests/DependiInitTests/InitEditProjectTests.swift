import DependiDomain
import DependiInit
import DependiTestSupport
import Foundation
import Testing

@Suite("Init with the edit-project flag", .timeLimit(.minutes(1)))
struct InitEditProjectTests {
    private func call(dry: Bool, target: String = "App", bundle: String = "/proj/Settings.bundle")
        -> RecordingProjectBuild.Call
    {
        RecordingProjectBuild.Call(
            projectFilePath: "/proj/App.xcodeproj", targetName: target,
            settingsBundlePath: bundle, backupPath: "/proj/.dependi/project.pbxproj.bak",
            isDryRun: dry)
    }

    @Test("plain init never calls the project editor and prints the manual steps and the hint")
    func plainInitSkipsTheEditor() throws {
        let world = try InitWorld()
        #expect(try world.run() == .installed)
        #expect(world.projectBuild.calls.isEmpty)
        #expect(world.console.lines.contains("    \"${SRCROOT}/.dependi/run.sh\" generate"))
        #expect(world.console.lines.contains { $0.contains("--edit-project") })
    }

    @Test("the old overload leaves the project file alone")
    func forwardingOverload() throws {
        let world = try InitWorld()
        _ = try world.makeFeature().run(projectPath: "/proj", isDryRun: false)
        #expect(world.projectBuild.calls.isEmpty)
    }

    @Test("the flag calls the editor twice, a dry run first and then the real edit")
    func editsInTwoSteps() throws {
        let world = try InitWorld()
        world.projectBuildResult = .success(["Dependi: added the Run Script phase."])
        #expect(try world.run(editsProject: true) == .installed)
        #expect(world.projectBuild.calls == [call(dry: true), call(dry: false)])
        #expect(world.console.lines.contains("Dependi: added the Run Script phase."))
        #expect(world.console.lines.contains { $0.contains("close and reopen") })
        #expect(!world.console.lines.contains("    \"${SRCROOT}/.dependi/run.sh\" generate"))
        #expect(!world.console.lines.contains { $0.contains("as a resource in Xcode") })
        #expect(!world.console.lines.contains { $0.contains("already set up") })
    }

    @Test("the bundle that init found is the bundle that the editor gets")
    func existingBundlePath() throws {
        let world = try InitWorld()
        try world.files.addDirectory(at: "/proj/App/Settings.bundle")
        _ = try world.run(editsProject: true)
        let path = "/proj/App/Settings.bundle"
        #expect(
            world.projectBuild.calls == [
                call(dry: true, bundle: path), call(dry: false, bundle: path),
            ])
    }

    @Test("the target from the choice is the target that the editor gets")
    func chosenTarget() throws {
        let world = try InitWorld()
        world.targets = ["Alpha", "Beta"]
        world.answers = [.choice(1)]
        _ = try world.run(editsProject: true)
        #expect(
            world.projectBuild.calls == [
                call(dry: true, target: "Beta"), call(dry: false, target: "Beta"),
            ])
        #expect(world.linked.targetsAsked == ["Beta"])
    }

    @Test("a refusal from the dry run stops init before any file is written")
    func refusalStopsInit() throws {
        let world = try InitWorld()
        world.projectBuildResult = .failure(
            .fileUnreadable(
                path: "/proj/App.xcodeproj/project.pbxproj", reason: "no Resources phase"))
        #expect(throws: DomainError.self) { try world.run(editsProject: true) }
        #expect(world.projectBuild.calls == [call(dry: true)])
        for path in [
            "/proj/.dependi.json", "/proj/Settings.bundle", "/proj/.dependi", "/proj/.gitignore",
        ] {
            #expect(!world.files.exists(at: path), "\(path) exists")
        }
    }

    @Test("a dry run with the flag reports the editor lines and writes nothing")
    func dryRunWithFlag() throws {
        let world = try InitWorld()
        world.projectBuildResult = .success(["Dependi: would add the phase."])
        #expect(try world.run(dry: true, editsProject: true) == .reported)
        #expect(world.projectBuild.calls == [call(dry: true)])
        #expect(world.console.lines.contains { $0.contains("Dependi: would add the phase.") })
        for path in [
            "/proj/.dependi.json", "/proj/Settings.bundle", "/proj/.dependi", "/proj/.gitignore",
        ] {
            #expect(!world.files.exists(at: path), "\(path) exists")
        }
    }

    @Test("a dry run without the flag does not call the editor")
    func dryRunWithoutFlag() throws {
        let world = try InitWorld()
        _ = try world.run(dry: true)
        #expect(world.projectBuild.calls.isEmpty)
        #expect(!world.console.lines.contains { $0.contains("Edit the Xcode project") })
    }

    @Test("when the editor changes nothing, init says the project is already set up")
    func alreadySetUp() throws {
        let world = try InitWorld()
        world.projectBuildResult = .success([])
        #expect(try world.run(editsProject: true) == .installed)
        #expect(world.console.lines.contains("Dependi: the Xcode project is already set up."))
    }
}
