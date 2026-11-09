import DependiDomain
import DependiTestSupport
import Foundation

/// Loads fixture files and builds in-memory trees for the reader tests.
enum Support {
    static let root = "/work"
    static let sourcePackages = "/work/DD/SourcePackages"

    static func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.replacingOccurrences(of: "$ROOT", with: root)
    }

    /// A file system that holds a `workspace-state.json` and one empty folder for each checkout.
    static func sourcePackagesTree(
        state: Data, checkouts: [String]
    ) throws -> InMemoryFileSystem {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: sourcePackages + "/checkouts")
        try fileSystem.addFile(at: sourcePackages + "/workspace-state.json", contents: state)
        for name in checkouts {
            try fileSystem.addDirectory(at: sourcePackages + "/checkouts/" + name)
        }
        return fileSystem
    }

    static func data(_ text: String) -> Data { Data(text.utf8) }

    /// A state file with the given dependency bodies.
    static func state(version: Int = 7, dependencies: [String]) -> Data {
        data(
            "{\"object\":{\"artifacts\":[],\"dependencies\":[\(dependencies.joined(separator: ","))]},\"version\":\(version)}"
        )
    }

    static func remote(
        identity: String = "kit", location: String = "https://github.com/x/kit.git",
        subpath: String = "kit"
    ) -> String {
        """
        {"basedOn":null,"packageRef":{"identity":"\(identity)","kind":"remoteSourceControl","location":"\(location)","name":"n"},\
        "state":{"checkoutState":{"revision":"abc","version":"1.0.0"},"name":"sourceControlCheckout"},"subpath":"\(subpath)"}
        """
    }
}
