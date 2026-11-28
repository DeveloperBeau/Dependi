import DependiDomain
import Foundation

/// Edits a `project.pbxproj` as text so that an app target runs the Dependi build step.
public struct ProjectFileEditor: Sendable {
    private let files: any FileReading
    private let writer: any FileWriting
    private let adjustPlan: @Sendable (BuildSetupPlan) -> BuildSetupPlan
    private let lastBackupNumber: Int

    /// Creates an editor that reads through `files` and writes through `writer`.
    public init(files: any FileReading, writer: any FileWriting) {
        self.init(files: files, writer: writer, adjustPlan: { $0 })
    }

    /// Lets a test change the plan before it is checked, or lower the highest backup number.
    init(
        files: any FileReading, writer: any FileWriting,
        adjustPlan: @escaping @Sendable (BuildSetupPlan) -> BuildSetupPlan,
        lastBackupNumber: Int = 999
    ) {
        self.files = files
        self.writer = writer
        self.adjustPlan = adjustPlan
        self.lastBackupNumber = lastBackupNumber
    }

    /// Adds the settings bundle, the Dependi phase and the sandbox setting to one target, and returns one line for each change.
    ///
    /// The settings bundle path is absolute. It writes a backup first and keeps the first backup for ever.
    /// If nothing is at `backupPath`, the backup goes there. Otherwise it goes to `backupPath.2`,
    /// then `.3`, and so on, and it refuses when every number up to `.999` is taken.
    /// An empty list means that nothing was written, and a dry run writes nothing at all.
    /// A dry run reports the path that a real run would use.
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
        let backup = try freeBackup(for: backupPath)
        let lines = plan.lines + [backup.line]
        if isDryRun { return lines }
        try write(original: original, edited: edited, realPath: model.path, backupPath: backup.path)
        return lines
    }

    /// The path for this backup and the line that reports it.
    private func freeBackup(for backupPath: String) throws(DomainError) -> (
        path: String, line: String
    ) {
        if !files.exists(at: backupPath) {
            return (backupPath, "Dependi: backup of the original project file is at \(backupPath).")
        }
        for number in stride(from: 2, through: lastBackupNumber, by: 1) {
            let path = "\(backupPath).\(number)"
            if !files.exists(at: path) {
                return (path, "Dependi: backup of the project file before this edit is at \(path).")
            }
        }
        throw .fileUnwritable(
            path: ProjectPathMath.parent(of: backupPath),
            reason:
                "every backup name from .2 to .\(lastBackupNumber) is taken in this folder. Remove old backups, then run again"
        )
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

    /// Writes the backup first and reads it back, then replaces the project file in one move.
    private func write(
        original: [UInt8], edited: [UInt8], realPath: String, backupPath: String
    ) throws(DomainError) {
        try writer.createDirectory(at: ProjectPathMath.parent(of: backupPath))
        try writer.write(Data(original), toPath: backupPath)
        let backup = try files.readRegularFile(
            at: files.realPath(of: backupPath), upToBytes: ProjectFileLoader.sizeLimit)
        guard Array(backup) == original else {
            throw .fileUnwritable(
                path: backupPath, reason: "the backup does not match the original")
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
