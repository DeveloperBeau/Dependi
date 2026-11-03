import DependiDomain
import Foundation

/// Reads and parses a project file through the injected file interface.
enum ProjectFileLoader {
    /// The largest project file that is read.
    static let sizeLimit = 64 * 1024 * 1024

    /// Loads the `project.pbxproj` at a path. The path may point to a link.
    static func load(projectFile: String, files: any FileReading) throws(DomainError)
        -> ProjectModel
    {
        let real = try files.realPath(of: projectFile)
        let data = try files.readRegularFile(at: real, upToBytes: sizeLimit)
        guard data.count <= sizeLimit else {
            throw .fileUnreadable(path: real, reason: "the project file is longer than 64 MB")
        }
        let xcodeproj = ProjectPathMath.parent(of: real)
        return try ProjectModel.parse(
            data, path: real, folder: ProjectPathMath.parent(of: xcodeproj))
    }
}
