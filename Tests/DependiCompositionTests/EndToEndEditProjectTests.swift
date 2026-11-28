import Foundation
import TestHelpers
import Testing

@Suite("End to end with the edit-project flag", .timeLimit(.minutes(5)))
struct EndToEndEditProjectTests {
    private static var fixtureText: String {
        get throws {
            try String(
                contentsOf: RepositoryRoot.url.appendingPathComponent(
                    "Tests/DependiProjectFileTests/Fixtures/old-format-mew.pbxproj"),
                encoding: .utf8)
        }
    }

    private func mewWorld(projectFile: String? = nil) throws -> EndToEndWorld {
        let world = try EndToEndWorld(
            configuration: nil, projectFile: try projectFile ?? Self.fixtureText)
        // Init copies the running program, so a stand-in file must exist.
        try Data("BINARY".utf8).write(to: URL(fileURLWithPath: world.root.path + "/dependi-bin"))
        return world
    }

    private func projectBytes(_ world: EndToEndWorld) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: world.project + "/App.xcodeproj/project.pbxproj"))
    }

    /// Every file under the project folder with its bytes, so a test can see a change or a new file.
    private func snapshot(_ world: EndToEndWorld) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = try requireValue(
            FileManager.default.enumerator(atPath: world.project))
        for case let name as String in enumerator {
            var isFolder: ObjCBool = false
            let path = world.project + "/" + name
            FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            result[name] =
                isFolder.boolValue
                ? Data("folder".utf8) : try Data(contentsOf: URL(fileURLWithPath: path))
        }
        return result
    }

    private func arguments(_ world: EndToEndWorld, edits: Bool) -> [String] {
        ["init", "--project", world.project] + (edits ? ["--edit-project"] : [])
    }

    private func backupPath(_ world: EndToEndWorld) -> String {
        world.project + "/.dependi/project.pbxproj.bak"
    }

    @Test("plain init leaves the project file byte identical and writes no backup")
    func plainInitLeavesTheProjectFileByteIdentical() throws {
        let world = try mewWorld()
        let before = try projectBytes(world)
        let result = try world.run(arguments(world, edits: false))
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try projectBytes(world) == before)
        #expect(!FileManager.default.fileExists(atPath: backupPath(world)))
        #expect(result.output.contains("Add a Run Script build phase to the app target"))
        #expect(result.output.contains("--edit-project"))
    }

    @Test("the flag sets up the target, backs up the original and names every change")
    func editProjectSetsUpTheTargetAndBacksUpTheOriginal() throws {
        let world = try mewWorld()
        let before = try projectBytes(world)
        let result = try world.run(arguments(world, edits: true))
        #expect(result.code == 0, "errors: \(result.errors)")

        let lines = String(decoding: try projectBytes(world), as: UTF8.self)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let expected = [
            "76C979CC1790CDFA3037B5DC /* Settings.bundle in Resources */ = {isa = PBXBuildFile; fileRef = 3F3B65923D016048D4FAF971 /* Settings.bundle */; };",
            "2753DE8B26A7EEA90771BF6B /* Dependi */ = {",
            "isa = PBXShellScriptBuildPhase;",
            "name = Dependi;",
            "shellScript = \"\\\"${SRCROOT}/.dependi/run.sh\\\" generate\\n\";",
            "\"$(SRCROOT)/.dependi/inputs.xcfilelist\",",
            "\"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist\",",
        ]
        for line in expected { #expect(lines.contains(line), "missing: \(line)") }
        #expect(lines.filter { $0 == "ENABLE_USER_SCRIPT_SANDBOXING = NO;" }.count == 2)

        #expect(try Data(contentsOf: URL(fileURLWithPath: backupPath(world))) == before)
        for change in [
            "added Settings.bundle to Copy Bundle Resources of MewTestsApp.",
            "added the Dependi Run Script phase after Copy Bundle Resources of MewTestsApp.",
            "set ENABLE_USER_SCRIPT_SANDBOXING = NO in Debug of MewTestsApp.",
            "set ENABLE_USER_SCRIPT_SANDBOXING = NO in Release of MewTestsApp.",
            "backup of the original project file is at ",
            "/.dependi/project.pbxproj.bak.",
        ] {
            #expect(result.output.contains(change), "missing: \(change)")
        }
        #expect(!result.output.contains("Add a Run Script build phase"))
    }

    @Test("a second run with the flag changes nothing and keeps the first backup")
    func rerunWithEditProjectChangesNothing() throws {
        let world = try mewWorld()
        let original = try projectBytes(world)
        _ = try world.run(arguments(world, edits: true))
        let edited = try projectBytes(world)
        #expect(edited != original)

        let second = try world.run(arguments(world, edits: true))
        #expect(second.code == 0, "errors: \(second.errors)")
        #expect(try projectBytes(world) == edited)
        #expect(try Data(contentsOf: URL(fileURLWithPath: backupPath(world))) == original)
        #expect(second.output.contains("Dependi: the Xcode project is already set up."))
    }

    @Test("a damaged project file with the flag fails by name and changes nothing")
    func malformedProjectWithEditProjectChangesNothing() throws {
        let text = try Self.fixtureText
        let world = try mewWorld(projectFile: String(text.prefix(text.count / 2)))
        let before = try snapshot(world)
        let result = try world.run(arguments(world, edits: true))
        #expect(result.code == 1)
        #expect(result.errors.contains("project.pbxproj"), "errors: \(result.errors)")
        #expect(try snapshot(world) == before)
    }
}
