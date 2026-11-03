import Foundation
import Testing

@Suite("Architecture checks", .timeLimit(.minutes(1)))
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

    @Test(
        "the executable may depend on the composition library and no other ring may depend on itself"
    )
    func compositionMayUseItsOwnRing() {
        let allowed = Planted.dump([Planted.target("dependi", dependsOn: ["DependiComposition"])])
        #expect(ArchitectureChecker.checkDeclaredDependencies(dump: allowed).isEmpty)
        let features = Planted.dump([Planted.target("DependiGenerate", dependsOn: ["DependiInit"])])
        #expect(
            Planted.rules(ArchitectureChecker.checkDeclaredDependencies(dump: features)) == [
                "ringEdge"
            ])
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

    @Test("indirect enums, public extensions and a second type on one line each count as types")
    func hiddenPublicTypesAreCounted() {
        #expect(
            SourceRules.topLevelPublicTypeCount(
                in: "/// A.\npublic struct A {}\n/// B.\npublic indirect enum B {}\n") == 2)
        #expect(
            SourceRules.topLevelPublicTypeCount(
                in: "/// A.\npublic struct A {}\npublic extension A {}\n") == 2)
        #expect(
            SourceRules.topLevelPublicTypeCount(in: "public struct A {}; public final class B {}")
                == 2)
        #expect(
            SourceRules.topLevelPublicTypeCount(in: "public actor A {}\n    public open class B {}")
                == 2)
    }

    @Test("one public type with nested public types, strings and comments counts once")
    func singlePublicTypeIsNotOvercounted() {
        let text = """
            /// A.
            public indirect enum A {
                /// N.
                public struct N {}
                case leaf
            }
            // public struct Fake {}
            let note = "public struct Fake {}"
            struct Internal {}
            """
        #expect(SourceRules.topLevelPublicTypeCount(in: text) == 1)
    }

    @Test("a block comment is not a doc comment and a triple slash comment is")
    func onlyTripleSlashDocuments() {
        #expect(
            SourceRules.undocumentedPublicDeclarationLines(in: "/* A. */\npublic struct A {}\n")
                == [2])
        #expect(
            SourceRules.undocumentedPublicDeclarationLines(in: "/** A. */\npublic struct A {}\n")
                == [2])
        #expect(
            SourceRules.undocumentedPublicDeclarationLines(in: "/// A.\npublic struct A {}\n")
                .isEmpty)
    }

    @Test("an initializer default that builds an object is a violation whatever the type is called")
    func constructedDefaultsFail() {
        let cases = [
            "init(files: DiskFileSystem = DiskFileSystem()) {}",
            "init(gate: ReleaseGate = ReleaseGate()) {}",
            "init(files: (any FileReading)? = Real.shared) {}",
            "init(clock: SystemClock = .live()) {}",
            "init(run: Runner = Runner(), count: Int = 1) {}",
            "static func make(files: DiskFileSystem = DiskFileSystem()) -> Self { fatalError() }",
        ]
        for text in cases {
            #expect(SourceRules.collaboratorDefaults(in: text).count == 1, "missed: \(text)")
        }
    }

    @Test("literal, nil, case and value type defaults are not violations")
    func literalDefaultsPass() {
        let cases = [
            "init(count: Int = 3, ratio: Double = -1.5, name: String = \"x\", on: Bool = true) {}",
            "init(files: (any FileReading)? = nil, items: [String] = [], map: [String: Int] = [:]) {}",
            "init(mode: Mode = .strict, other: Mode? = .none) {}",
            "init(names: Set<String> = Set<String>(), wait: Duration = Duration.seconds(1)) {}",
            "static func make(count: Int = 2) -> Self { fatalError() }",
        ]
        for text in cases {
            #expect(SourceRules.collaboratorDefaults(in: text).isEmpty, "flagged: \(text)")
        }
    }

    @Test("static stored variables, unsafe isolation and global variables are hidden state")
    func hiddenGlobalStateFails() {
        let cases = [
            "enum A {\n    static var count = 0\n}",
            "enum A {\n    static var cache: [String: Int] = [:]\n}",
            "enum A {\n    static var value: Int\n}",
            "enum A {\n    nonisolated(unsafe) static let shared = 1\n}",
            "var counter = 0\n",
            "var table: [String] = { [] }()\n",
        ]
        for text in cases {
            #expect(SourceRules.hiddenGlobalState(in: text).count >= 1, "missed: \(text)")
        }
        let found = ArchitectureChecker.checkSourceRules(sources: [
            Planted.file("DependiDomain", "var counter = 0\n")
        ])
        #expect(Planted.rules(found) == ["hiddenGlobalState"])
    }

    @Test("computed statics, constants, locals, comments and strings are not hidden state")
    func hiddenGlobalStatePasses() {
        let text = """
            enum A {
                static let limit = 3
                static var names: [String] { ["a"] }
                static var total: Int {
                    var sum = 0
                    sum += 1
                    return sum
                }
            }
            struct B {
                var value = 0
                func run() { var local = 1; local += 1 }
            }
            let ok = 1
            // static var fake = 0
            let note = "static var fake = 0"
            var computedGlobal: Int { 3 }
            """
        #expect(SourceRules.hiddenGlobalState(in: text).isEmpty)
    }

    @Test("a suite without a time limit is found and suites with one are not")
    func suiteTimeLimitRule() {
        let bare = "import Testing\n@Suite(\"A\")\nstruct A {}\n"
        let serialized = "@Suite(\"A\", .serialized)\nstruct A {}\n"
        let bareNoArguments = "@Suite struct A {}\n"
        let limited =
            "@Suite(\"A\", .timeLimit(.minutes(1)))\nstruct A {}\n@Suite(.timeLimit(.minutes(2))) struct B {}\n"
        let wrapped =
            "@Suite(\n    \"A\",\n    .serialized, .timeLimit(.minutes(1)))\nstruct A {}\n"
        let embedded = "let text = \"\"\"\n    @Suite struct Fake {}\n    \"\"\"\n"
        let inString = "@Suite(\"mentions .timeLimit in text\")\nstruct A {}\n"
        #expect(SourceRules.suitesWithoutTimeLimit(in: bare) == [2])
        #expect(SourceRules.suitesWithoutTimeLimit(in: serialized) == [1])
        #expect(SourceRules.suitesWithoutTimeLimit(in: bareNoArguments) == [1])
        #expect(SourceRules.suitesWithoutTimeLimit(in: inString) == [1])
        #expect(SourceRules.suitesWithoutTimeLimit(in: limited).isEmpty)
        #expect(SourceRules.suitesWithoutTimeLimit(in: wrapped).isEmpty)
        #expect(SourceRules.suitesWithoutTimeLimit(in: embedded).isEmpty)
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
