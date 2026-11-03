import Foundation
import Testing

@Suite("Architecture checks")
struct ArchitectureCheckerTests {
    // MARK: Ring edges in declared dependencies

    @Test("a feature that depends on infrastructure is a ring edge violation")
    func featureOnInfrastructureFails() {
        let dump = Planted.dump([
            Planted.target("DependiGenerate", dependsOn: ["DependiFileSystem"]),
            Planted.target("DependiFileSystem"),
        ])
        let found = ArchitectureChecker.checkDeclaredDependencies(dump: dump)
        #expect(Planted.rules(found) == ["ringEdge"])
        #expect(found.first?.location == "DependiGenerate")
    }

    @Test("infrastructure that depends on infrastructure is a ring edge violation")
    func infrastructureOnInfrastructureFails() {
        let dump = Planted.dump([
            Planted.target("DependiPackageGraph", dependsOn: ["DependiProcess"])
        ])
        #expect(
            Planted.rules(ArchitectureChecker.checkDeclaredDependencies(dump: dump)) == ["ringEdge"]
        )
    }

    @Test("allowed edges in every ring pass")
    func allowedEdgesPass() {
        let dump = Planted.dump([
            Planted.target("DependiDomain", dependsOn: ["DependiEntities"]),
            Planted.target("DependiFileSystem", dependsOn: ["DependiEntities", "DependiDomain"]),
            Planted.target("DependiGenerate", dependsOn: ["DependiEntities", "DependiDomain"]),
            Planted.target(
                "DependiComposition",
                dependsOn: [
                    "DependiEntities", "DependiDomain", "DependiFileSystem", "DependiGenerate",
                ]),
            Planted.target("DependiTestSupport", dependsOn: ["DependiEntities", "DependiDomain"]),
        ])
        #expect(ArchitectureChecker.checkDeclaredDependencies(dump: dump).isEmpty)
    }

    @Test("an external product is a third-party violation")
    func externalProductFails() {
        let dump = Planted.dump([Planted.target("DependiDomain", products: ["Collections"])])
        #expect(
            Planted.rules(ArchitectureChecker.checkDeclaredDependencies(dump: dump)) == [
                "thirdParty"
            ])
    }

    @Test("test targets are not checked for ring edges")
    func testTargetsAreSkipped() {
        let dump = Planted.dump([
            Planted.target("DomainTests", type: "test", dependsOn: ["DependiFileSystem"])
        ])
        #expect(ArchitectureChecker.checkDeclaredDependencies(dump: dump).isEmpty)
    }

    // MARK: Ring map

    @Test("a module that is not in the ring map is a violation")
    func unmappedModuleFails() {
        let dump = Planted.dump([Planted.target("Mystery")])
        let found = ArchitectureChecker.checkRingMap(dump: dump, sources: [])
        #expect(Planted.rules(found) == ["ringMap"])
    }

    @Test("a source folder that is not in the ring map is a violation")
    func unmappedSourceFolderFails() {
        let found = ArchitectureChecker.checkRingMap(
            dump: Planted.dump([]), sources: [Planted.file("Mystery", "x")])
        #expect(Planted.rules(found) == ["ringMap"])
    }

    @Test("mapped modules and test targets pass the ring map check")
    func mappedModulesPass() {
        let dump = Planted.dump([
            Planted.target("DependiDomain"),
            Planted.target("AnythingTests", type: "test"),
        ])
        #expect(ArchitectureChecker.checkRingMap(dump: dump, sources: []).isEmpty)
    }

    // MARK: Language settings

    @Test("a package without Swift 6 mode is a violation")
    func missingSwiftSixFails() {
        let dump = Planted.dump([Planted.target("DependiDomain")], languages: ["5"])
        #expect(Planted.rules(ArchitectureChecker.checkLanguageSettings(dump: dump)) == ["swift6"])
    }

    @Test("a target without ExistentialAny is a violation, test targets included")
    func missingExistentialAnyFails() {
        let dump = Planted.dump([
            Planted.target("DependiDomain", features: []),
            Planted.target("DomainTests", type: "test", features: []),
        ])
        let found = ArchitectureChecker.checkLanguageSettings(dump: dump)
        #expect(Planted.rules(found) == ["existentialAny", "existentialAny"])
    }

    @Test("Swift 6 mode with ExistentialAny passes")
    func languageSettingsPass() {
        let dump = Planted.dump([Planted.target("DependiDomain")])
        #expect(ArchitectureChecker.checkLanguageSettings(dump: dump).isEmpty)
    }

    // MARK: Imports

    private let domainDump = Planted.dump([
        Planted.target("DependiDomain", dependsOn: ["DependiEntities"]),
        Planted.target("DependiFileSystem", dependsOn: ["DependiEntities", "DependiDomain"]),
    ])

    @Test("an import of a module in a forbidden ring is a ring edge violation")
    func forbiddenImportFails() {
        let source = Planted.file("DependiDomain", "import DependiFileSystem")
        let found = ArchitectureChecker.checkImports(dump: domainDump, sources: [source])
        #expect(Planted.rules(found) == ["ringEdge"])
    }

    @Test("an import of an allowed but undeclared module is a violation")
    func undeclaredImportFails() {
        let source = Planted.file(
            "DependiFileSystem", "import DependiProcessMissing\nimport DependiEntities")
        let dump = Planted.dump([Planted.target("DependiFileSystem", dependsOn: ["DependiDomain"])])
        let found = ArchitectureChecker.checkImports(dump: dump, sources: [source])
        #expect(Planted.rules(found).sorted() == ["undeclaredImport", "unknownImport"])
    }

    @Test("an import of an unknown module is a violation")
    func unknownImportFails() {
        let source = Planted.file("DependiDomain", "import SwiftUI")
        let found = ArchitectureChecker.checkImports(dump: domainDump, sources: [source])
        #expect(Planted.rules(found) == ["unknownImport"])
    }

    @Test("Dispatch is allowed in DependiProcess and refused elsewhere")
    func dispatchOnlyInProcess() {
        let dump = Planted.dump([Planted.target("DependiProcess"), Planted.target("DependiDomain")])
        let allowed = ArchitectureChecker.checkImports(
            dump: dump, sources: [Planted.file("DependiProcess", "import Dispatch")])
        let refused = ArchitectureChecker.checkImports(
            dump: dump, sources: [Planted.file("DependiDomain", "import Dispatch")])
        #expect(allowed.isEmpty)
        #expect(Planted.rules(refused) == ["unknownImport"])
    }

    @Test("production code that imports the test support module is a violation")
    func testSupportImportFails() {
        let dump = Planted.dump([Planted.target("DependiDomain")])
        let found = ArchitectureChecker.checkImports(
            dump: dump, sources: [Planted.file("DependiDomain", "import DependiTestSupport")])
        #expect(Planted.rules(found) == ["testSupportImport"])
    }

    @Test("declared imports that follow the rings pass")
    func declaredImportsPass() {
        let source = Planted.file(
            "DependiFileSystem", "import Foundation\nimport DependiDomain\nimport DependiEntities")
        #expect(ArchitectureChecker.checkImports(dump: domainDump, sources: [source]).isEmpty)
    }

    // MARK: Source rules

    @Test("two top-level public types in one file are a violation")
    func twoPublicTypesFail() {
        let text = "/// A.\npublic struct A {}\n/// B.\npublic enum B {}\n"
        let found = ArchitectureChecker.checkSourceRules(sources: [
            Planted.file("DependiDomain", text)
        ])
        #expect(Planted.rules(found) == ["onePublicType"])
    }

    @Test("a public type with a nested public type counts once")
    func nestedPublicTypeCountsOnce() {
        let text = "/// A.\npublic struct A {\n    /// N.\n    public enum N {}\n}\n"
        let found = ArchitectureChecker.checkSourceRules(sources: [
            Planted.file("DependiDomain", text)
        ])
        #expect(found.isEmpty)
    }

    @Test("a public declaration without a doc comment is a violation with its line")
    func missingDocCommentFails() {
        let text = "/// A.\npublic struct A {\n    public func run() {}\n}\n"
        let found = ArchitectureChecker.checkSourceRules(sources: [
            Planted.file("DependiDomain", text)
        ])
        #expect(found.map(\.location) == ["DependiDomain/File.swift:3"])
    }

    @Test("a doc comment above an attribute counts")
    func docCommentAboveAttributePasses() {
        let text = "/// A.\n@frozen\npublic struct A {}\n"
        #expect(
            ArchitectureChecker.checkSourceRules(sources: [Planted.file("DependiDomain", text)])
                .isEmpty)
    }

    @Test("a doc comment inside a string does not count as documentation")
    func docCommentInStringDoesNotCount() {
        let text = "let note = \"\"\"\n/// fake\n\"\"\"\npublic struct A {}\n"
        let lines = SourceRules.undocumentedPublicDeclarationLines(in: text)
        #expect(lines == [4])
    }

    @Test("a collaborator with a default value in an initializer is a violation")
    func collaboratorDefaultFails() {
        let text =
            "/// A.\npublic struct A {\n    /// Makes A.\n    public init(files: any FileReading = Real(), count: Int = 3) {}\n}\n"
        let found = SourceRules.collaboratorDefaults(in: text)
        #expect(found.count == 1)
        #expect(found.first?.contains("files") == true)
    }

    @Test("plain defaults and collaborators without defaults are not violations")
    func plainDefaultsPass() {
        let text = "init(count: Int = 3, name: String = \"x\", files: any FileReading) {}"
        #expect(SourceRules.collaboratorDefaults(in: text).isEmpty)
    }

    @Test("two error enumerations in one module are a violation")
    func twoErrorEnumsFail() {
        let sources = [
            Planted.file("DependiDomain", "enum FirstError: Error {}", name: "A.swift"),
            Planted.file("DependiDomain", "enum SecondError: Error, Equatable {}", name: "B.swift"),
        ]
        #expect(
            Planted.rules(ArchitectureChecker.checkSourceRules(sources: sources)) == [
                "oneErrorEnum"
            ])
    }

    @Test("one error enumeration per module passes")
    func oneErrorEnumPasses() {
        let sources = [
            Planted.file("DependiDomain", "enum FirstError: Error {}", name: "A.swift"),
            Planted.file("DependiEntities", "enum OtherError: Error {}", name: "B.swift"),
        ]
        #expect(ArchitectureChecker.checkSourceRules(sources: sources).isEmpty)
    }

    @Test("untyped throws in the domain is a violation and typed throws passes")
    func untypedThrowsInDomain() {
        let bad = Planted.file("DependiDomain", "func run() throws {}")
        let good = Planted.file(
            "DependiDomain", "func run() throws(FileError) {}\nfunc map() rethrows {}")
        let elsewhere = Planted.file("DependiFileSystem", "func run() throws {}")
        #expect(
            Planted.rules(ArchitectureChecker.checkSourceRules(sources: [bad])) == ["typedThrows"])
        #expect(ArchitectureChecker.checkSourceRules(sources: [good]).isEmpty)
        #expect(ArchitectureChecker.checkSourceRules(sources: [elsewhere]).isEmpty)
    }

    @Test("each forbidden fragment is found and clean text is not flagged")
    func forbiddenFragmentsAreFound() {
        for fragment in SourceRules.forbiddenSourceFragments {
            let found = SourceRules.forbiddenFragments(in: "let x = \(fragment)")
            #expect(found == [fragment])
        }
        #expect(
            SourceRules.forbiddenFragments(in: "let sandboxed = true // a sandbox is on").isEmpty)
    }
}
