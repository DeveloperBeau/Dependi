import Foundation
import TestHelpers

/// A tiny package in a temporary git repository, used to run the mutation runner for real.
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

    /// Creates the package in a new temporary folder and commits it.
    static func create() throws -> MiniPackage {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mini-\(UUID().uuidString)")
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
        try testText.write(
            to: root.appendingPathComponent("Tests/MiniTests/MiniTests.swift"), atomically: true,
            encoding: .utf8)
        try ".build/\n".write(
            to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        let package = MiniPackage(root: root)
        for command in [
            ["git", "init", "-q"],
            ["git", "add", "-A"],
            [
                "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "-q", "-m", "fixture",
            ],
        ] {
            let result = try ChildProcess.run(command, workingDirectory: root)
            precondition(result.status == 0, "fixture setup failed: \(result.output)")
        }
        return package
    }

    var sourceURL: URL { root.appendingPathComponent("Sources/Mini/Mini.swift") }

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

    func remove() { try? FileManager.default.removeItem(at: root) }
}
