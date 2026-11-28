import DependiDomain
import Foundation

/// Edits a `project.pbxproj` as text so that an app target runs the Dependi build step.
public struct ProjectFileEditor: Sendable {
    private let files: any FileReading
    private let writer: any FileWriting
    private let adjustPlan: @Sendable (BuildSetupPlan) -> BuildSetupPlan

    /// Creates an editor that reads through `files` and writes through `writer`.
    public init(files: any FileReading, writer: any FileWriting) {
        self.init(files: files, writer: writer, adjustPlan: { $0 })
    }

    /// Lets a test change the plan before it is checked.
    init(
        files: any FileReading, writer: any FileWriting,
        adjustPlan: @escaping @Sendable (BuildSetupPlan) -> BuildSetupPlan
    ) {
        self.files = files
        self.writer = writer
        self.adjustPlan = adjustPlan
    }

    /// Adds the settings bundle, the Dependi phase and the sandbox setting to one target, and returns one line for each change.
    ///
    /// The settings bundle path is absolute. If nothing is at `backupPath`, it writes the backup there first.
    /// If something is already there, it never changes it and writes no other backup, so the backup stays the original.
    /// An empty list means that nothing was written, and a dry run writes nothing at all.
    /// A dry run reports the same backup line that a real run would print.
    public func configureBuild(
        projectFilePath: String, targetName: String, settingsBundlePath: String,
        backupPath: String, isDryRun: Bool
    ) throws(DomainError) -> [String] {
        let model = try ProjectFileLoader.load(
            projectFile: ProjectFileLoader.fileLocation(projectFilePath), files: files)
        let original = Array(
            try files.readRegularFile(at: model.path, upToBytes: ProjectFileLoader.sizeLimit))
        try Self.checkLayout(original, path: model.path)
        let scanner = try PBXTextScanner(bytes: original, path: model.path)
        var planner = BuildSetupPlanner(
            model: model, scanner: scanner,
            ids: ProjectObjectIDMaker(existingText: String(decoding: original, as: UTF8.self)))
        let plan = adjustPlan(
            try planner.plan(targetName: targetName, bundlePath: settingsBundlePath))
        if plan.edits.isEmpty { return plan.lines }
        let edited = plan.apply(to: original)
        let after = try ProjectModel.parse(
            Data(edited), path: model.path, folder: model.folder)
        try plan.verify(before: model, after: after)
        try checkSettled(edited, after: after, target: targetName, bundlePath: settingsBundlePath)
        let keepsBackup = files.exists(at: backupPath)
        let lines =
            plan.lines + [
                keepsBackup
                    ? "Dependi: kept the backup of the original project file at \(backupPath)."
                    : "Dependi: backup of the original project file is at \(backupPath)."
            ]
        if isDryRun { return lines }
        try write(
            original: original, edited: edited, realPath: model.path,
            backupPath: keepsBackup ? nil : backupPath)
        return lines
    }

    /// Plans again on the edited text. A correct edit leaves nothing more to do.
    private func checkSettled(
        _ edited: [UInt8], after: ProjectModel, target: String, bundlePath: String
    ) throws(DomainError) {
        let scanner = try PBXTextScanner(bytes: edited, path: after.path)
        var planner = BuildSetupPlanner(
            model: after, scanner: scanner,
            ids: ProjectObjectIDMaker(existingText: String(decoding: edited, as: UTF8.self)))
        guard try planner.plan(targetName: target, bundlePath: bundlePath).isEmpty else {
            throw .fileUnreadable(
                path: after.path,
                reason:
                    "the edit did not give the expected project (a step is still open). Nothing was written."
            )
        }
    }

    /// Refuses text that the planner does not lay out correctly.
    private static func checkLayout(_ bytes: [UInt8], path: String) throws(DomainError) {
        if bytes.contains(0x0D) {
            throw .unsafeProject(path: path, why: "the lines end with CR LF")
        }
        if bytes.first == 0x20
            || zip(bytes, bytes.dropFirst()).contains(where: { $0 == 0x0A && $1 == 0x20 })
        {
            throw .unsafeProject(path: path, why: "the lines are indented with spaces")
        }
    }

    /// Writes the backup first, if there is one to write, and reads it back.
    /// Then it replaces the project file in one move.
    private func write(
        original: [UInt8], edited: [UInt8], realPath: String, backupPath: String?
    ) throws(DomainError) {
        if let backupPath {
            try writer.createDirectory(at: ProjectPathMath.parent(of: backupPath))
            try writer.write(Data(original), toPath: backupPath)
            let backup = try files.readRegularFile(
                at: files.realPath(of: backupPath), upToBytes: ProjectFileLoader.sizeLimit)
            guard Array(backup) == original else {
                throw .fileUnwritable(
                    path: backupPath, reason: "the backup does not match the original")
            }
        }
        let temporary = realPath + ".dependi-new"
        do {
            try writer.write(Data(edited), toPath: temporary)
            try writer.moveItem(at: temporary, to: realPath)
        } catch {
            try? writer.removeItem(at: temporary)
            throw error
        }
    }
}
