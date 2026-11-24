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

    /// Builds the world. `projectTraits` is the `traits` entry that the project writes on its
    /// SQLite.swift reference, such as `traits = (SQLiteSwiftCSQLite, );`, or `nil` for none.
    private func world(
        defaultTrait: String, csqlite: Bool, projectTraits: String? = nil,
        sqlcipher: Bool = false, secondReference: String? = nil
    ) throws -> EndToEndWorld {
        var projectFile = Self.sqliteProject
        if let secondReference {
            projectFile =
                projectFile
                .replacingOccurrences(
                    of: "packageReferences = (R1);", with: "packageReferences = (R1, R2);"
                )
                .replacingOccurrences(
                    of: "D1 = {isa = XCSwiftPackageProductDependency;",
                    with: "R2 = {isa = XCRemoteSwiftPackageReference; "
                        + #"repositoryURL = "https://github.com/stephencelis/SQLite.swift"; "#
                        + secondReference + " };\n\t\tD1 = {isa = XCSwiftPackageProductDependency;")
        }
        if let projectTraits {
            projectFile = projectFile.replacingOccurrences(
                of: #"repositoryURL = "https://github.com/stephencelis/SQLite.swift.git";"#,
                with: #"repositoryURL = "https://github.com/stephencelis/SQLite.swift.git"; "#
                    + projectTraits)
        }
        let world = try EndToEndWorld(projectFile: projectFile)
        try world.addRemote(
            "sqlite.swift", owner: "stephencelis",
            manifest: Self.sqliteManifest(defaultTrait: defaultTrait))
        var pins = [
            #"{"identity":"sqlite.swift","kind":"remoteSourceControl","location":"https://github.com/stephencelis/SQLite.swift.git","state":{"revision":"r1","version":"1.0.0"}}"#
        ]
        if csqlite {
            try world.addRemote(
                "csqlite", owner: "stephencelis",
                manifest: EndToEndWorld.manifest(product: "SQLiteSwiftCSQLite"))
            pins.append(
                #"{"identity":"csqlite","kind":"remoteSourceControl","location":"https://github.com/stephencelis/CSQLite.git","state":{"revision":"r1","version":"1.0.0"}}"#
            )
        }
        if sqlcipher {
            try world.addRemote(
                "sqlcipher.swift", owner: "sqlcipher",
                manifest: EndToEndWorld.manifest(product: "SQLCipher"))
            pins.append(
                #"{"identity":"sqlcipher.swift","kind":"remoteSourceControl","location":"https://github.com/sqlcipher/SQLCipher.swift.git","state":{"revision":"r1","version":"1.0.0"}}"#
            )
        }
        let resolved = #"{"version":2,"pins":["# + pins.joined(separator: ",") + "]}"
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

    @Test("an archive follows the package that a trait picked in the project file gates")
    func projectPickedTraitIsFollowed() throws {
        let world = try world(
            defaultTrait: "SystemSQLite", csqlite: true,
            projectTraits: "traits = (SQLiteSwiftCSQLite, );")
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["csqlite", "sqlite.swift"])
        #expect(result.output.contains("Dependi: wrote 2 acknowledgements"))
    }

    @Test("a reference with no trait list and one that lists a trait both count")
    func referencesWithAndWithoutTraitsJoin() throws {
        let world = try world(
            defaultTrait: "SQLCipher", csqlite: true, sqlcipher: true,
            secondReference: "traits = (SQLiteSwiftCSQLite, );")
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["csqlite", "sqlcipher.swift", "sqlite.swift"])
    }

    @Test("an empty trait list in the project file turns the default trait and its package off")
    func projectEmptyTraitListTurnsDefaultsOff() throws {
        let world = try world(
            defaultTrait: "SQLiteSwiftCSQLite", csqlite: false, projectTraits: "traits = ( );")
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["sqlite.swift"])
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
