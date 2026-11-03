import DependiDomain
import DependiEntities
import TestHelpers
import Testing

@Suite("Package identity normalizer")
struct PackageIdentityNormalizerTests {
    private let normalizer = PackageIdentityNormalizer()

    @Test(
        "different forms of one repository give one normalized location and identity",
        arguments: [
            "https://github.com/Org/Repo.git", "git@github.com:Org/Repo.git",
            "ssh://git@github.com/Org/Repo", "https://github.com/org/repo/",
            "https://github.com/Org/Repo.GIT", "http://example.org/org/repo",
        ])
    func formsJoin(location: String) {
        #expect(normalizer.normalizedLocation(of: location) == "org/repo")
        #expect(normalizer.identity(forLocation: location) == PackageIdentity("repo"))
    }

    @Test("a repository name that only contains git is not shortened")
    func gitInsideNameIsKept() {
        #expect(
            normalizer.identity(forLocation: "https://github.com/me/my.github.io")
                == PackageIdentity("my.github.io"))
        #expect(
            normalizer.identity(forLocation: "https://github.com/me/digit")
                == PackageIdentity("digit"))
        #expect(normalizer.normalizedLocation(of: "https://github.com/me/legit") == "me/legit")
    }

    @Test("two owners with the same repository name give the same identity but different locations")
    func sameNameDifferentOwners() {
        let first = "https://github.com/a/Utils.git"
        let second = "https://github.com/b/Utils.git"
        #expect(normalizer.identity(forLocation: first) == normalizer.identity(forLocation: second))
        #expect(normalizer.normalizedLocation(of: first) == "a/utils")
        #expect(normalizer.normalizedLocation(of: second) == "b/utils")
    }

    @Test("a local path keeps its folders and takes the last folder as the identity")
    func localPath() {
        #expect(normalizer.normalizedLocation(of: "/work/Packages/Core") == "/work/packages/core")
        #expect(normalizer.identity(forLocation: "/work/Packages/Core/") == PackageIdentity("core"))
    }

    @Test("an empty location gives an empty identity and location")
    func emptyLocation() {
        #expect(normalizer.normalizedLocation(of: "") == "")
        #expect(normalizer.identity(forLocation: "").value == "")
    }

    @Test(
        "fuzz: every identity is lowercase, has no slash and the location has no trailing slash or .git"
    )
    func fuzzProperties() {
        let alphabet = Array("abcXYZ./:@-_ gGiItT")
        for seed in [SeededGenerator.defaultSeed, 3, 17, 1001] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<400 {
                let length = Int.random(in: 0...14, using: &generator)
                let text = String(
                    (0..<length).map { _ in alphabet.randomElement(using: &generator)! })
                let identity = normalizer.identity(forLocation: text).value
                let location = normalizer.normalizedLocation(of: text)
                #expect(
                    identity == identity.lowercased(), "seed \(seed) text \(text.debugDescription)")
                #expect(!identity.contains("/"), "seed \(seed) text \(text.debugDescription)")
                #expect(!location.hasSuffix("/"), "seed \(seed) text \(text.debugDescription)")
                #expect(!location.hasSuffix(".git"), "seed \(seed) text \(text.debugDescription)")
            }
        }
    }

    @Test("fuzz: normalizing an identity again gives the same identity")
    func fuzzIdentityIsIdempotent() {
        let alphabet = Array("abcXYZ./-_ ")
        var generator = SeededGenerator()
        for _ in 0..<400 {
            let length = Int.random(in: 1...10, using: &generator)
            let text =
                "https://host/"
                + String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            let identity = normalizer.identity(forLocation: text)
            #expect(
                normalizer.identity(forLocation: identity.value) == identity,
                "text \(text.debugDescription)")
        }
    }
}
