import DependiDomain
import DependiEntities
import DependiGenerate
import DependiTestSupport
import Foundation
import Testing

@Suite("Output location links")
struct OutputLinkTests {
    private func world() throws -> GenerateWorld {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        try world.files.addDirectory(at: "/products/App.app")
        return world
    }

    @Test("a link to a folder outside the product is refused before any write")
    func linkOutsideIsRefused() throws {
        let world = try world()
        try world.files.addDirectory(at: "/elsewhere")
        try world.files.addSymlink(
            at: "/products/App.app/Settings.bundle", pointingTo: "/elsewhere")
        #expect(
            throws: DomainError.invalidOutputLocation(
                path: "Settings.bundle",
                reason: "it is, or passes through, a link that leaves the product")
        ) { try world.run() }
        #expect(world.writer.calls.isEmpty)
    }

    @Test("a link to a folder inside the product is refused too")
    func linkInsideIsRefused() throws {
        let world = try world()
        try world.files.addDirectory(at: "/products/App.app/Real.bundle")
        try world.files.addSymlink(
            at: "/products/App.app/Settings.bundle", pointingTo: "/products/App.app/Real.bundle")
        #expect(throws: DomainError.self) { try world.run() }
        #expect(world.writer.calls.isEmpty)
    }

    @Test("a dangling link is refused")
    func danglingLinkIsRefused() throws {
        let world = try world()
        try world.files.addSymlink(
            at: "/products/App.app/Settings.bundle", pointingTo: "/nowhere")
        #expect(
            throws: DomainError.invalidOutputLocation(
                path: "Settings.bundle", reason: "it is a link that leads nowhere")
        ) { try world.run() }
        #expect(world.writer.calls.isEmpty)
    }

    @Test("a link in the middle of a custom output path is refused")
    func middleLinkIsRefused() throws {
        let world = try GenerateWorld(configuration: #"{"outputPath":"Res/Settings.bundle"}"#)
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        try world.files.addDirectory(at: "/elsewhere")
        try world.files.addDirectory(at: "/products/App.app")
        try world.files.addSymlink(at: "/products/App.app/Res", pointingTo: "/elsewhere")
        #expect(throws: DomainError.self) { try world.run() }
        #expect(world.writer.calls.isEmpty)
    }

    @Test("a link as the product folder is refused")
    func productRootLinkIsRefused() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        try world.files.addDirectory(at: "/elsewhere")
        try world.files.addSymlink(at: "/products/App.app", pointingTo: "/elsewhere")
        #expect(throws: DomainError.self) { try world.run() }
        #expect(world.writer.calls.isEmpty)
    }

    @Test("a plain existing bundle folder is accepted")
    func plainFolderIsAccepted() throws {
        let world = try world()
        try world.files.addDirectory(at: "/products/App.app/Settings.bundle")
        _ = try world.run()
        #expect(world.writer.calls.first?.bundlePath == "/products/App.app/Settings.bundle")
    }

    @Test("a missing bundle folder is accepted")
    func missingFolderIsAccepted() throws {
        let world = try world()
        _ = try world.run()
        #expect(world.writer.calls.count == 1)
    }

    @Test("a bundle path with dot components still compares equal to its real path")
    func dotComponentsAreAccepted() throws {
        let world = try GenerateWorld(configuration: #"{"outputPath":"./Res/./Settings.bundle"}"#)
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        try world.files.addDirectory(at: "/products/App.app/Res/Settings.bundle")
        _ = try world.run()
        #expect(world.writer.calls.first?.bundlePath == "/products/App.app/Res/Settings.bundle")
    }
}
