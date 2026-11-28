import DependiDomain
import DependiProjectFile
import DependiTestSupport
import Foundation

/// An in-memory project with one fixture, an editor and a recording writer.
struct EditWorld {
    static let projectFolder = "/work/App/App.xcodeproj"
    static let projectFile = projectFolder + "/project.pbxproj"
    static let backup = "/work/App/.dependi/project.pbxproj.bak"
    static let appFolder = "/work/App"

    let files = InMemoryFileSystem()
    let writer: RecordingWriter
    let original: Data

    /// Places the fixture, or the given bytes in its place, and creates the backup folder.
    init(
        _ fixture: String, bytes: Data? = nil, failingPrefix: String? = nil,
        alteringPrefix: String? = nil
    ) throws {
        original = bytes ?? FixtureWorld.fixture(fixture)
        try files.addDirectory(at: Self.projectFolder)
        try files.addDirectory(at: Self.appFolder + "/.dependi")
        try files.addFile(at: Self.projectFile, contents: original)
        writer = RecordingWriter(
            files, failingPrefix: failingPrefix, alteringPrefix: alteringPrefix)
    }

    var editor: ProjectFileEditor { ProjectFileEditor(files: files, writer: writer) }

    /// The project file as it is now.
    func currentBytes() throws -> Data {
        try files.readRegularFile(at: Self.projectFile, upToBytes: Int.max)
    }

    func currentText() throws -> String { String(decoding: try currentBytes(), as: UTF8.self) }

    /// Runs the editor for a target and a bundle path relative to the folder of the project.
    @discardableResult
    func configure(
        target: String, bundle: String, isDryRun: Bool = false
    ) throws(DomainError) -> [String] {
        try editor.configureBuild(
            projectFilePath: Self.projectFolder, targetName: target,
            settingsBundlePath: Self.appFolder + "/" + bundle, backupPath: Self.backup,
            isDryRun: isDryRun)
    }
}

/// One fixture with the target and the bundle path that the success tests use for it.
struct EditCase: Sendable {
    let fixture: String
    let target: String
    let bundle: String

    static let all: [EditCase] = [
        EditCase(fixture: "old-format-mew", target: "MewTestsApp", bundle: "Settings.bundle"),
        EditCase(fixture: "synchronized-fila", target: "Fila", bundle: "Fila/Settings.bundle"),
        EditCase(
            fixture: "folder-reference-twittertexteditor", target: "Example",
            bundle: "Example/Resources/Settings.bundle"),
        EditCase(
            fixture: "settings-bundle-overland", target: "Overland",
            bundle: "GPSLogger/Settings.bundle"),
        EditCase(
            fixture: "multiple-targets-keyboardkit", target: "KeyboardKitDemo",
            bundle: "KeyboardKitDemo/Settings.bundle"),
    ]
}
