import DependiDomain
import Foundation
import Testing

@Suite("Project file editor layouts", .timeLimit(.minutes(1)))
struct BuildEditLayoutTests {
    private func world(settings: String?) throws -> EditWorld {
        let text = MiniProject.text(settings: settings, resourceFiles: "")
        return try EditWorld("x", bytes: Data(text.utf8))
    }

    @Test("a project with no later section gets the new section at the end")
    func sectionAtTheEnd() throws {
        let world = try world(settings: nil)
        let lines = try world.configure(target: "App", bundle: "Settings.bundle")
        #expect(lines.count == 4)
        let text = try world.currentText()
        #expect(
            text.contains(
                "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXShellScriptBuildPhase section */\n"
            ))
        #expect(
            text.hasSuffix(
                "/* End PBXShellScriptBuildPhase section */\n\t};\n\trootObject = F0 /* Project object */;\n}\n"
            ))
    }

    @Test("an empty list gets its first item one tab deeper than the closing bracket")
    func emptyList() throws {
        let world = try world(settings: nil)
        try world.configure(target: "App", bundle: "Settings.bundle")
        let text = try world.currentText()
        let pattern = try Regex(
            #"files = \(\n\t\t\t\t[0-9A-F]{24} /\* Settings\.bundle in Resources \*/,\n\t\t\t\);"#)
        #expect(text.firstMatch(of: pattern) != nil)
    }

    @Test("an empty build settings dictionary on several lines gets the setting")
    func emptySettings() throws {
        let world = try world(settings: "{\n\t\t\t}")
        let lines = try world.configure(target: "App", bundle: "Settings.bundle")
        #expect(lines.contains("Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Debug of App."))
        #expect(
            try world.currentText().contains(
                "buildSettings = {\n\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n\t\t\t};"))
    }

    @Test("build settings on one line are refused and nothing is written")
    func oneLineSettings() throws {
        let world = try world(settings: "{}")
        do {
            try world.configure(target: "App", bundle: "Settings.bundle")
            Issue.record("expected a refusal")
        } catch {
            #expect("\(error)".contains("laid out in lines"), "\(error)")
        }
        #expect(world.writer.records.isEmpty)
    }

    @Test("a backup that does not match the original stops the edit before the project is replaced")
    func backupMismatch() throws {
        let world = try EditWorld("old-format-mew", alteringPrefix: "write \(EditWorld.backup)")
        #expect(throws: DomainError.self) {
            try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        }
        #expect(world.writer.records == ["write \(EditWorld.backup)"])
        #expect(try world.currentBytes() == world.original)
    }

    @Test("the path of the project file itself works as well as the path of its folder")
    func projectFilePathIsAccepted() throws {
        let world = try EditWorld("old-format-mew")
        let lines = try world.editor.configureBuild(
            projectFilePath: EditWorld.projectFile, targetName: "MewTestsApp",
            settingsBundlePath: "/work/App/Settings.bundle", backupPath: EditWorld.backup,
            isDryRun: false)
        #expect(lines.count == 6)
    }
}
