import DependiDomain
import DependiEntities
import DependiFileSystem
import Foundation
import Testing

@Suite("License validation on a real tree")
struct LicenseOnDiskTests {
    private let arranger = DiskTreeArranger()
    private let limit = 16

    private func validator() -> LicenseFileValidator {
        LicenseFileValidator(files: DiskFileSystem(), maximumBytes: limit)
    }

    private func outcome(
        folder: String, root: String, name: String = "LICENSE"
    ) -> Result<LicenseDocument, DomainError> {
        do {
            return .success(
                try validator().document(named: name, inFolder: folder, root: root, owner: "kit"))
        } catch {
            return .failure(error)
        }
    }

    private func failure(_ result: Result<LicenseDocument, DomainError>) -> DomainError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    @Test("a checkout root reached through a link reads its license")
    func linkedCheckoutRoot() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/kit/LICENSE", contents: Data("MIT text".utf8))
            try arranger.addSymlink(at: temp.root + "/linked", pointingTo: temp.real + "/kit")
            let linked = temp.root + "/linked"
            let result = outcome(folder: linked, root: linked)
            #expect(try result.get().text == "MIT text")
            #expect(try result.get().fileName == "LICENSE")
        }
    }

    @Test("a license link that escapes the checkout is refused")
    func escapingLinkRefused() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/outside/secret", contents: Data("secret".utf8))
            try arranger.addDirectory(at: temp.real + "/kit")
            try arranger.addSymlink(
                at: temp.real + "/kit/LICENSE", pointingTo: "../outside/secret")
            #expect(
                failure(outcome(folder: temp.real + "/kit", root: temp.real + "/kit"))
                    == .licenseOutsideCheckout(package: "kit", file: "LICENSE"))
        }
    }

    @Test("an inside link to a large inside file is measured by the target size")
    func insideLinkMeasuredByTarget() throws {
        try TempFolder.run { temp in
            try arranger.addFile(
                at: temp.real + "/kit/big", contents: Data(repeating: 0x61, count: limit + 10))
            // The link text is 3 bytes, far below the limit. Its own size must not be used.
            try arranger.addSymlink(at: temp.real + "/kit/LICENSE", pointingTo: "big")
            #expect(
                failure(outcome(folder: temp.real + "/kit", root: temp.real + "/kit"))
                    == .licenseTooLarge(package: "kit", file: "LICENSE"))
        }
    }

    @Test("a small inside link is accepted")
    func insideLinkAccepted() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/kit/small", contents: Data("tiny".utf8))
            try arranger.addSymlink(at: temp.real + "/kit/LICENSE", pointingTo: "small")
            let result = outcome(folder: temp.real + "/kit", root: temp.real + "/kit")
            #expect(try result.get().text == "tiny")
        }
    }

    @Test("a license that is a loop of links is reported")
    func licenseLoop() throws {
        try TempFolder.run { temp in
            try arranger.addDirectory(at: temp.real + "/kit")
            try arranger.addSymlink(at: temp.real + "/kit/LICENSE", pointingTo: "other")
            try arranger.addSymlink(at: temp.real + "/kit/other", pointingTo: "LICENSE")
            #expect(
                failure(outcome(folder: temp.real + "/kit", root: temp.real + "/kit"))
                    == .symlinkLoop(path: temp.real + "/kit/LICENSE"))
        }
    }

    @Test("a linked parent folder that escapes the checkout is refused")
    func escapingParentLink() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/outside/LICENSE", contents: Data("out".utf8))
            try arranger.addDirectory(at: temp.real + "/kit")
            try arranger.addSymlink(at: temp.real + "/kit/sub", pointingTo: "../outside")
            #expect(
                failure(outcome(folder: temp.real + "/kit/sub", root: temp.real + "/kit"))
                    == .licenseOutsideCheckout(package: "kit", file: "LICENSE")
            )
        }
    }

    @Test("a sibling folder with the checkout name as prefix is outside the checkout")
    func prefixSiblingIsOutside() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/kit-extra/LICENSE", contents: Data("x".utf8))
            try arranger.addDirectory(at: temp.real + "/kit")
            #expect(
                failure(outcome(folder: temp.real + "/kit-extra", root: temp.real + "/kit"))
                    == .licenseOutsideCheckout(
                        package: "kit", file: "LICENSE")
            )
        }
    }

    @Test("a named pipe named LICENSE is refused")
    func pipeLicense() throws {
        try TempFolder.run { temp in
            try arranger.addDirectory(at: temp.real + "/kit")
            try arranger.addNamedPipe(at: temp.real + "/kit/LICENSE")
            #expect(
                failure(outcome(folder: temp.real + "/kit", root: temp.real + "/kit"))
                    == .notRegularFile(path: temp.real + "/kit/LICENSE"))
        }
    }

    @Test("a folder named LICENSE is refused")
    func folderLicense() throws {
        try TempFolder.run { temp in
            try arranger.addDirectory(at: temp.real + "/kit/LICENSE")
            #expect(
                failure(outcome(folder: temp.real + "/kit", root: temp.real + "/kit"))
                    == .notRegularFile(path: temp.real + "/kit/LICENSE"))
        }
    }

    @Test("a file of exactly the limit is accepted and one byte more is refused")
    func limitBoundary() throws {
        try TempFolder.run { temp in
            try arranger.addFile(
                at: temp.real + "/exact/LICENSE", contents: Data(repeating: 0x61, count: limit))
            try arranger.addFile(
                at: temp.real + "/over/LICENSE", contents: Data(repeating: 0x61, count: limit + 1))
            let exact = outcome(folder: temp.real + "/exact", root: temp.real + "/exact")
            #expect(try exact.get().text.utf8.count == limit)
            #expect(
                failure(outcome(folder: temp.real + "/over", root: temp.real + "/over"))
                    == .licenseTooLarge(package: "kit", file: "LICENSE"))
        }
    }
}
