import DependiDomain
import DependiEntities
import DependiProjectFile
import DependiTestSupport
import Foundation
import Testing

@Suite("Package traits from a project file", .timeLimit(.minutes(1)))
struct PackageTraitsTests {
    private let sqlite = "https://github.com/stephencelis/SQLite.swift.git"
    private let alamofire = "https://github.com/Alamofire/Alamofire.git"
    private let kingfisher = "https://github.com/onevcat/Kingfisher.git"
    private let nuke = "https://github.com/kean/Nuke.git"

    /// Reads the traits fixture after replacing pieces of its text.
    private func readEdited(_ edits: [(String, String)]) throws -> LinkedProductSet {
        var text = String(decoding: FixtureWorld.fixture("package-traits"), as: UTF8.self)
        for (original, replacement) in edits {
            #expect(text.contains(original), "the fixture no longer holds \(original)")
            text = text.replacingOccurrences(of: original, with: replacement)
        }
        let world = FixtureWorld()
        try world.files.addDirectory(at: "/work/App/App.xcodeproj")
        try world.files.addFile(
            at: "/work/App/App.xcodeproj/project.pbxproj", contents: Data(text.utf8))
        return try ProjectFileReader(files: world.files).linkedProducts(
            projectFilePath: "/work/App/App.xcodeproj", targetName: "App")
    }

    private func reason(of error: any Error) -> String {
        if case .fileUnreadable(_, let reason) = error as? DomainError { return reason }
        return "other: \(error)"
    }

    // MARK: Success

    @Test("the traits of every package reference are read exactly")
    func projectTraitsReadExactly() throws {
        let set = try FixtureWorld.read("package-traits")
        let expected: [String: Set<String>] = [
            sqlite: ["FTS5", "SQLiteSwiftCSQLite"],
            alamofire: [],
            nuke: ["default"],
            kingfisher: ["Animated"],
            "https://github.com/onevcat/Kingfisher": ["default"],
            "/work/App/Packages/Core": ["Extra", "Logging"],
        ]
        #expect(set.packageTraits == expected)
    }

    @Test("a remote reference that lists traits gives those traits")
    func remoteReferenceTraitsAreRead() throws {
        let set = try FixtureWorld.read("package-traits")
        #expect(set.packageTraits[sqlite] == ["FTS5", "SQLiteSwiftCSQLite"])
    }

    @Test("a local reference that lists traits gives those traits under its folder")
    func localReferenceTraitsAreRead() throws {
        let set = try FixtureWorld.read("package-traits")
        #expect(set.packageTraits["/work/App/Packages/Core"] == ["Extra", "Logging"])
        #expect(set.localPackagePaths == ["/work/App/Packages/Core"])
    }

    @Test("an empty trait list is kept apart from a missing one")
    func emptyTraitListIsKept() throws {
        let set = try FixtureWorld.read("package-traits")
        #expect(set.packageTraits[alamofire] == [])
        #expect(set.packageTraits[nuke] == ["default"])
    }

    @Test("a reference with no trait list gives the default trait under its own location")
    func unlistedReferenceGivesDefault() throws {
        let set = try FixtureWorld.read("package-traits")
        #expect(set.packageTraits[nuke] == ["default"])
        #expect(set.packageTraits["https://github.com/onevcat/Kingfisher"] == ["default"])
    }

    @Test("two references to one package under different spellings keep their own names")
    func spellingsOfOnePackageStaySeparate() throws {
        let set = try FixtureWorld.read("package-traits")
        #expect(set.packageTraits[kingfisher] == ["Animated"])
        #expect(set.packageTraits["https://github.com/onevcat/Kingfisher"] == ["default"])
    }

    @Test("a project with no trait lists gives the default trait to every reference")
    func noTraitListsGiveDefaults() throws {
        let set = try FixtureWorld.read("local-package")
        let expected: [String: Set<String>] = [
            "/work/Packages/LocalKit": ["default"],
            "/work/App/Packages/Other": ["default"],
            alamofire: ["default"],
        ]
        #expect(set.packageTraits == expected)
    }

    @Test("an other project that the app reaches adds the traits that it picks")
    func crossProjectTraitsAreRead() throws {
        let world = FixtureWorld()
        try world.place("cross-project", at: "/work/App/App.xcodeproj")
        try world.place("cross-shared-traits", at: "/work/Shared/Shared.xcodeproj")
        let set = try ProjectFileReader(files: world.files).linkedProducts(
            projectFilePath: "/work/App/App.xcodeproj", targetName: "App")
        let expected: [String: Set<String>] = [
            nuke: ["Progressive"],
            alamofire: ["Session", "default"],
            "/work/Shared/Packages/Kit": [],
        ]
        #expect(set.packageTraits == expected)
        #expect(set.localPackagePaths.isEmpty)
    }

    @Test("a remote reference that no product uses, with no URL and no trait list, is skipped")
    func remoteWithoutURLIsSkipped() throws {
        let set = try readEdited([
            (#"repositoryURL = "https://github.com/kean/Nuke.git";"#, ""),
            ("\t\t\t\tBB03 /* Nuke */,\n", ""),
        ])
        #expect(set.packageTraits[sqlite] == ["FTS5", "SQLiteSwiftCSQLite"])
        #expect(set.products.map(\.productName) == ["Alamofire", "Core", "SQLite"])
    }

    // MARK: Failure

    @Test(
        "a trait value that is not a list of names fails and names the reference",
        arguments: [
            "traits = SQLiteSwiftCSQLite;",
            "traits = ( { name = SQLiteSwiftCSQLite; } );",
        ])
    func traitsNotAList(replacement: String) throws {
        let original = "traits = (\n\t\t\t\tSQLiteSwiftCSQLite,\n\t\t\t);"
        do {
            _ = try readEdited([(original, replacement)])
            Issue.record("expected a failure")
        } catch {
            let expected = "package reference AB12 has traits that are not a list of names"
            #expect(reason(of: error) == expected)
        }
    }

    @Test("a local reference with a trait value that is not a list fails and names it")
    func localTraitsNotAList() throws {
        do {
            _ = try readEdited([
                ("traits = (\n\t\t\t\tExtra,\n\t\t\t\tLogging,\n\t\t\t);", "traits = Extra;")
            ])
            Issue.record("expected a failure")
        } catch {
            #expect(reason(of: error).contains("package reference CD34 has traits"))
        }
    }

    @Test("a remote reference that lists traits but has no URL fails and names it")
    func traitsWithoutURL() throws {
        do {
            _ = try readEdited([
                (#"repositoryURL = "https://github.com/onevcat/Kingfisher.git";"#, "")
            ])
            Issue.record("expected a failure")
        } catch {
            #expect(reason(of: error) == "package reference AB16 has traits but no URL")
        }
    }
}
