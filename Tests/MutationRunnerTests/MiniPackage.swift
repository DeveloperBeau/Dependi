import Foundation
import TestHelpers

/// A tiny package in its own git repository, used to run the mutation runner for real.
struct MiniPackage {
    let root: URL

    static let sourceText = """
        public func isEven(_ number: Int) -> Bool {
            number % 2 == 0
        }

        public func unusedValue() -> Int {
            return 7
        }

        public func countDown(_ start: Int) -> Int {
            var value = start
            while value > 0 {
                value -= 1
            }
            return value
        }

        """

    static let otherSourceText = """
        public func tripled(_ number: Int) -> Int {
            number * 3
        }

        """

    static let testText = """
        import Testing
        import Mini

        @Suite struct MiniTests {
            @Test func evenNumbersAreEven() {
                #expect(isEven(4))
                #expect(!isEven(3))
            }

            @Test func countDownReachesZero() {
                #expect(countDown(3) == 0)
            }

            @Test func brokenBaseline() {
                #expect(unusedValue() == 0)
            }

            @Test func evenNumbersAreEvenToo() {
                #expect(isEven(0))
            }

            @Test func sharedName() {
                #expect(isEven(2))
            }

            @Test func tripledTriples() {
                #expect(tripled(2) == 6)
            }
        }

        @Suite struct MiniOtherTests {
            @Test func sharedName() {
                #expect(Bool(true))
            }
        }

        """

    static let manifestText = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Mini",
            platforms: [.macOS(.v14)],
            targets: [
                .target(name: "Mini"),
                .testTarget(name: "MiniTests", dependencies: ["Mini"]),
            ]
        )

        """

    /// The one package folder that every runner test uses. It sits in the build folder, so it is
    /// git-ignored and `swift package clean` removes it. Its own build folder stays between tests,
    /// so each runner build is incremental instead of cold.
    static let sharedRoot = RepositoryRoot.url.appendingPathComponent(
        ".build/mutation-runner-fixture")

    /// Gives the shared package at the fixture commit with no other file. A tree that a
    /// test or an interrupted run left changed is reset. A fixture text that changed in this file
    /// makes a new package.
    static func create() throws -> MiniPackage {
        let package = MiniPackage(root: sharedRoot)
        if FileManager.default.fileExists(
            atPath: sharedRoot.appendingPathComponent(".git").path)
        {
            for command in [
                ["git", "reset", "-q", "--hard", "fixture"], ["git", "clean", "-fdq"],
            ] {
                let result = try ChildProcess.run(command, workingDirectory: sharedRoot)
                precondition(result.status == 0, "fixture reset failed: \(result.output)")
            }
            if try package.holdsFixtureText() { return package }
            try FileManager.default.removeItem(at: sharedRoot)
        }
        try write(at: sharedRoot)
        return package
    }

    private func holdsFixtureText() throws -> Bool {
        let expected = [
            "Package.swift": Self.manifestText, "Sources/Mini/Mini.swift": Self.sourceText,
            "Tests/MiniTests/MiniTests.swift": Self.testText,
            "Sources/Mini/Other.swift": Self.otherSourceText,
        ]
        for (path, text) in expected {
            let url = root.appendingPathComponent(path)
            if (try? String(contentsOf: url, encoding: .utf8)) != text { return false }
        }
        return true
    }

    private static func write(at root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Sources/Mini"), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Tests/MiniTests"), withIntermediateDirectories: true)
        try manifestText.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try sourceText.write(
            to: root.appendingPathComponent("Sources/Mini/Mini.swift"), atomically: true,
            encoding: .utf8)
        try otherSourceText.write(
            to: root.appendingPathComponent("Sources/Mini/Other.swift"), atomically: true,
            encoding: .utf8)
        try testText.write(
            to: root.appendingPathComponent("Tests/MiniTests/MiniTests.swift"), atomically: true,
            encoding: .utf8)
        try ".build/\n".write(
            to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        for command in [
            ["git", "init", "-q"],
            ["git", "add", "-A"],
            [
                "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "-q", "-m", "fixture",
            ],
            ["git", "tag", "fixture"],
        ] {
            let result = try ChildProcess.run(command, workingDirectory: root)
            precondition(result.status == 0, "fixture setup failed: \(result.output)")
        }
    }

    var sourceURL: URL { root.appendingPathComponent("Sources/Mini/Mini.swift") }

    var otherSourceURL: URL { root.appendingPathComponent("Sources/Mini/Other.swift") }

    /// Commits the working tree, for a test that needs history.
    func commitAll(message: String) throws {
        for command in [
            ["git", "add", "-A"],
            [
                "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "-q", "-m", message,
            ],
        ] {
            let result = try ChildProcess.run(command, workingDirectory: root)
            precondition(result.status == 0, "fixture commit failed: \(result.output)")
        }
    }

    /// The worker copy folders that the runner made in the temporary folder.
    static func workerFolders() throws -> Set<String> {
        Set(
            try FileManager.default.contentsOfDirectory(
                atPath: FileManager.default.temporaryDirectory.path
            ).filter { $0.hasPrefix("mutate-worker-") })
    }

    func sourceText() throws -> String { try String(contentsOf: sourceURL, encoding: .utf8) }

    func gitStatus() throws -> String {
        try ChildProcess.run(["git", "status", "--porcelain"], workingDirectory: root).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lists running processes whose command line mentions the given text.
    static func processes(mentioning text: String) throws -> [String] {
        let table = try ChildProcess.run(
            ["ps", "-axo", "pid=,command="],
            workingDirectory: FileManager.default.temporaryDirectory
        ).output
        return table.split(separator: "\n").map(String.init).filter {
            $0.contains(text) && !$0.contains("ps -axo")
        }
    }
}
