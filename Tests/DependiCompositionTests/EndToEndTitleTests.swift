import Foundation
import Testing

@Suite("End to end package titles", .timeLimit(.minutes(5)))
struct EndToEndTitleTests {
    /// An app that links Alamofire. It depends on swift-log and on a package that is pinned by revision.
    private func world(configuration: String = "{}") throws -> EndToEndWorld {
        let world = try EndToEndWorld(configuration: configuration)
        try world.addRemote(
            "alamofire", owner: "Alamofire",
            manifest: EndToEndWorld.manifest(
                product: "Alamofire", dependencies: ["Logging", "Zebra"],
                declared: ["swift-log", "zebra"], name: "Alamofire"),
            version: "5.9.1")
        try world.addRemote(
            "swift-log", owner: "apple",
            manifest: EndToEndWorld.manifest(product: "Logging", name: "  swift-log "),
            version: "1.5.4")
        try world.addRemote(
            "zebra", owner: "stripes",
            manifest: EndToEndWorld.manifest(product: "Zebra", name: "AardvarkKit"), version: nil)
        return world
    }

    @Test("the index and the child panes carry the titles, sorted by title without case")
    func panesCarryTitles() throws {
        let world = try world()
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(
            try world.indexTitles() == ["AardvarkKit", "Alamofire (5.9.1)", "swift-log (1.5.4)"])
        let paneTitles = try world.files(in: "Acknowledgements").filter { $0.hasSuffix(".plist") }
            .map { try #require(world.plist("Acknowledgements/" + $0)["Title"] as? String) }
        #expect(
            paneTitles.sorted() == ["AardvarkKit", "Alamofire (5.9.1)", "swift-log (1.5.4)"])
    }

    @Test("a single page run groups the same titles in the same order")
    func singlePageCarriesTitles() throws {
        let world = try world(configuration: #"{"singlePage":true}"#)
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        let index = try world.plist("Acknowledgements.plist")
        let groups = try requireValue(index["PreferenceSpecifiers"] as? [[String: String]])
        #expect(
            groups == [
                [
                    "Type": "PSGroupSpecifier", "Title": "AardvarkKit",
                    "FooterText": "license of zebra",
                ],
                [
                    "Type": "PSGroupSpecifier", "Title": "Alamofire (5.9.1)",
                    "FooterText": "license of alamofire",
                ],
                [
                    "Type": "PSGroupSpecifier", "Title": "swift-log (1.5.4)",
                    "FooterText": "license of swift-log",
                ],
            ])
    }

    @Test("a second run gives the same titles")
    func titlesRepeat() throws {
        let world = try world()
        _ = try world.run()
        let first = try world.indexTitles()
        _ = try world.run()
        #expect(try world.indexTitles() == first)
    }
}
