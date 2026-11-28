import DependiDomain
import DependiPackageGraph
import DependiTestSupport
import Foundation
import Testing

@Suite("Package graph manifest name", .timeLimit(.minutes(1)))
struct PackageGraphNameTests {
    private func dump(name: String?) -> Data {
        let field = name.map { "\"name\": \($0)," } ?? ""
        return Data("{ \(field) \"products\": [], \"targets\": [] }".utf8)
    }

    private func read(_ data: Data) throws -> PackageManifest {
        let files = try GraphTestSupport.files()
        let runner = FakeProcessRunner(results: [GraphTestSupport.success(data)])
        return try GraphTestSupport.reader(files: files, runner: runner).manifest(
            atPackagePath: GraphTestSupport.packagePath)
    }

    @Test("the top level name of the dump is the manifest name")
    func nameIsRead() throws {
        #expect(try read(dump(name: "\"SQLite.swift\"")).name == "SQLite.swift")
        #expect(try read(dump(name: "\"Key chain (Swift) é\"")).name == "Key chain (Swift) é")
    }

    @Test("a dump with no name gives a manifest with no name")
    func nameMissing() throws {
        #expect(try read(dump(name: nil)).name == nil)
    }

    @Test("a name that is not a string gives a manifest with no name and does not fail")
    func nameNotAString() throws {
        for raw in ["5", "null", "[\"Kit\"]", "{\"a\": 1}", "true"] {
            #expect(try read(dump(name: raw)).name == nil, "name \(raw)")
        }
    }

    @Test("the name of a target or a product is not taken for the manifest name")
    func nestedNamesAreIgnored() throws {
        let data = Data(
            #"{"products":[{"name":"Product","targets":["T"]}],"targets":[{"name":"T","type":"regular"}]}"#
                .utf8)
        #expect(try read(data).name == nil)
    }

    @Test("an older cache entry with no name reads back with no name and no failure")
    func olderCacheEntryWithNoName() throws {
        let files = try GraphTestSupport.files()
        let first = FakeProcessRunner(results: [GraphTestSupport.success(dump(name: nil))])
        _ = try GraphTestSupport.reader(files: files, runner: first).manifest(
            atPackagePath: GraphTestSupport.packagePath)
        let second = FakeProcessRunner(results: [])
        let cached = try GraphTestSupport.reader(files: files, runner: second).manifest(
            atPackagePath: GraphTestSupport.packagePath)
        #expect(second.requests.isEmpty)
        #expect(cached.name == nil)
    }

    @Test("a cache entry that holds a name gives the name without running the process")
    func cacheEntryWithName() throws {
        let files = try GraphTestSupport.files()
        let first = FakeProcessRunner(results: [
            GraphTestSupport.success(dump(name: "\"RevenueCat\""))
        ])
        _ = try GraphTestSupport.reader(files: files, runner: first).manifest(
            atPackagePath: GraphTestSupport.packagePath)
        let second = FakeProcessRunner(results: [])
        let cached = try GraphTestSupport.reader(files: files, runner: second).manifest(
            atPackagePath: GraphTestSupport.packagePath)
        #expect(second.requests.isEmpty)
        #expect(cached.name == "RevenueCat")
    }
}
