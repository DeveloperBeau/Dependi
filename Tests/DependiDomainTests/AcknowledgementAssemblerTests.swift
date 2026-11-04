import DependiDomain
import DependiEntities
import Testing

@Suite("Acknowledgement assembler", .timeLimit(.minutes(1)))
struct AcknowledgementAssemblerTests {
    private let assembler = AcknowledgementAssembler(slugger: OutputNameSlugger())

    private func item(
        _ name: String, identity: String? = nil, location: String? = nil, documents: Int = 1
    )
        -> Acknowledgement
    {
        let docs = (0..<documents).map { try! LicenseDocument(fileName: "LICENSE\($0)", text: "t") }
        return Acknowledgement(
            displayName: name, identity: PackageIdentity(identity ?? name.lowercased()),
            normalizedLocation: location ?? "org/\(name.lowercased())", documents: docs)
    }

    @Test("items are sorted by name without regard to case")
    func sortedWithoutCase() throws {
        let result = try assembler.assemble([
            item("zeta"), item("Beta"), item("alpha"), item("Gamma"),
        ])
        #expect(result.map(\.displayName) == ["alpha", "Beta", "Gamma", "zeta"])
    }

    @Test("names that differ only in case are ordered by identity")
    func caseTieBreak() throws {
        let one = item("Kit", identity: "kit-b", location: "x/kit-b")
        let two = item("kit", identity: "kit-a", location: "x/kit-a")
        #expect(try assembler.assemble([one, two]).map(\.identity.value) == ["kit-a", "kit-b"])
        #expect(try assembler.assemble([two, one]).map(\.identity.value) == ["kit-a", "kit-b"])
    }

    @Test("sorting does not depend on the locale for non-ASCII names")
    func nonAsciiOrder() throws {
        let result = try assembler.assemble([
            item("İstanbul", identity: "a", location: "a"),
            item("Zed", identity: "b", location: "b"),
        ])
        #expect(
            result.map(\.displayName)
                == ["Zed", "İstanbul"].sorted { $0.lowercased() < $1.lowercased() })
    }

    @Test("a package with no license is refused and named")
    func missingLicense() {
        #expect(throws: DomainError.licenseMissing(package: "Bare")) {
            try assembler.assemble([item("Kit"), item("Bare", documents: 0)])
        }
    }

    @Test("two packages with one identity are refused and both locations are named")
    func duplicateIdentity() {
        let one = item("Utils", identity: "utils", location: "a/utils")
        let two = item("Utils", identity: "utils", location: "b/utils")
        #expect(throws: DomainError.identityConflict(first: "a/utils", second: "b/utils")) {
            try assembler.assemble([one, two])
        }
    }

    @Test(
        "two packages whose output names collide are refused, using two locations found with equal 48-bit hash prefixes"
    )
    func slugCollision() {
        let one = item("Kit", identity: "kit", location: "collide/606695")
        let two = item("Kit", identity: "Kit", location: "collide/35466346")
        #expect(
            throws: DomainError.slugCollision(first: "collide/606695", second: "collide/35466346")
        ) {
            try assembler.assemble([one, two])
        }
    }

    @Test("a manual entry that repeats a resolved package is refused")
    func manualEntryRepeats() {
        let resolved = item("Kit", identity: "kit", location: "org/kit")
        let manual = item("Kit (vendored)", identity: "kit", location: "vendor/kit")
        #expect(throws: DomainError.identityConflict(first: "org/kit", second: "vendor/kit")) {
            try assembler.assemble([resolved, manual])
        }
    }

    @Test("an empty list gives an empty list")
    func emptyList() throws {
        #expect(try assembler.assemble([]).isEmpty)
    }
}
