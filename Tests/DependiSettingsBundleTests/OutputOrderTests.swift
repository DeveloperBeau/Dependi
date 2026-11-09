import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing
import TestHelpers

@testable import DependiSettingsBundle

@Suite("Output order", .timeLimit(.minutes(1)))
struct OutputOrderTests {
    /// Mixed case names, names that differ only in case, and a manual entry that sorts in the middle.
    private let items: [Acknowledgement] = [
        makeAck("zlib"), makeAck("Alpha"), makeAck("beta"),
        Acknowledgement(
            displayName: "Kit", identity: PackageIdentity("kit-b"), normalizedLocation: "x/kit-b",
            documents: [try! LicenseDocument(fileName: "LICENSE", text: "b")]),
        Acknowledgement(
            displayName: "kit", identity: PackageIdentity("kit-a"), normalizedLocation: "x/kit-a",
            documents: [try! LicenseDocument(fileName: "LICENSE", text: "a")]),
        Acknowledgement(
            displayName: "Manual Tool", identity: PackageIdentity("manual tool"),
            normalizedLocation: "manual/manual tool",
            documents: [try! LicenseDocument(fileName: "tool.txt", text: "m")]),
        makeAck("Zeta"), makeAck("_under"),
    ]

    private func titles(_ fs: InMemoryFileSystem) throws -> [String] {
        let index = try readPlist(fs, "\(bundle)/Acknowledgements.plist")
        let entries = index["PreferenceSpecifiers"] as? [NSDictionary] ?? []
        return entries.compactMap { $0["Title"] as? String }
    }

    @Test("the root list is sorted by lowercased name in code point order, then by identity")
    func rootListOrder() throws {
        let fs = try freshFileSystem()
        let sorted = try AcknowledgementAssembler(slugger: OutputNameSlugger()).assemble(items)
        try makeWriter(fs).write(sorted, intoBundleAt: bundle)
        #expect(
            try titles(fs) == [
                "_under", "Alpha", "beta", "kit", "Kit", "Manual Tool", "Zeta", "zlib",
            ])
    }

    @Test("two runs on shuffled input write byte-identical files")
    func shuffledInputIsByteIdentical() throws {
        var generator = SeededGenerator(seed: 42)
        var outputs: [[String: Data]] = []
        for _ in 0..<5 {
            let fs = try freshFileSystem()
            let sorted = try AcknowledgementAssembler(slugger: OutputNameSlugger()).assemble(
                items.shuffled(using: &generator))
            try makeWriter(fs).write(sorted, intoBundleAt: bundle)
            var files: [String: Data] = [:]
            for path in try allPaths(fs, under: bundle) where fs.exists(at: path) {
                if let data = try? readBytes(fs, path) { files[path] = data }
            }
            outputs.append(files)
        }
        #expect(outputs[0].count == items.count + 2)
        for output in outputs.dropFirst() { #expect(output == outputs[0]) }
    }
}
