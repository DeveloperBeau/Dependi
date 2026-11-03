import Foundation
import TestHelpers
import Testing

@Suite("Mutation runner", .serialized)
struct MutationRunnerTests {
    @Test("each outcome is reported: killed, survived, invalid and killed by timeout")
    func mixedRegisterReportsEachOutcome() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let before = try package.sourceText()
        let result = try RunnerBinary.run(
            on: package,
            register: Register.list([
                Register.killed, Register.survivor, Register.invalid, Register.looping,
            ]),
            extra: ["--timeout", "90"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("even-flip | KILLED |"))
        #expect(result.output.contains("unused | SURVIVED |"))
        #expect(result.output.contains("broken | INVALID |"))
        #expect(result.output.contains("loop | KILLED (TIMEOUT) |"))
        #expect(try package.sourceText() == before)
        #expect(try package.gitStatus().isEmpty)
    }

    @Test("a register where every mutant is killed exits zero")
    func allKilledExitsZero() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let result = try RunnerBinary.run(
            on: package, register: Register.list([Register.killed]), extra: ["--timeout", "90"])
        #expect(result.status == 0, "output: \(result.output)")
        #expect(result.output.contains("even-flip | KILLED |"))
    }

    @Test("a named test that fails on clean code is a baseline failure, not a kill")
    func baselineFailureIsReported() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let entry = Register.entry(
            id: "needs-baseline", search: "return 7", replace: "return 8", test: "brokenBaseline")
        let result = try RunnerBinary.run(
            on: package, register: Register.list([entry]), extra: ["--timeout", "90"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("needs-baseline | BASELINE FAILED"))
    }

    @Test("a test id that does not resolve is a register error and nothing is mutated")
    func unknownTestIsRegisterError() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let entry = Register.entry(
            id: "bad-test", search: "return 7", replace: "return 8", test: "noSuchTest")
        let result = try RunnerBinary.run(on: package, register: Register.list([entry]))
        #expect(result.status == 2)
        #expect(
            result.output.contains("REGISTER ERROR bad-test: test id noSuchTest does not resolve"))
        #expect(try package.gitStatus().isEmpty)
    }

    @Test("search text that occurs twice is a register error")
    func searchTwiceIsRegisterError() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let entry = Register.entry(id: "twice", search: "value", replace: "other")
        let result = try RunnerBinary.run(on: package, register: Register.list([entry]))
        #expect(result.status == 2)
        #expect(result.output.contains("twice: search text occurs"))
        #expect(result.output.contains("need 1"))
    }

    @Test("search text that does not occur is a register error")
    func searchMissingIsRegisterError() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let entry = Register.entry(id: "missing", search: "not in the file", replace: "x")
        let result = try RunnerBinary.run(on: package, register: Register.list([entry]))
        #expect(result.status == 2)
        #expect(result.output.contains("missing: search text occurs 0 times"))
    }

    @Test("a file outside Sources is a register error")
    func fileOutsideSourcesIsRegisterError() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        for file in [
            "Package.swift", "../Package.swift", "/etc/hosts", "Tests/MiniTests/MiniTests.swift",
        ] {
            let entry = Register.entry(id: "outside", search: "x", replace: "y", file: file)
            let result = try RunnerBinary.run(on: package, register: Register.list([entry]))
            #expect(result.status == 2, "file \(file)")
            #expect(
                result.output.contains("file must be a relative path under Sources/"),
                "file \(file)")
        }
    }

    @Test("a duplicate id and an unchanged replacement are register errors")
    func duplicateAndNoOpAreRegisterErrors() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let same = Register.entry(id: "same", search: "return 7", replace: "return 7")
        let result = try RunnerBinary.run(
            on: package, register: Register.list([same, same]))
        #expect(result.status == 2)
        #expect(result.output.contains("same: duplicate id"))
        #expect(result.output.contains("same: replacement equals search"))
    }

    @Test("a dirty working tree is refused")
    func dirtyTreeIsRefused() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        try (try package.sourceText() + "\n// edit\n").write(
            to: package.sourceURL, atomically: true, encoding: .utf8)
        let result = try RunnerBinary.run(on: package, register: Register.list([Register.killed]))
        #expect(result.status == 2)
        #expect(result.output.contains("the working tree is not clean"))
    }

    @Test("malformed registers are refused with a register message and no mutation")
    func malformedRegistersAreRefused() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let corpus = [
            "", "null", "{}", "[1,2]", "[{\"id\":\"a\"}]", "[{\"id\":\"a\",\"slice\":\"1\"",
            "not json", "[{\"id\":1,\"slice\":2,\"file\":3,\"search\":4,\"replace\":5,\"test\":6}]",
        ]
        for text in corpus {
            let result = try RunnerBinary.run(on: package, register: text)
            #expect(result.status == 2, "register: \(text)")
            #expect(result.output.contains("register"), "register: \(text)")
            #expect(try package.gitStatus().isEmpty, "register: \(text)")
        }
    }

    @Test("an interrupt during a mutant run restores the mutated file")
    func interruptRestoresFile() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let registerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("register-\(UUID().uuidString).json")
        try Register.list([Register.looping]).write(
            to: registerURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: registerURL) }

        let process = Process()
        process.executableURL = RunnerBinary.url
        process.arguments = [
            "--root", package.root.path, "--register", registerURL.path, "--timeout", "600",
        ]
        process.currentDirectoryURL = package.root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(180)
        var sawMutation = false
        while Date() < deadline, process.isRunning {
            if (try? package.sourceText().contains("value += 1")) == true {
                sawMutation = true
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        #expect(sawMutation, "the runner never applied the mutation")
        kill(process.processIdentifier, SIGINT)
        let exitDeadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.1) }
        #expect(!process.isRunning, "the runner did not stop after the interrupt")
        #expect(try package.sourceText() == MiniPackage.sourceText)
        #expect(try package.gitStatus().isEmpty)
    }

    @Test("the markdown page is generated from the register and sorted by id")
    func markdownIsGenerated() throws {
        let package = try MiniPackage.create()
        defer { package.remove() }
        let output = package.root.appendingPathComponent("page.md")
        let register = Register.list([Register.survivor, Register.killed])
        let result = try RunnerBinary.run(
            on: package, register: register, extra: ["--markdown", output.path])
        #expect(result.status == 0, "output: \(result.output)")
        let text = try String(contentsOf: output, encoding: .utf8)
        let rows = text.split(separator: "\n").filter {
            $0.hasPrefix("| even-flip") || $0.hasPrefix("| unused")
        }
        #expect(rows.count == 2)
        #expect(rows.first?.hasPrefix("| even-flip") == true)
    }

    @Test("the committed register page is the page generated from the committed register")
    func committedPageIsCurrent() throws {
        let root = RepositoryRoot.url
        let generated = FileManager.default.temporaryDirectory
            .appendingPathComponent("page-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: generated) }
        let result = try ChildProcess.run(
            [RunnerBinary.url.path, "--root", root.path, "--markdown", generated.path],
            workingDirectory: root)
        #expect(result.status == 0, "output: \(result.output)")
        let committed = try String(
            contentsOf: root.appendingPathComponent("Documentation/Registers/mutations.md"),
            encoding: .utf8)
        #expect(try String(contentsOf: generated, encoding: .utf8) == committed)
    }
}
