import DependiDomain
import DependiEntities
import TestHelpers
import Testing

@Suite("Output name slugger")
struct OutputNameSluggerTests {
    private let slugger = OutputNameSlugger()

    @Test(
        "the slug is the identity, a dash and eight hex characters of the SHA-256 of the location")
    func slugMatchesHandComputedHash() {
        #expect(
            slugger.slug(identity: PackageIdentity("kit"), normalizedLocation: "org/kit")
                == "kit-79623b0b")
        #expect(
            slugger.slug(identity: PackageIdentity("utils"), normalizedLocation: "a/utils")
                == "utils-62b0e77e")
        #expect(
            slugger.slug(identity: PackageIdentity("utils"), normalizedLocation: "b/utils")
                == "utils-da5a3048")
    }

    @Test("two locations with one identity give different slugs")
    func differentLocationsDiffer() {
        let one = slugger.slug(identity: PackageIdentity("utils"), normalizedLocation: "a/utils")
        let two = slugger.slug(identity: PackageIdentity("utils"), normalizedLocation: "b/utils")
        #expect(one != two)
    }

    @Test("the same input always gives the same slug")
    func stable() {
        let identity = PackageIdentity("kit")
        #expect(
            slugger.slug(identity: identity, normalizedLocation: "x/kit")
                == slugger.slug(identity: identity, normalizedLocation: "x/kit"))
    }

    @Test("path characters and odd text are reduced to a safe name")
    func unsafeIdentityIsReduced() {
        #expect(
            slugger.slug(identity: PackageIdentity("../x y"), normalizedLocation: "x/y")
                == "x-y-bd3c9047")
        #expect(
            slugger.slug(identity: PackageIdentity(""), normalizedLocation: "")
                == "package-e3b0c442")
        #expect(
            slugger.slug(identity: PackageIdentity("///"), normalizedLocation: "")
                == "package-e3b0c442")
        #expect(
            slugger.slug(identity: PackageIdentity("A.B"), normalizedLocation: "") == "a-b-e3b0c442"
        )
    }

    @Test("fuzz: a slug only holds safe characters and ends with eight hex characters")
    func fuzzSlugShape() {
        let alphabet = Array("abcXYZ019./\\:;$()- _é\u{0}")
        for seed in [SeededGenerator.defaultSeed, 21, 22] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<300 {
                let length = Int.random(in: 0...10, using: &generator)
                let identity = String(
                    (0..<length).map { _ in alphabet.randomElement(using: &generator)! })
                let slug = slugger.slug(
                    identity: PackageIdentity(identity), normalizedLocation: identity)
                let valid =
                    slug.range(of: #"^[a-z0-9_-]+-[0-9a-f]{8}$"#, options: .regularExpression)
                    != nil
                #expect(valid, "slug \(slug.debugDescription) for \(identity.debugDescription)")
                #expect(!slug.contains("/") && !slug.contains("."))
            }
        }
    }
}
