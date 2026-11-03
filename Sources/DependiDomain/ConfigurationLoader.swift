import DependiEntities
import Foundation

/// Reads `.dependi.json` from the project folder.
public struct ConfigurationLoader: Sendable {
    private let files: any FileReading

    /// Creates a loader that reads through the given file interface.
    public init(files: any FileReading) {
        self.files = files
    }

    /// The most bytes read from a configuration file.
    public static let maximumBytes = 1_048_576

    /// Loads the configuration. A missing file is `fileNotFound`, a file that cannot be read is
    /// `fileUnreadable`, and text that cannot be decoded is `configurationCorrupt`.
    public func load(projectDirectory: String) throws(DomainError) -> ToolConfiguration {
        let path = projectDirectory + "/.dependi.json"
        let real = try files.realPath(of: path)
        let data = try files.readRegularFile(at: real, upToBytes: Self.maximumBytes)
        if data.count > Self.maximumBytes {
            throw .configurationCorrupt(
                path: path, reason: "the file is larger than \(Self.maximumBytes) bytes")
        }
        do {
            return try JSONDecoder().decode(ToolConfiguration.self, from: data)
        } catch let error as EntityError {
            throw .configurationCorrupt(path: path, reason: Self.describe(error))
        } catch {
            throw .configurationCorrupt(path: path, reason: "\(error)")
        }
    }

    private static func describe(_ error: EntityError) -> String {
        switch error {
        case .unknownConfigurationKey(let key): return "unknown key \(key)"
        case .invalidVersion(let value): return "invalid version \(value)"
        case .invalidCommit(let value): return "invalid commit \(value)"
        case .invalidLicenseFileName(let value): return "invalid license file name \(value)"
        }
    }
}
