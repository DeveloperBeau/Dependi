import DependiDomain
import DependiEntities
import DependiProjectFile
import DependiTestSupport
import Foundation
import TestHelpers
import Testing

@Suite("Legacy local packages", .timeLimit(.minutes(1)))
struct LegacyLocalPackageTests {
    /// Adds a package folder with a manifest under the project folder.
    private func addPackage(_ files: InMemoryFileSystem, _ relative: String) throws {
        try files.addDirectory(at: "/work/App/" + relative)
        try files.addFile(at: "/work/App/" + relative + "/Package.swift", contents: Data())
    }

    private func legacyWorld() throws -> (FixtureWorld, ProjectFileReader) {
        let (world, reader) = try FixtureWorld.single("legacy-local-package")
        for relative in ["Packages/Account", "Packages/AppAccount", "Vendor/Kit"] {
            try addPackage(world.files, relative)
        }
        try world.files.addDirectory(at: "/work/App/Packages/Docs")
        return (world, reader)
    }

    private func read(_ reader: ProjectFileReader) throws -> LinkedProductSet {
        try reader.linkedProducts(projectFilePath: "/work/App/App.xcodeproj", targetName: "App")
    }

    @Test("a folder reference that holds a manifest is a local package, as in the IceCubes shape")
    func legacyFolderReferencesAreLocalPackages() throws {
        let (_, reader) = try legacyWorld()
        let set = try read(reader)
        #expect(
            set.localPackagePaths == [
                "/work/App/Packages/Account", "/work/App/Packages/AppAccount",
                "/work/App/Vendor/Kit",
            ])
        #expect(
            set.products == [
                product("Account", nil), product("AppAccount", nil), product("Kit", nil),
            ])
    }

    @Test(
        "a folder reference without a manifest, a missing folder and a manifest file are not packages"
    )
    func foldersWithoutManifestAreIgnored() throws {
        let (_, reader) = try legacyWorld()
        let paths = try read(reader).localPackagePaths
        #expect(!paths.contains("/work/App/Packages/Docs"))
        #expect(!paths.contains("/work/App/Packages/Missing"))
        #expect(!paths.contains("/work/App/Packages/Account/Package.swift"))
    }

    @Test("a reference outside the project tree, such as an SDK framework, is not a package")
    func sdkReferenceIsIgnored() throws {
        let (world, reader) = try legacyWorld()
        try addPackage(world.files, "System/Library/Frameworks/StoreKit.framework")
        #expect(try read(reader).localPackagePaths.count == 3)
    }

    @Test("a package listed both as a folder reference and as a local reference appears once")
    func bothFormsGiveOnePath() throws {
        let (world, reader) = try legacyWorld()
        let text = String(decoding: FixtureWorld.fixture("legacy-local-package"), as: UTF8.self)
            .replacingOccurrences(
                of: "targets = (T1); };",
                with:
                    "targets = (T1); packageReferences = (L1); };\n\t\tL1 = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Account; };"
            )
        try world.files.addFile(
            at: "/work/App/App.xcodeproj/project.pbxproj", contents: Data(text.utf8))
        let paths = try read(reader).localPackagePaths
        #expect(paths.filter { $0 == "/work/App/Packages/Account" }.count == 1)
        #expect(paths.count == 3)
    }

    @Test("a group cycle ends and the reference inside it is not a package")
    func groupCycleEnds() throws {
        let (world, reader) = try legacyWorld()
        let text = String(decoding: FixtureWorld.fixture("legacy-local-package"), as: UTF8.self)
            .replacingOccurrences(of: "F5, G1, G2);", with: "F5, G2);")
            .replacingOccurrences(
                of: "G1 = {isa = PBXGroup; children = (F6);",
                with: "G1 = {isa = PBXGroup; children = (F6, G3);"
            )
            .replacingOccurrences(
                of: "\t\tG2 = ",
                with:
                    "\t\tG3 = {isa = PBXGroup; children = (G1); path = Loop; sourceTree = \"<group>\"; };\n\t\tG2 = "
            )
        try world.files.addFile(
            at: "/work/App/App.xcodeproj/project.pbxproj", contents: Data(text.utf8))
        #expect(
            try read(reader).localPackagePaths == [
                "/work/App/Packages/Account", "/work/App/Packages/AppAccount",
            ])
    }

    @Test(
        "a source root reference and an absolute reference resolve from the project folder and from the root"
    )
    func sourceRootAndAbsoluteReferences() throws {
        let (world, reader) = try legacyWorld()
        try addPackage(world.files, "Packages/Docs")
        try world.files.addDirectory(at: "/shared/Abs")
        try world.files.addFile(at: "/shared/Abs/Package.swift", contents: Data())
        let text = String(decoding: FixtureWorld.fixture("legacy-local-package"), as: UTF8.self)
            .replacingOccurrences(
                of: "path = Packages/Docs; sourceTree = \"<group>\"",
                with: "path = Packages/Docs; sourceTree = SOURCE_ROOT"
            )
            .replacingOccurrences(
                of: "path = Packages/Missing; sourceTree = \"<group>\"",
                with: "path = /shared/Abs; sourceTree = \"<absolute>\"")
        try world.files.addFile(
            at: "/work/App/App.xcodeproj/project.pbxproj", contents: Data(text.utf8))
        #expect(
            try read(reader).localPackagePaths == [
                "/shared/Abs", "/work/App/Packages/Account", "/work/App/Packages/AppAccount",
                "/work/App/Packages/Docs", "/work/App/Vendor/Kit",
            ])
    }

    @Test("fuzz: generated projects give exactly the folders that are packages (seeded)")
    func fuzzFolderReferences() throws {
        let seed: UInt64 = SeededGenerator.defaultSeed
        print("legacy local package fuzz seed: \(seed)")
        var generator = SeededGenerator(seed: seed)
        for round in 0..<80 {
            var objects: [String] = []
            var rootChildren: [String] = []
            var expected = Set<String>()
            let files = InMemoryFileSystem()
            for index in 0..<Int.random(in: 0...8, using: &generator) {
                let type = ["wrapper", "folder", "text", "wrapper.framework", "sourcecode.swift"]
                    .randomElement(using: &generator)!
                let hasManifest = Bool.random(using: &generator)
                let inGroup = Bool.random(using: &generator)
                let relative = (inGroup ? "g\(index)/" : "") + "p\(index)"
                if hasManifest { try addPackage(files, relative) }
                objects.append(
                    "R\(index) = {isa = PBXFileReference; lastKnownFileType = \(type); path = p\(index); sourceTree = \"<group>\"; };"
                )
                if inGroup {
                    objects.append(
                        "H\(index) = {isa = PBXGroup; children = (R\(index)); path = g\(index); sourceTree = \"<group>\"; };"
                    )
                    rootChildren.append("H\(index)")
                } else {
                    rootChildren.append("R\(index)")
                }
                if hasManifest && (type == "wrapper" || type == "folder") {
                    expected.insert("/work/App/" + relative)
                }
            }
            let text = """
                {
                    archiveVersion = 1; classes = {}; objectVersion = 56;
                    objects = {
                        P0 = {isa = PBXProject; buildConfigurationList = PL; mainGroup = G0; targets = (T1); };
                        PL = {isa = XCConfigurationList; buildConfigurations = (); };
                        G0 = {isa = PBXGroup; children = (\(rootChildren.joined(separator: ", "))); sourceTree = "<group>"; };
                        T1 = {isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application"; dependencies = (); packageProductDependencies = (); buildPhases = (); };
                        \(objects.joined(separator: "\n"))
                    };
                    rootObject = P0;
                }
                """
            try files.addDirectory(at: "/work/App/App.xcodeproj")
            try files.addFile(
                at: "/work/App/App.xcodeproj/project.pbxproj", contents: Data(text.utf8))
            let found = Set(try read(ProjectFileReader(files: files)).localPackagePaths)
            #expect(
                found.subtracting(expected).isEmpty,
                "false positive, seed \(seed) round \(round): \(found.subtracting(expected))")
            #expect(
                expected.subtracting(found).isEmpty,
                "false negative, seed \(seed) round \(round): \(expected.subtracting(found))")
        }
    }
}
