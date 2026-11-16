import DependiComposition
import Foundation
import Testing

@Suite("End to end with package traits", .timeLimit(.minutes(5)))
struct EndToEndTraitsTests {
    /// A project that links the SQLite product of the package SQLite.swift.
    private static let sqliteProject = EndToEndWorld.alamofireProject
        .replacingOccurrences(
            of: "https://github.com/Alamofire/Alamofire.git",
            with: "https://github.com/stephencelis/SQLite.swift.git"
        )
        .replacingOccurrences(of: "productName = Alamofire", with: "productName = SQLite")

    /// A manifest in the shape of SQLite.swift 0.16: two dependencies that each need a trait.
    private static func sqliteManifest(defaultTrait: String) -> String {
        """
        {"name":"SQLite.swift","products":[{"name":"SQLite","targets":["SQLite"]}],
        "targets":[{"name":"SQLite","type":"regular","dependencies":[
        {"product":["SQLiteSwiftCSQLite","CSQLite",null,{"platformNames":[],"traits":["SQLiteSwiftCSQLite"]}]},
        {"product":["SQLCipher","SQLCipher.swift",null,{"platformNames":["ios","macos"],"traits":["SQLCipher"]}]}]}],
        "traits":[{"enabledTraits":[],"name":"SQLCipher"},{"enabledTraits":[],"name":"SQLiteSwiftCSQLite"},
        {"enabledTraits":[],"name":"SystemSQLite"},{"enabledTraits":["\(defaultTrait)"],"name":"default"}],
        "dependencies":[{"sourceControl":[{"identity":"csqlite","traits":[{"name":"default"}]}]},
        {"sourceControl":[{"identity":"sqlcipher.swift","traits":[{"name":"default"}]}]}]}
        """
    }

    private func world(defaultTrait: String, csqlite: Bool) throws -> EndToEndWorld {
        let world = try EndToEndWorld(projectFile: Self.sqliteProject)
        try world.addRemote(
            "sqlite.swift", owner: "stephencelis",
            manifest: Self.sqliteManifest(defaultTrait: defaultTrait))
        if csqlite {
            try world.addRemote(
                "csqlite", owner: "stephencelis",
                manifest: EndToEndWorld.manifest(product: "SQLiteSwiftCSQLite"))
        }
        let resolved =
            #"{"version":2,"pins":[{"identity":"sqlite.swift","kind":"remoteSourceControl","location":"https://github.com/stephencelis/SQLite.swift.git","state":{"revision":"r1","version":"1.0.0"}}]}"#
        try FileManager.default.createDirectory(
            atPath: world.project + "/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm",
            withIntermediateDirectories: true)
        try resolved.write(
            toFile: world.project
                + "/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            atomically: true, encoding: .utf8)
        return world
    }

    @Test("an archive links SQLite.swift and ignores the packages that its off traits gate")
    func offTraitsAreIgnored() throws {
        let world = try world(defaultTrait: "SystemSQLite", csqlite: false)
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["sqlite.swift"])
        #expect(result.output.contains("Dependi: wrote 1 acknowledgement"))
    }

    @Test("an archive follows the package that a default trait gates")
    func defaultTraitIsFollowed() throws {
        let world = try world(defaultTrait: "SQLiteSwiftCSQLite", csqlite: true)
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["csqlite", "sqlite.swift"])
    }

    @Test("a product that a trait that is on needs, and that no package has, fails and names it")
    func missingGatedProductFails() throws {
        let world = try world(defaultTrait: "SQLiteSwiftCSQLite", csqlite: false)
        let result = try world.run()
        #expect(result.code == 1)
        #expect(
            result.errors.contains(
                "No package provides the product SQLiteSwiftCSQLite in package CSQLite."))
    }
}
