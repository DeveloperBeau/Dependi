import DependiDomain
import DependiEntities
import DependiInit
import DependiTestSupport
import Foundation
import TestHelpers
import Testing

@Suite("Init feature", .timeLimit(.minutes(1)))
struct InitFeatureTests {
    // MARK: A fresh install

    @Test("a fresh project gets the configuration, the pane, the tool files and the ignore rule")
    func freshInstall() throws {
        let world = try InitWorld()
        world.localPaths = ["/proj/Packages/Core", "/elsewhere/Kit"]
        #expect(try world.run() == .installed)

        let config = try JSONDecoder().decode(
            ToolConfiguration.self, from: try world.data("/proj/.dependi.json"))
        #expect(config.excludes == ["core"])
        #expect(config.version == "0.1.0")
        #expect(config.commit == InitWorld.commit)
        #expect(config.gateConfigurations == ["Release"])

        let specifiers = try world.specifiers("/proj/Settings.bundle/Root.plist")
        #expect(
            specifiers == [
                [
                    "Type": "PSChildPaneSpecifier", "Title": "Acknowledgements",
                    "File": "Acknowledgements",
                ]
            ])

        #expect(try world.text("/proj/.dependi/bin/dependi") == "BINARY")
        #expect(world.files.isExecutable(at: "/proj/.dependi/bin/dependi"))
        #expect(try world.text("/proj/.dependi/bin/VERSION") == "0.1.0\n")
        #expect(try world.text("/proj/.dependi/run.sh") == InitWorld.wrapper)
        #expect(world.files.isExecutable(at: "/proj/.dependi/run.sh"))
        #expect(
            try world.text("/proj/.dependi/inputs.xcfilelist")
                == """
                $(SRCROOT)/.dependi.json
                $(SRCROOT)/.dependi/run.sh
                $(SRCROOT)/.dependi/bin/VERSION
                $(PROJECT_FILE_PATH)/project.pbxproj
                $(PROJECT_FILE_PATH)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

                """)
        #expect(try world.text("/proj/.gitignore") == ".dependi/bin/\n")
        #expect(world.console.lines.contains("    \"${SRCROOT}/.dependi/run.sh\" generate"))
        #expect(world.console.lines.contains { $0.contains("ENABLE_USER_SCRIPT_SANDBOXING") })
        #expect(
            world.console.lines.contains {
                $0.contains("add /proj/Settings.bundle to your app target")
            })
    }

    @Test("the pinned commit comes from git in the Dependi source folder")
    func commitRequest() throws {
        let world = try InitWorld()
        _ = try world.run()
        let request = try #require(world.runner.requests.first)
        #expect(request.executable == "/usr/bin/git")
        #expect(request.arguments == ["-C", "/dependi-source", "rev-parse", "HEAD"])
        #expect(request.environment == ["PATH": "/usr/bin:/bin"])
    }

    @Test(
        "a missing source folder, a failing git or an odd answer leave the commit out with a note")
    func commitMissing() throws {
        for scenario in 0..<3 {
            let world = try InitWorld()
            switch scenario {
            case 0: world.sourceRoot = nil
            case 1: world.gitResult = .failure(.processFailed(command: "git", reason: "gone"))
            default:
                world.gitResult = .success(
                    ProcessOutput(
                        exitStatus: 0, standardOutput: Data("not a commit".utf8),
                        standardError: Data()))
            }
            _ = try world.run()
            let config = try JSONDecoder().decode(
                ToolConfiguration.self, from: try world.data("/proj/.dependi.json"))
            #expect(config.commit == nil, "scenario \(scenario)")
            #expect(config.version == "0.1.0")
            #expect(
                world.console.lines.contains { $0.contains("could not read the commit") },
                "scenario \(scenario)")
            if scenario == 0 { #expect(world.runner.requests.isEmpty) }
        }
    }

    // MARK: Dry run and reruns

    @Test("a dry run reports the plan, writes nothing and starts no process")
    func dryRun() throws {
        let world = try InitWorld()
        #expect(try world.run(dry: true) == .reported)
        for path in [
            "/proj/.dependi.json", "/proj/Settings.bundle", "/proj/.dependi", "/proj/.gitignore",
        ] {
            #expect(!world.files.exists(at: path), "\(path) exists")
        }
        #expect(world.runner.requests.isEmpty)
        #expect(world.console.lines.contains("Dry run. Nothing is changed. A real run would:"))
    }

    @Test("a second run keeps the configuration, adds no pane, no backup and no ignore line")
    func secondRunChangesNothingNew() throws {
        let world = try InitWorld()
        _ = try world.run()
        let config = try world.data("/proj/.dependi.json")
        let plist = try world.data("/proj/Settings.bundle/Root.plist")
        #expect(try world.run() == .installed)
        #expect(try world.data("/proj/.dependi.json") == config)
        #expect(try world.data("/proj/Settings.bundle/Root.plist") == plist)
        #expect(!world.files.exists(at: "/proj/.dependi/Root.plist.bak"))
        #expect(!world.files.exists(at: "/proj/Settings.bundle/Root.plist.bak"))
        #expect(try world.text("/proj/.gitignore") == ".dependi/bin/\n")
        #expect(world.console.lines.contains("Dependi: kept the existing .dependi.json."))
        #expect(
            world.console.lines.contains(
                "Dependi: Root.plist already has the Acknowledgements pane."))
    }

    @Test("an existing configuration is never overwritten")
    func existingConfigurationKept() throws {
        let world = try InitWorld()
        try world.files.addFile(
            at: "/proj/.dependi.json", contents: Data(#"{"excludes":["mine"]}"#.utf8))
        _ = try world.run()
        #expect(try world.text("/proj/.dependi.json") == #"{"excludes":["mine"]}"#)
    }

    // MARK: Root.plist

    private func writePlist(
        _ world: InitWorld, _ object: [String: Any],
        format: PropertyListSerialization.PropertyListFormat = .xml
    ) throws {
        try world.files.addDirectory(at: "/proj/Settings.bundle")
        let data = try PropertyListSerialization.data(
            fromPropertyList: object, format: format, options: 0)
        try world.files.addFile(at: "/proj/Settings.bundle/Root.plist", contents: data)
    }

    @Test(
        "the pane is appended after the existing entries, which keep their order, and a backup is written"
    )
    func paneAppended() throws {
        let world = try InitWorld()
        let first: [String: Any] = [
            "Type": "PSToggleSwitchSpecifier", "Title": "Sound", "Key": "sound",
        ]
        let second: [String: Any] = ["Type": "PSGroupSpecifier", "Title": "About"]
        try writePlist(world, ["StringsTable": "Root", "PreferenceSpecifiers": [first, second]])
        let before = try world.data("/proj/Settings.bundle/Root.plist")
        _ = try world.run()
        let specifiers = try world.specifiers("/proj/Settings.bundle/Root.plist")
        #expect(specifiers.map { $0["Title"] } == ["Sound", "About", "Acknowledgements"])
        #expect(specifiers.last?["File"] == "Acknowledgements")
        #expect(try world.data("/proj/.dependi/Root.plist.bak") == before)
        #expect(
            !world.files.exists(at: "/proj/Settings.bundle/Root.plist.bak"),
            "the backup would ship in the app")
        #expect(
            try world.plist("/proj/Settings.bundle/Root.plist")["StringsTable"] as? String == "Root"
        )
    }

    @Test("an old LicensePlist entry is rewritten in place with its other keys kept")
    func oldEntryRewritten() throws {
        let world = try InitWorld()
        let old: [String: Any] = [
            "Type": "PSChildPaneSpecifier", "Title": "Open Source",
            "File": "com.mono0926.LicensePlist",
        ]
        try writePlist(
            world,
            [
                "PreferenceSpecifiers": [
                    ["Type": "PSGroupSpecifier", "Title": "A"], old,
                    ["Type": "PSGroupSpecifier", "Title": "Z"],
                ]
            ])
        _ = try world.run()
        let specifiers = try world.specifiers("/proj/Settings.bundle/Root.plist")
        #expect(specifiers.map { $0["Title"] } == ["A", "Open Source", "Z"])
        #expect(specifiers[1]["File"] == "Acknowledgements")
        #expect(specifiers[1]["Type"] == "PSChildPaneSpecifier")
        #expect(world.console.lines.contains { $0.contains("old LicensePlist pane") })
    }

    @Test("a file name that only resembles the old LicensePlist name is not rewritten")
    func lookalikeNotRewritten() throws {
        let world = try InitWorld()
        let near: [String: Any] = [
            "Type": "PSChildPaneSpecifier", "Title": "Mine", "File": "com.mono0926.LicensePlist2",
        ]
        try writePlist(world, ["PreferenceSpecifiers": [near]])
        _ = try world.run()
        let specifiers = try world.specifiers("/proj/Settings.bundle/Root.plist")
        #expect(
            specifiers.map { $0["File"] } == ["com.mono0926.LicensePlist2", "Acknowledgements"])
    }

    @Test("a binary property list stays binary")
    func binaryFormatKept() throws {
        let world = try InitWorld()
        try writePlist(
            world, ["PreferenceSpecifiers": [["Type": "PSGroupSpecifier", "Title": "A"]]],
            format: .binary)
        _ = try world.run()
        let data = try world.data("/proj/Settings.bundle/Root.plist")
        #expect(data.prefix(6) == Data("bplist".utf8))
        #expect(try world.specifiers("/proj/Settings.bundle/Root.plist").count == 2)
    }

    @Test("a Root.plist that is not a dictionary property list is refused and left alone")
    func badRootPlist() throws {
        for content in [
            Data("not a plist".utf8),
            try PropertyListSerialization.data(
                fromPropertyList: ["a", "b"], format: .xml, options: 0),
        ] {
            let world = try InitWorld()
            try world.files.addDirectory(at: "/proj/Settings.bundle")
            try world.files.addFile(at: "/proj/Settings.bundle/Root.plist", contents: content)
            #expect(throws: DomainError.self) { try world.run() }
            #expect(try world.data("/proj/Settings.bundle/Root.plist") == content)
        }
    }

    @Test(
        "fuzz: the edited file has one Acknowledgements entry and every other entry in the same order"
    )
    func fuzzRootPlist() throws {
        var generator = SeededGenerator()
        for round in 0..<60 {
            let count = Int.random(in: 0...6, using: &generator)
            var entries: [[String: String]] = []
            for index in 0..<count {
                let file: String? = [
                    nil, "Other\(index)", "com.mono0926.LicensePlist", "Acknowledgements",
                ].randomElement(using: &generator)!
                var entry = ["Type": "PSChildPaneSpecifier", "Title": "T\(index)"]
                if let file { entry["File"] = file }
                entries.append(entry)
            }
            let world = try InitWorld()
            try writePlist(world, ["PreferenceSpecifiers": entries])
            _ = try world.run()
            let after = try world.specifiers("/proj/Settings.bundle/Root.plist")
            #expect(after.filter { $0["File"] == "Acknowledgements" }.count >= 1, "round \(round)")
            let hadNew = entries.contains { $0["File"] == "Acknowledgements" }
            let hadOld = entries.contains { $0["File"] == "com.mono0926.LicensePlist" }
            let expectedCount = entries.count + (hadNew || hadOld ? 0 : 1)
            #expect(after.count == expectedCount, "round \(round)")
            #expect(
                Array(after.prefix(entries.count)).map { $0["Title"] }
                    == entries.map { $0["Title"] }, "round \(round)")
        }
    }

    // MARK: Settings bundle location and clashes

    @Test("a settings bundle in a folder of the project is found and used")
    func bundleInSubfolder() throws {
        let world = try InitWorld()
        try world.files.addDirectory(at: "/proj/App/Settings.bundle")
        try world.files.addFile(
            at: "/proj/App/Settings.bundle/Root.plist",
            contents: try PropertyListSerialization.data(
                fromPropertyList: ["PreferenceSpecifiers": []], format: .xml, options: 0))
        _ = try world.run()
        #expect(try world.specifiers("/proj/App/Settings.bundle/Root.plist").count == 1)
        #expect(!world.files.exists(at: "/proj/Settings.bundle"))
    }

    @Test("two settings bundles ask which one to use")
    func twoBundlesAsk() throws {
        let world = try InitWorld()
        for folder in ["/proj/Settings.bundle", "/proj/App/Settings.bundle"] {
            try world.files.addDirectory(at: folder)
            try world.files.addFile(
                at: folder + "/Root.plist",
                contents: try PropertyListSerialization.data(
                    fromPropertyList: ["PreferenceSpecifiers": []], format: .xml, options: 0))
        }
        world.answers = [.choice(1)]
        _ = try world.run()
        #expect(world.console.questions == ["Which Settings.bundle?"])
        #expect(try world.specifiers("/proj/App/Settings.bundle/Root.plist").count == 1)
        #expect(try world.specifiers("/proj/Settings.bundle/Root.plist").isEmpty)
    }

    @Test("files that would clash are removed only after a yes")
    func clashesNeedConfirmation() throws {
        let world = try InitWorld()
        try writePlist(world, ["PreferenceSpecifiers": []])
        try world.files.addFile(
            at: "/proj/Settings.bundle/Acknowledgements.plist", contents: Data("x".utf8))
        try world.files.addDirectory(at: "/proj/Settings.bundle/com.mono0926.LicensePlist")
        try world.files.addFile(
            at: "/proj/Settings.bundle/Other.plist", contents: Data("keep".utf8))
        world.answers = [.confirmation(false), .confirmation(true)]
        _ = try world.run()
        #expect(world.files.exists(at: "/proj/Settings.bundle/Acknowledgements.plist"))
        #expect(!world.files.exists(at: "/proj/Settings.bundle/com.mono0926.LicensePlist"))
        #expect(world.files.exists(at: "/proj/Settings.bundle/Other.plist"))
        #expect(world.console.questions.count == 2)
    }

    @Test("the end of the input while asking about a clash stops the run and removes nothing")
    func clashPromptEnds() throws {
        let world = try InitWorld()
        try writePlist(world, ["PreferenceSpecifiers": []])
        try world.files.addFile(
            at: "/proj/Settings.bundle/Acknowledgements.plist", contents: Data("x".utf8))
        world.answers = []
        #expect(throws: DomainError.inputEnded) { try world.run() }
        #expect(world.files.exists(at: "/proj/Settings.bundle/Acknowledgements.plist"))
    }

    // MARK: Gitignore

    @Test("the ignore rule is added once and a missing final newline is handled")
    func gitignoreRules() throws {
        let world = try InitWorld()
        try world.files.addFile(at: "/proj/.gitignore", contents: Data(".build/".utf8))
        _ = try world.run()
        #expect(try world.text("/proj/.gitignore") == ".build/\n.dependi/bin/\n")
        let already = try InitWorld()
        try already.files.addFile(
            at: "/proj/.gitignore", contents: Data("a\n  .dependi/bin/  \nb\n".utf8))
        _ = try already.run()
        #expect(try already.text("/proj/.gitignore") == "a\n  .dependi/bin/  \nb\n")
        let similar = try InitWorld()
        try similar.files.addFile(at: "/proj/.gitignore", contents: Data(".dependi/bin\n".utf8))
        _ = try similar.run()
        #expect(try similar.text("/proj/.gitignore") == ".dependi/bin\n.dependi/bin/\n")
    }

    // MARK: Finding the project

    @Test("a project folder, a project file and a workspace next to a project all work")
    func projectForms() throws {
        for path in ["/proj", "/proj/App.xcodeproj", "/proj/App.xcworkspace"] {
            let world = try InitWorld()
            try world.files.addDirectory(at: "/proj/App.xcworkspace")
            #expect(try world.run(path) == .installed, "path \(path)")
            #expect(world.files.exists(at: "/proj/.dependi.json"), "path \(path)")
        }
    }

    @Test("a workspace without a project of the same name is refused")
    func workspaceWithoutProject() throws {
        let world = try InitWorld()
        try world.files.addDirectory(at: "/proj/Other.xcworkspace")
        #expect(throws: DomainError.self) { try world.run("/proj/Other.xcworkspace") }
    }

    @Test("two projects in a folder ask which one")
    func twoProjectsAsk() throws {
        let world = try InitWorld()
        try world.files.addDirectory(at: "/proj/Second.xcodeproj")
        world.answers = [.choice(1)]
        _ = try world.run()
        #expect(world.console.questions == ["Which project?"])
    }

    @Test("a Swift package, an empty folder and a missing path are refused")
    func notAProject() throws {
        let package = try InitWorld()
        try package.files.addDirectory(at: "/pkg")
        try package.files.addFile(at: "/pkg/Package.swift", contents: Data("// p".utf8))
        #expect(throws: DomainError.self) { try package.run("/pkg") }
        let empty = try InitWorld()
        try empty.files.addDirectory(at: "/empty")
        #expect(throws: DomainError.projectNotFound(path: "/empty")) { try empty.run("/empty") }
        #expect(throws: DomainError.projectNotFound(path: "/missing")) { try empty.run("/missing") }
    }

    @Test("the Dependi source folder itself is refused and nothing is written")
    func dependiItself() throws {
        let world = try InitWorld()
        try world.files.addDirectory(at: "/clone/Sources/DependiDomain")
        try world.files.addDirectory(at: "/clone/Dependi.xcodeproj")
        try world.files.addFile(at: "/clone/Package.swift", contents: Data("// d".utf8))
        #expect(
            throws: DomainError.initRefused(
                reason:
                    "this folder holds the Dependi source itself. Pass the folder of your app project."
            )
        ) {
            try world.run("/clone")
        }
        #expect(!world.files.exists(at: "/clone/.dependi.json"))
    }

    // MARK: Targets and platforms

    @Test("with two application targets the chosen one is read")
    func chooseTarget() throws {
        let world = try InitWorld()
        world.targets = ["App", "Pro"]
        world.answers = [.choice(1)]
        _ = try world.run()
        #expect(world.console.questions == ["Which application target shows the acknowledgements?"])
        #expect(world.linked.targetsAsked == ["Pro"])
    }

    @Test("a project with no application target is refused")
    func noApplicationTarget() throws {
        let world = try InitWorld()
        world.targets = []
        #expect(throws: DomainError.initRefused(reason: "the project has no application target.")) {
            try world.run()
        }
        #expect(!world.files.exists(at: "/proj/.dependi.json"))
    }

    @Test(
        "a macOS-only app is refused and a Catalyst, multi-platform or unknown platform app is accepted"
    )
    func platforms() throws {
        let mac = try InitWorld()
        mac.platforms = ["macosx"]
        #expect(
            throws: DomainError.initRefused(
                reason: "App is a macOS app. macOS apps have no Settings.bundle.")
        ) { try mac.run() }
        #expect(!mac.files.exists(at: "/proj/.dependi.json"))
        for platforms in [["macosx", "maccatalyst"], ["iphoneos", "macosx"], ["xros"], []] {
            let world = try InitWorld()
            world.platforms = platforms
            #expect(try world.run() == .installed, "platforms \(platforms)")
        }
    }
}
