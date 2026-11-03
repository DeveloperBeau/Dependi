import DependiDomain
import DependiEntities
import DependiProjectFile
import DependiTestSupport
import Foundation

/// Builds an in-memory file system that holds fixture project files.
struct FixtureWorld {
    let files = InMemoryFileSystem()

    /// Reads a fixture file next to this source file.
    static func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent("\(name).pbxproj")
        return (try? Data(contentsOf: url)) ?? Data()
    }

    /// Places a fixture as `project.pbxproj` inside the given `.xcodeproj` folder.
    func place(_ fixtureName: String, at xcodeproj: String) throws {
        try files.addDirectory(at: xcodeproj)
        try files.addFile(at: xcodeproj + "/project.pbxproj", contents: Self.fixture(fixtureName))
    }

    /// Places a fixture at `/work/App/App.xcodeproj` and returns a reader for it.
    static func single(_ fixtureName: String) throws -> (FixtureWorld, ProjectFileReader) {
        let world = FixtureWorld()
        try world.place(fixtureName, at: "/work/App/App.xcodeproj")
        return (world, ProjectFileReader(files: world.files))
    }

    /// Reads the products of a target of a fixture placed at the usual path.
    static func read(_ fixtureName: String, target: String = "App") throws -> LinkedProductSet {
        let (_, reader) = try single(fixtureName)
        return try reader.linkedProducts(
            projectFilePath: "/work/App/App.xcodeproj", targetName: target)
    }
}

/// Shorthand for the expected products.
func product(_ name: String, _ package: String?) -> ProductReference {
    ProductReference(productName: name, packageName: package)
}
