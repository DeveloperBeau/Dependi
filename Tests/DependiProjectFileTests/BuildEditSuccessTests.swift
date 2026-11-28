import DependiDomain
import DependiProjectFile
import Foundation
import Testing

@Suite("Project file editor success", .timeLimit(.minutes(1)))
struct BuildEditSuccessTests {
    /// The lines of the new Dependi phase, written by hand for one id.
    private static func phaseLines(id: String) -> [String] {
        [
            "\t\t\(id) /* Dependi */ = {",
            "\t\t\tisa = PBXShellScriptBuildPhase;",
            "\t\t\tbuildActionMask = 2147483647;",
            "\t\t\tfiles = (",
            "\t\t\t);",
            "\t\t\tinputFileListPaths = (",
            "\t\t\t\t\"$(SRCROOT)/.dependi/inputs.xcfilelist\",",
            "\t\t\t);",
            "\t\t\tinputPaths = (",
            "\t\t\t);",
            "\t\t\tname = Dependi;",
            "\t\t\toutputFileListPaths = (",
            "\t\t\t);",
            "\t\t\toutputPaths = (",
            "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist\",",
            "\t\t\t);",
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
            "\t\t\tshellPath = /bin/sh;",
            "\t\t\tshellScript = \"\\\"${SRCROOT}/.dependi/run.sh\\\" generate\\n\";",
            "\t\t};",
        ]
    }

    private static let sandboxLine = "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;"

    @Test("Mew gets all three steps and the new lines match the hand-written ones")
    func mewGetsAllThreeSteps() throws {
        let world = try EditWorld("old-format-mew")
        let lines = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(
            lines == [
                "Dependi: added the file reference Settings.bundle (Settings.bundle) to the main group.",
                "Dependi: added Settings.bundle to Copy Bundle Resources of MewTestsApp.",
                "Dependi: added the Dependi Run Script phase after Copy Bundle Resources of MewTestsApp.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Debug of MewTestsApp.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Release of MewTestsApp.",
                "Dependi: backup of the original project file is at /work/App/.dependi/project.pbxproj.bak.",
            ])
        let added = assertOnlyAdded(
            before: String(decoding: world.original, as: UTF8.self), after: try world.currentText())
        let expected =
            [
                "\t\t76C979CC1790CDFA3037B5DC /* Settings.bundle in Resources */ = {isa = PBXBuildFile; fileRef = 3F3B65923D016048D4FAF971 /* Settings.bundle */; };",
                "\t\t3F3B65923D016048D4FAF971 /* Settings.bundle */ = {isa = PBXFileReference; lastKnownFileType = \"wrapper.plug-in\"; path = Settings.bundle; sourceTree = SOURCE_ROOT; };",
                "\t\t\t\t3F3B65923D016048D4FAF971 /* Settings.bundle */,",
                "\t\t\t\t2753DE8B26A7EEA90771BF6B /* Dependi */,",
                "\t\t\t\t76C979CC1790CDFA3037B5DC /* Settings.bundle in Resources */,",
                "",
                "/* Begin PBXShellScriptBuildPhase section */",
            ] + Self.phaseLines(id: "2753DE8B26A7EEA90771BF6B") + [
                "/* End PBXShellScriptBuildPhase section */",
                "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;",
                "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;",
            ]
        #expect(Set(added) == Set(expected))
        #expect(added.count == expected.count)
        let text = try world.currentText()
        let resources = try #require(text.range(of: "D2568DEA214BCA3B00FCA44A /* Resources */ = {"))
        #expect(text[resources.upperBound...].prefix(400).contains("Settings.bundle in Resources"))
        #expect(
            text.contains(
                "D2568DEA214BCA3B00FCA44A /* Resources */,\n\t\t\t\t2753DE8B26A7EEA90771BF6B /* Dependi */,\n"
            ))
        // The new section goes between the sections that sort around its name.

        #expect(
            text.contains(
                "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXShellScriptBuildPhase section */\n"
            ))
        #expect(
            text.contains(
                "/* End PBXShellScriptBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */\n"
            ))
        #expect(
            world.writer.records == [
                "mkdir /work/App/.dependi",
                "write /work/App/.dependi/project.pbxproj.bak",
                "write /work/App/App.xcodeproj/project.pbxproj.dependi-new",
                "move /work/App/App.xcodeproj/project.pbxproj.dependi-new to /work/App/App.xcodeproj/project.pbxproj",
            ])
    }

    @Test("a dry run reports the same lines and writes nothing")
    func dryRunWritesNothing() throws {
        let real = try EditWorld("old-format-mew")
        let dry = try EditWorld("old-format-mew")
        let expected = try real.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        let lines = try dry.configure(
            target: "MewTestsApp", bundle: "Settings.bundle", isDryRun: true)
        #expect(lines == expected)
        #expect(dry.writer.records.isEmpty)
        #expect(try dry.currentBytes() == dry.original)
    }

    @Test("a bundle in a synchronized folder gets only the phase and the setting")
    func filaAddsNoReference() throws {
        let world = try EditWorld("synchronized-fila")
        let lines = try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        #expect(lines.count == 4)
        #expect(lines[0].contains("Run Script phase"))
        #expect(
            lines.allSatisfy {
                !$0.contains("file reference") && !$0.contains("Copy Bundle Resources of")
                    || $0.contains("Run Script")
            })
        let added = assertOnlyAdded(
            before: String(decoding: world.original, as: UTF8.self), after: try world.currentText())
        #expect(!added.contains { $0.contains("PBXBuildFile") || $0.contains("PBXFileReference") })
        let expected =
            ["\t\t\t\tD4B70E90F7363348AA99C94E /* Dependi */,"]
            + Self.phaseLines(id: "D4B70E90F7363348AA99C94E") + [
                Self.sandboxLine, Self.sandboxLine,
            ]
        #expect(Set(added) == Set(expected))
        #expect(added.count == expected.count)
    }

    @Test(
        "a bundle in a folder next to the synchronized folder still gets a reference and a copy entry"
    )
    func filaSiblingFolderIsNotCovered() throws {
        let world = try EditWorld("synchronized-fila")
        let lines = try world.configure(target: "Fila", bundle: "FilaExtras/Settings.bundle")
        #expect(
            lines == [
                "Dependi: added the file reference Settings.bundle (FilaExtras/Settings.bundle) to the main group.",
                "Dependi: added Settings.bundle to Copy Bundle Resources of Fila.",
                "Dependi: added the Dependi Run Script phase after Copy Bundle Resources of Fila.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Debug of Fila.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Release of Fila.",
                "Dependi: backup of the original project file is at /work/App/.dependi/project.pbxproj.bak.",
            ])
        let added = assertOnlyAdded(
            before: String(decoding: world.original, as: UTF8.self), after: try world.currentText())
        let expected =
            [
                "\t\tD8D171BBB09BB43C74768155 /* Settings.bundle in Resources */ = {isa = PBXBuildFile; fileRef = 588A91F81B5940BC0126D64A /* Settings.bundle */; };",
                "\t\t588A91F81B5940BC0126D64A /* Settings.bundle */ = {isa = PBXFileReference; lastKnownFileType = \"wrapper.plug-in\"; name = Settings.bundle; path = FilaExtras/Settings.bundle; sourceTree = SOURCE_ROOT; };",
                "\t\t\t\t588A91F81B5940BC0126D64A /* Settings.bundle */,",
                "\t\t\t\tD4B70E90F7363348AA99C94E /* Dependi */,",
                "\t\t\t\tD8D171BBB09BB43C74768155 /* Settings.bundle in Resources */,",
            ] + Self.phaseLines(id: "D4B70E90F7363348AA99C94E") + [
                Self.sandboxLine, Self.sandboxLine,
            ]
        #expect(Set(added) == Set(expected))
        #expect(added.count == expected.count)
    }

    @Test("ids that the project text already holds in a comment are not used again")
    func idsInACommentAreSkipped() throws {
        let taken = [
            "76C979CC1790CDFA3037B5DC", "3F3B65923D016048D4FAF971", "2753DE8B26A7EEA90771BF6B",
        ]
        let source = replacing(
            String(decoding: FixtureWorld.fixture("old-format-mew"), as: UTF8.self),
            "\tarchiveVersion = 1;\n",
            with: "\t/* \(taken.joined(separator: " ")) */\n\tarchiveVersion = 1;\n")
        let world = try EditWorld("x", bytes: Data(source.utf8))
        let lines = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(lines.count == 6)
        let text = try world.currentText()
        func count(_ id: String) -> Int { text.components(separatedBy: id).count - 1 }
        for id in taken { #expect(count(id) == 1, "\(id)") }
        // The next id for each role: the file reference, the build file and the phase.
        let made = [
            "DE1BF51D55BE617187F3A756": 3, "4EE5B9DD737E9DCC7D176091": 2,
            "B3E12B5716B67B90F2B9B159": 2,
        ]
        for (id, times) in made {
            #expect(count(id) == times, "\(id)")
            #expect(id.count == 24 && id.allSatisfy { "0123456789ABCDEF".contains($0) })
            #expect(!taken.contains(id))
        }
    }

    @Test("a second app target is edited and the first stays as it was")
    func filaSecondAppTarget() throws {
        let world = try EditWorld("synchronized-fila")
        try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        let afterFirst = try world.currentText()
        let lines = try world.configure(target: "FilaSandboxed", bundle: "Fila/Settings.bundle")
        #expect(lines.contains { $0.contains("FilaSandboxed") })
        #expect(lines.allSatisfy { !$0.contains("of Fila.") && !$0.contains("of Fila ") })
        assertOnlyAdded(before: afterFirst, after: try world.currentText())
    }

    @Test("an existing resource stays and the phase and the setting are added")
    func overlandKeepsExistingResource() throws {
        let world = try EditWorld("settings-bundle-overland")
        let lines = try world.configure(target: "Overland", bundle: "GPSLogger/Settings.bundle")
        #expect(lines.filter { $0.contains("Settings.bundle") }.isEmpty)
        #expect(lines.contains { $0.contains("Run Script phase") })
        let added = assertOnlyAdded(
            before: String(decoding: world.original, as: UTF8.self), after: try world.currentText())
        let expected =
            ["\t\t\t\t634792559B7D869A61B96187 /* Dependi */,"]
            + Self.phaseLines(id: "634792559B7D869A61B96187")
        #expect(Set(added) == Set(expected))
        #expect(added.count == expected.count)
    }

    @Test("a setting that comes from a configuration file is overridden and the note says so")
    func xcconfigGetsOverrideNote() throws {
        let text = String(decoding: FixtureWorld.fixture("settings-bundle-overland"), as: UTF8.self)
        let line = "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n"
        let bare = replacing(
            text, line, with: "", times: text.components(separatedBy: line).count - 1)
        let world = try EditWorld("x", bytes: Data(bare.utf8))
        let lines = try world.configure(target: "Overland", bundle: "GPSLogger/Settings.bundle")
        #expect(
            lines.contains(
                "Dependi: the value in the xcconfig file is now overridden for Overland."))
    }

    @Test("a setting that is only at project level gets a target level setting")
    func keyboardKitInsertsTargetLevelSetting() throws {
        let world = try EditWorld("multiple-targets-keyboardkit")
        let lines = try world.configure(
            target: "KeyboardKitDemo", bundle: "KeyboardKitDemo/Settings.bundle")
        #expect(lines.filter { $0.contains("ENABLE_USER_SCRIPT_SANDBOXING = NO") }.count == 2)
        let added = assertOnlyAdded(
            before: String(decoding: world.original, as: UTF8.self), after: try world.currentText())
        #expect(added.filter { $0 == "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;" }.count == 2)
        let expected =
            ["\t\t\t\tAB89770312B31623E747CA7D /* Dependi */,"]
            + Self.phaseLines(id: "AB89770312B31623E747CA7D") + [
                Self.sandboxLine, Self.sandboxLine,
            ]
        #expect(Set(added) == Set(expected))
        #expect(added.count == expected.count)
    }

    @Test("each app target of one project can be chosen and the others stay unchanged")
    func keyboardKitEachApp() throws {
        for target in ["KeyboardKitDemo", "KeyboardKitClassicDemo", "KeyboardKitUITestsHost"] {
            let world = try EditWorld("multiple-targets-keyboardkit")
            let lines = try world.configure(
                target: target, bundle: "KeyboardKitDemo/Settings.bundle")
            #expect(lines.contains { $0.contains("of \(target).") }, "\(target)")
            #expect(lines.allSatisfy { !$0.contains(" of KeyboardKit.") })
        }
    }

    @Test("a bundle that the target already copies is not added again")
    func existingResourceIsNotAddedAgain() throws {
        let world = try EditWorld("folder-reference-twittertexteditor")
        let lines = try world.configure(
            target: "Example", bundle: "Example/Resources/Settings.bundle")
        #expect(
            lines.allSatisfy {
                !$0.contains("Copy Bundle Resources of") || $0.contains("Run Script")
            })
        let added = assertOnlyAdded(
            before: String(decoding: world.original, as: UTF8.self), after: try world.currentText())
        #expect(added.filter { $0.contains("Settings.bundle") }.count == 1)
        let expected =
            [
                "\t\t\t\t387834CB168FA33CA67DCEFE /* Dependi */,",
                "",
                "/* Begin PBXShellScriptBuildPhase section */",
            ] + Self.phaseLines(id: "387834CB168FA33CA67DCEFE") + [
                "/* End PBXShellScriptBuildPhase section */", Self.sandboxLine, Self.sandboxLine,
            ]
        #expect(Set(added) == Set(expected))
        #expect(added.count == expected.count)
    }

    @Test("a reference that is not in the target is reused")
    func existingReferenceOutsideTargetIsReused() throws {
        let text = String(
            decoding: FixtureWorld.fixture("folder-reference-twittertexteditor"), as: UTF8.self)
        let removed = replacing(
            text, "\t\t\t\t54884C7024ABCC6B00D56C95 /* Settings.bundle in Resources */,\n", with: ""
        )
        let world = try EditWorld("x", bytes: Data(removed.utf8))
        let lines = try world.configure(
            target: "Example", bundle: "Example/Resources/Settings.bundle")
        #expect(
            lines.contains("Dependi: added Settings.bundle to Copy Bundle Resources of Example."))
        #expect(!lines.contains { $0.contains("file reference") })
        let added = assertOnlyAdded(before: removed, after: try world.currentText())
        #expect(added.filter { $0.contains("isa = PBXFileReference") }.isEmpty)
        #expect(
            added.contains {
                $0.contains("fileRef = 54884C6F24ABCC6B00D56C95 /* Settings.bundle */")
            })
    }

    @Test("a folder reference that is not the bundle does not count as a resource")
    func folderReferenceDoesNotCount() throws {
        let text = String(
            decoding: FixtureWorld.fixture("folder-reference-twittertexteditor"), as: UTF8.self)
        let folder = replacing(
            text, "lastKnownFileType = \"wrapper.plug-in\"; path = Settings.bundle;",
            with: "lastKnownFileType = folder; path = Settings.bundle;")
        let world = try EditWorld("x", bytes: Data(folder.utf8))
        let lines = try world.configure(
            target: "Example", bundle: "Example/Resources/Settings.bundle")
        #expect(
            lines.contains {
                $0.contains(
                    "added the file reference Settings.bundle (Example/Resources/Settings.bundle)")
            })
    }

    @Test("a bundle one folder down gets a project relative path")
    func bundleOneFolderDown() throws {
        let world = try EditWorld("old-format-mew")
        try world.configure(target: "MewTestsApp", bundle: "App/Settings.bundle")
        #expect(
            try world.currentText().contains(
                "name = Settings.bundle; path = App/Settings.bundle; sourceTree = SOURCE_ROOT;"))
    }

    @Test("a path with a space is quoted")
    func spaceInPathIsQuoted() throws {
        let world = try EditWorld("old-format-mew")
        try world.configure(target: "MewTestsApp", bundle: "My App/Settings.bundle")
        #expect(try world.currentText().contains("path = \"My App/Settings.bundle\";"))
    }

    @Test("a quoted NO counts as done and an unquoted YES is replaced in place")
    func quotedNoAndReplacedYes() throws {
        let world = try EditWorld("settings-bundle-overland")
        try world.configure(target: "Overland", bundle: "GPSLogger/Settings.bundle")
        let done = try world.currentText()
        let line = "ENABLE_USER_SCRIPT_SANDBOXING = NO;"
        let count = done.components(separatedBy: line).count - 1
        #expect(count >= 2)
        let quoted = replacing(
            done, line, with: "ENABLE_USER_SCRIPT_SANDBOXING = \"NO\";", times: count)
        let quotedWorld = try EditWorld("x", bytes: Data(quoted.utf8))
        #expect(
            try quotedWorld.configure(target: "Overland", bundle: "GPSLogger/Settings.bundle") == []
        )
        #expect(quotedWorld.writer.records.isEmpty)
        let yes = replacing(done, line, with: "ENABLE_USER_SCRIPT_SANDBOXING = YES;", times: count)
        let yesWorld = try EditWorld("x", bytes: Data(yes.utf8))
        let lines = try yesWorld.configure(target: "Overland", bundle: "GPSLogger/Settings.bundle")
        #expect(lines.filter { $0.hasSuffix("(was YES).") }.count == 2)
        let yesLine = "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;"
        let added = assertOnlyAdded(
            before: yes, after: try yesWorld.currentText(), replaced: [yesLine, yesLine])
        #expect(
            added == [
                "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;",
                "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;",
            ])
    }

    @Test("a Dependi phase before Copy Bundle Resources is kept and reported")
    func phaseBeforeResourcesIsKept() throws {
        let world = try EditWorld("old-format-mew")
        try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        let phase = "\t\t\t\t2753DE8B26A7EEA90771BF6B /* Dependi */,\n"
        let resources = "\t\t\t\tD2568DEA214BCA3B00FCA44A /* Resources */,\n"
        var broken = replacing(try world.currentText(), phase, with: "")
        broken = replacing(broken, resources, with: phase + resources)
        let moved = try EditWorld("x", bytes: Data(broken.utf8))
        let lines = try moved.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(lines.count == 1)
        #expect(lines[0].contains("runs before Copy Bundle Resources"))
        #expect(moved.writer.records.isEmpty)
    }

    @Test("a project file that is a link is edited at its real path")
    func linkedProjectFile() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addDirectory(at: "/store")
        try world.files.addFile(at: "/store/project.pbxproj", contents: world.original)
        try world.files.removeItem(at: EditWorld.projectFile)
        try world.files.addSymlink(at: EditWorld.projectFile, pointingTo: "/store/project.pbxproj")
        try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(
            world.writer.records.contains(
                "move /store/project.pbxproj.dependi-new to /store/project.pbxproj"))
        let stored = try world.files.readRegularFile(
            at: "/store/project.pbxproj", upToBytes: Int.max)
        #expect(stored != world.original)
        let backup = try world.files.readRegularFile(at: EditWorld.backup, upToBytes: Int.max)
        #expect(backup == world.original)
    }

    @Test("a missing backup folder is created before the backup and the edit are written")
    func missingBackupFolderIsCreated() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.removeItem(at: EditWorld.appFolder + "/.dependi")
        try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(
            world.writer.records == [
                "mkdir /work/App/.dependi",
                "write /work/App/.dependi/project.pbxproj.bak",
                "write /work/App/App.xcodeproj/project.pbxproj.dependi-new",
                "move /work/App/App.xcodeproj/project.pbxproj.dependi-new to /work/App/App.xcodeproj/project.pbxproj",
            ])
        let backup = try world.files.readRegularFile(at: EditWorld.backup, upToBytes: Int.max)
        #expect(backup == world.original)
        #expect(try world.currentBytes() != world.original)
    }

    @Test("every fixture is still readable by the project reader after the edit")
    func editedFixturesStillLoad() throws {
        for item in EditCase.all {
            let world = try EditWorld(item.fixture)
            try world.configure(target: item.target, bundle: item.bundle)
            let reader = ProjectFileReader(files: world.files)
            let targets = try reader.applicationTargets(projectFilePath: EditWorld.projectFolder)
            #expect(targets.contains(item.target), "\(item.fixture)")
        }
    }

    @Test("the phase goes right after Copy Bundle Resources, not at the end")
    func phaseGoesRightAfterResources() throws {
        let world = try EditWorld("synchronized-fila")
        try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        let text = try world.currentText()
        let resources = "\t\t\t\tFA0000000000000000000042 /* Resources */,\n\t\t\t\t"
        let range = try #require(text.range(of: resources))
        #expect(text[range.upperBound...].prefix(60).contains("/* Dependi */"))
    }

    @Test("a path with a quote, a backslash or a comment opener is quoted and escaped")
    func awkwardPaths() throws {
        for (folder, written) in [
            ("A\"B", "\"A\\\"B/Settings.bundle\""),
            ("A\\B", "\"A\\\\B/Settings.bundle\""),
            ("a/*b", "\"a/*b/Settings.bundle\""),
        ] {
            let world = try EditWorld("old-format-mew")
            try world.configure(target: "MewTestsApp", bundle: folder + "/Settings.bundle")
            #expect(try world.currentText().contains("path = \(written);"), "\(folder)")
        }
    }

    @Test("a build file with no file reference is ignored")
    func buildFileWithoutReference() throws {
        let text = String(decoding: FixtureWorld.fixture("old-format-mew"), as: UTF8.self)
        var changed = replacing(
            text, "/* Begin PBXBuildFile section */\n",
            with:
                "/* Begin PBXBuildFile section */\n\t\tD2568DFF214BCA3B00FCA44A /* (null) in Resources */ = {isa = PBXBuildFile; };\n"
        )
        changed = replacing(
            changed, "\t\t\t\tD2568DF4214BCA3B00FCA44A /* Main.storyboard in Resources */,\n",
            with:
                "\t\t\t\tD2568DFF214BCA3B00FCA44A /* (null) in Resources */,\n\t\t\t\tD2568DF4214BCA3B00FCA44A /* Main.storyboard in Resources */,\n"
        )
        let world = try EditWorld("x", bytes: Data(changed.utf8))
        let lines = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(
            lines.contains(
                "Dependi: added Settings.bundle to Copy Bundle Resources of MewTestsApp."))
    }

    @Test("a setting that comes from a configuration anchor is overridden and the note says so")
    func xcconfigAnchorGetsOverrideNote() throws {
        let text = String(decoding: FixtureWorld.fixture("settings-bundle-overland"), as: UTF8.self)
        let line = "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n"
        var changed = replacing(
            text, line, with: "", times: text.components(separatedBy: line).count - 1)
        changed = changed.replacingOccurrences(
            of: "baseConfigurationReference =", with: "baseConfigurationReferenceAnchor =")
        let world = try EditWorld("x", bytes: Data(changed.utf8))
        let lines = try world.configure(target: "Overland", bundle: "GPSLogger/Settings.bundle")
        #expect(
            lines.contains(
                "Dependi: the value in the xcconfig file is now overridden for Overland."))
    }
}
