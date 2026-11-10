import Foundation
import TestHelpers
import Testing

@Suite("Mutation runner", .serialized, .timeLimit(.minutes(5)))
struct MutationRunnerTests {
    @Test("each outcome is reported: killed, survived, invalid and killed by timeout")
    func mixedRegisterReportsEachOutcome() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let before = try package.sourceText()
        let result = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([
                Register.killed, Register.survivor, Register.invalid, Register.looping,
            ]),
            extra: ["--timeout", Register.loopTimeout])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("even-flip | KILLED |"))
        #expect(result.output.contains("unused | SURVIVED |"))
        #expect(result.output.contains("broken | INVALID |"))
        #expect(result.output.contains("loop | KILLED (TIMEOUT) |"))
        #expect(result.output.contains("UNEXPECTED loop: the register expects killed"))
        #expect(try package.sourceText() == before)
        #expect(try package.gitStatus().isEmpty)
    }

    @Test("a timeout kill that the register does not declare fails the run")
    func undeclaredTimeoutFails() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([Register.looping]),
            extra: ["--timeout", Register.loopTimeout])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("UNEXPECTED loop"))
    }

    @Test("a timeout kill that the register declares passes")
    func declaredTimeoutPasses() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([Register.loopingExpectingTimeout]),
            extra: ["--timeout", Register.loopTimeout])
        #expect(result.status == 0, "output: \(result.output)")
        #expect(result.output.contains("loop | KILLED (TIMEOUT) |"))
        #expect(!result.output.contains("UNEXPECTED"))
    }

    @Test("an ordinary kill of an entry that expects a timeout fails the run")
    func killWhereTimeoutExpectedFails() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(
            id: "even-flip", search: "number % 2 == 0", replace: "number % 2 == 1",
            expected: "timeout")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]),
            extra: ["--timeout", "90"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("UNEXPECTED even-flip"))
    }

    @Test("an expected value other than killed or timeout is a register error")
    func unknownExpectationIsRegisterError() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(
            id: "odd", search: "return 7", replace: "return 8", expected: "survived")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]))
        #expect(result.status == 2)
        #expect(result.output.contains("odd: expected must be killed or timeout"))
    }

    @Test("a test name shared by two suites is a register error that names both")
    func ambiguousTestNameIsRegisterError() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(
            id: "shared", search: "number % 2 == 0", replace: "number % 2 == 1",
            test: "sharedName")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]))
        #expect(result.status == 2, "output: \(result.output)")
        #expect(result.output.contains("shared: test id sharedName is ambiguous"))
        #expect(result.output.contains("MiniTests/sharedName()"))
        #expect(result.output.contains("MiniOtherTests/sharedName()"))
        #expect(try package.gitStatus().isEmpty)
    }

    @Test("a suite-qualified test id picks one of two equal names and only that test runs")
    func qualifiedTestRunsOnlyThatTest() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let flip = "number % 2 == 0"
        let killedBy = Register.entry(
            id: "own", search: flip, replace: "number % 2 == 1",
            test: "MiniTests/sharedName()")
        let notKilledBy = Register.entry(
            id: "other", search: flip, replace: "number % 2 == 1",
            test: "MiniOtherTests/sharedName()")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([killedBy, notKilledBy]),
            extra: ["--timeout", "90"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("own | KILLED |"))
        #expect(result.output.contains("other | SURVIVED |"))
    }

    @Test("a test name that is only the start of another name does not run the other test")
    func prefixOfAnotherNameDoesNotMatch() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(
            id: "only-too", search: "number % 2 == 0", replace: "number != 0 && number % 2 == 0")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]),
            extra: ["--timeout", "90"])
        #expect(result.output.contains("only-too | SURVIVED |"), "output: \(result.output)")
    }

    @Test("the run writes its outcome into the register and leaves other text alone")
    func runRecordsLastRun() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let pretty = """
            [
              {
                "id": "even-flip",
                "slice": "test",
                "file": "Sources/Mini/Mini.swift",
                "search": "number % 2 == 0",
                "replace": "number % 2 == 1",
                "test": "evenNumbersAreEven"
              }
            ]
            """
        let outcome = try RunnerBinary.runReadingRegister(
            on: package, double: double, register: pretty, extra: ["--timeout", "90"])
        #expect(outcome.result.status == 0, "output: \(outcome.result.output)")
        let lines = outcome.register.split(separator: "\n").map(String.init)
        #expect(lines.contains("    \"test\": \"evenNumbersAreEven\","))
        let recorded = lines.first { $0.contains("\"lastRun\"") } ?? ""
        #expect(recorded.contains("\"outcome\": \"KILLED\""))
        let date = try #require(recorded.split(separator: "\"").dropFirst(5).first)
        #expect(date.count == 10 && date.dropFirst(4).first == "-")
        // A second run replaces the record instead of adding another.
        let again = try RunnerBinary.runReadingRegister(
            on: package, double: double, register: outcome.register, extra: ["--timeout", "90"])
        #expect(again.register.components(separatedBy: "lastRun").count == 2)
        _ = try JSONSerialization.jsonObject(with: Data(again.register.utf8))
    }

    @Test("a compact register stays valid json after a run is recorded")
    func compactRegisterIsRecorded() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let outcome = try RunnerBinary.runReadingRegister(
            on: package, double: double,
            register: Register.list([Register.killed, Register.survivor]),
            extra: ["--timeout", "90"])
        let objects = try #require(
            try JSONSerialization.jsonObject(with: Data(outcome.register.utf8))
                as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0["id"] as! String, $0) })
        let flip = byID["even-flip"]?["lastRun"] as? [String: String]
        let unused = byID["unused"]?["lastRun"] as? [String: String]
        #expect(flip?["outcome"] == "KILLED")
        #expect(unused?["outcome"] == "SURVIVED")
    }

    @Test("the no record option leaves the register untouched")
    func noRecordLeavesRegisterAlone() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let register = Register.list([Register.killed])
        let outcome = try RunnerBinary.runReadingRegister(
            on: package, double: double, register: register,
            extra: ["--timeout", "90", "--record", "no"])
        #expect(outcome.register == register)
    }

    @Test("the page shows the expected result and the last run")
    func markdownShowsExpectationAndLastRun() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let output = package.root.appendingPathComponent("page.md")
        let withRun =
            #"{"id":"a","slice":"1","file":"Sources/Mini/Mini.swift","search":"x","replace":"y","test":"t","expected":"timeout","lastRun":{"date":"2026-01-02","outcome":"KILLED (TIMEOUT)"}}"#
        let plain = Register.entry(id: "b", search: "x", replace: "y", test: "t")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([withRun, plain]),
            extra: ["--markdown", output.path])
        #expect(result.status == 0, "output: \(result.output)")
        let text = try String(contentsOf: output, encoding: .utf8)
        #expect(text.contains("| Expected | Last run |"))
        #expect(text.contains("| `t` | timeout | 2026-01-02 KILLED (TIMEOUT) |"))
        #expect(text.contains("| `t` | killed | not run |"))
    }

    @Test("a time-out leaves no process of the mutant package running")
    func timeoutLeavesNoProcessBehind() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([Register.looping]),
            extra: ["--timeout", Register.loopTimeout])
        #expect(result.output.contains("loop | KILLED (TIMEOUT) |"), "output: \(result.output)")
        #expect(try MiniPackage.processes(mentioning: package.root.path).isEmpty)
    }

    @Test("a register where every mutant is killed exits zero")
    func allKilledExitsZero() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([Register.killed]),
            extra: ["--timeout", "90"])
        #expect(result.status == 0, "output: \(result.output)")
        #expect(result.output.contains("even-flip | KILLED |"))
    }

    @Test("a named test that fails on clean code is a baseline failure, not a kill")
    func baselineFailureIsReported() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(
            id: "needs-baseline", search: "return 7", replace: "return 8", test: "brokenBaseline")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]),
            extra: ["--timeout", "90"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("needs-baseline | BASELINE FAILED"))
    }

    @Test("a test id that does not resolve is a register error and nothing is mutated")
    func unknownTestIsRegisterError() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(
            id: "bad-test", search: "return 7", replace: "return 8", test: "noSuchTest")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]))
        #expect(result.status == 2)
        #expect(
            result.output.contains("REGISTER ERROR bad-test: test id noSuchTest does not resolve"))
        #expect(try package.gitStatus().isEmpty)
    }

    @Test("search text that occurs twice is a register error")
    func searchTwiceIsRegisterError() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(id: "twice", search: "value", replace: "other")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]))
        #expect(result.status == 2)
        #expect(result.output.contains("twice: search text occurs"))
        #expect(result.output.contains("need 1"))
    }

    @Test("search text that does not occur is a register error")
    func searchMissingIsRegisterError() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(id: "missing", search: "not in the file", replace: "x")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]))
        #expect(result.status == 2)
        #expect(result.output.contains("missing: search text occurs 0 times"))
    }

    @Test("a file outside Sources is a register error")
    func fileOutsideSourcesIsRegisterError() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        for file in [
            "Package.swift", "../Package.swift", "/etc/hosts", "Tests/MiniTests/MiniTests.swift",
            "Tests/ArchitectureTests/ArchitectureCheckerTests.swift",
            "Tests/ArchitectureTests/../../Package.swift", "Tests/ArchitectureTests/notes.md",
        ] {
            let entry = Register.entry(id: "outside", search: "x", replace: "y", file: file)
            let result = try RunnerBinary.run(
                on: package, double: double, register: Register.list([entry]))
            #expect(result.status == 2, "file \(file)")
            #expect(
                result.output.contains("file must be a relative path under Sources/"),
                "file \(file)")
        }
    }

    @Test("a duplicate id and an unchanged replacement are register errors")
    func duplicateAndNoOpAreRegisterErrors() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let same = Register.entry(id: "same", search: "return 7", replace: "return 7")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([same, same]))
        #expect(result.status == 2)
        #expect(result.output.contains("same: duplicate id"))
        #expect(result.output.contains("same: replacement equals search"))
    }

    @Test("a dirty working tree is refused")
    func dirtyTreeIsRefused() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        try (try package.sourceText() + "\n// edit\n").write(
            to: package.sourceURL, atomically: true, encoding: .utf8)
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([Register.killed]))
        #expect(result.status == 2)
        #expect(result.output.contains("the working tree is not clean"))
    }

    @Test("malformed registers are refused with a register message and no mutation")
    func malformedRegistersAreRefused() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let corpus = [
            "", "null", "{}", "[1,2]", "[{\"id\":\"a\"}]", "[{\"id\":\"a\",\"slice\":\"1\"",
            "not json", "[{\"id\":1,\"slice\":2,\"file\":3,\"search\":4,\"replace\":5,\"test\":6}]",
        ]
        for text in corpus {
            let result = try RunnerBinary.run(on: package, double: double, register: text)
            #expect(result.status == 2, "register: \(text)")
            #expect(result.output.contains("register"), "register: \(text)")
            #expect(try package.gitStatus().isEmpty, "register: \(text)")
        }
    }

    @Test("an interrupt during a mutant run restores the mutated file")
    func interruptRestoresFile() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
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
        process.environment = double.environment
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
        #expect(try MiniPackage.processes(mentioning: package.root.path).isEmpty)
    }

    @Test("the markdown page is generated from the register and sorted by id")
    func markdownIsGenerated() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let output = package.root.appendingPathComponent("page.md")
        let register = Register.list([Register.survivor, Register.killed])
        let result = try RunnerBinary.run(
            on: package, double: double, register: register, extra: ["--markdown", output.path])
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

    @Test("an architecture checker file passes the path rule and a missing one is reported")
    func architectureCheckerFileIsAllowed() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let entry = Register.entry(
            id: "checker", search: "x", replace: "y",
            file: "Tests/ArchitectureTests/ArchitectureChecker.swift")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([entry]))
        #expect(result.status == 2, "output: \(result.output)")
        #expect(!result.output.contains("file must be a relative path"))
        #expect(
            result.output.contains(
                "checker: cannot read Tests/ArchitectureTests/ArchitectureChecker.swift"))
    }

    // MARK: Plan, workers and changed files

    private static let otherKilled = Register.entry(
        id: "triple-flip", search: "number * 3", replace: "number * 4", test: "tripledTriples",
        file: "Sources/Mini/Other.swift")

    @Test("the plan groups entries by file in file order and keeps register order in a file")
    func planGroupsByFile() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([Self.otherKilled, Register.survivor, Register.killed]),
            extra: ["--plan", "yes", "--workers", "8"])
        #expect(result.status == 0, "output: \(result.output)")
        let lines = result.output.split(separator: "\n").map(String.init)
        #expect(
            lines == [
                "workers: 2",
                "GROUP Sources/Mini/Mini.swift: unused, even-flip",
                "GROUP Sources/Mini/Other.swift: triple-flip",
                "BASELINE evenNumbersAreEven",
                "BASELINE tripledTriples",
            ])
    }

    @Test("one worker is used when every entry is in one file")
    func planUsesOneWorkerForOneFile() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([Register.killed, Register.survivor]),
            extra: ["--plan", "yes", "--workers", "4"])
        #expect(result.output.hasPrefix("workers: 1\n"), "output: \(result.output)")
    }

    @Test("the baseline runs once for a test that two entries share")
    func baselineRunsOncePerTest() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([Register.killed, Register.survivor]),
            extra: ["--timeout", "90", "--record", "no"])
        #expect(result.output.contains("even-flip | KILLED |"), "output: \(result.output)")
        #expect(result.output.contains("unused | SURVIVED |"))
        #expect(result.output.contains("baseline runs: 1\n"))
    }

    @Test("a baseline failure skips every entry that names the failing test")
    func baselineFailureSkipsEveryEntryOfThatTest() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let first = Register.entry(
            id: "needs-a", search: "return 7", replace: "return 8", test: "brokenBaseline")
        let second = Register.entry(
            id: "needs-b", search: "number % 2 == 0", replace: "number % 2 == 1",
            test: "brokenBaseline")
        let result = try RunnerBinary.run(
            on: package, double: double, register: Register.list([first, second, Register.killed]),
            extra: ["--timeout", "90", "--record", "no"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("needs-a | BASELINE FAILED"))
        #expect(result.output.contains("needs-b | BASELINE FAILED"))
        #expect(result.output.contains("even-flip | KILLED |"))
        #expect(result.output.contains("baseline runs: 2\n"))
    }

    @Test("changed-since keeps only the entries whose file changed after the ref")
    func changedSinceKeepsChangedFiles() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        try (MiniPackage.otherSourceText + "// changed\n").write(
            to: package.otherSourceURL, atomically: true, encoding: .utf8)
        try package.commitAll(message: "change other")
        let register = Register.list([Register.killed, Self.otherKilled])
        let changed = try RunnerBinary.run(
            on: package, double: double, register: register,
            extra: ["--plan", "yes", "--changed-since", "HEAD~1"])
        #expect(changed.status == 0, "output: \(changed.output)")
        #expect(changed.output.contains("GROUP Sources/Mini/Other.swift: triple-flip"))
        #expect(!changed.output.contains("even-flip"))
        let all = try RunnerBinary.run(
            on: package, double: double, register: register,
            extra: ["--plan", "yes", "--changed-since", "fixture~0"])
        #expect(all.output.contains("triple-flip") && !all.output.contains("even-flip"))
        let none = try RunnerBinary.run(
            on: package, double: double, register: register, extra: ["--changed-since", "HEAD"])
        #expect(none.status == 0, "output: \(none.output)")
        #expect(none.output.contains("nothing to run"))
        #expect(!none.output.contains("|"))
    }

    @Test("changed-since refuses a ref that is not a commit, an option or an empty text")
    func changedSinceRefusesBadRef() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        for ref in ["no-such-ref", "--cached", "-p", "", "HEAD~99"] {
            let result = try RunnerBinary.run(
                on: package, double: double, register: Register.list([Register.killed]),
                extra: ["--plan", "yes", "--changed-since", ref])
            #expect(result.status == 2, "ref \(ref): \(result.output)")
            #expect(result.output.contains("is not a commit"), "ref \(ref)")
        }
    }

    @Test("a worker count that is not a whole number from 1 to 64 is refused")
    func badWorkerCountIsRefused() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        for value in ["0", "-1", "65", "two", "1.5", ""] {
            let result = try RunnerBinary.run(
                on: package, double: double, register: Register.list([Register.killed]),
                extra: ["--plan", "yes", "--workers", value])
            #expect(result.status == 2, "value \(value)")
            #expect(result.output.contains("--workers needs a whole number"), "value \(value)")
        }
        let edge = try RunnerBinary.run(
            on: package, double: double, register: Register.list([Register.killed]),
            extra: ["--plan", "yes", "--workers", "64"])
        #expect(edge.status == 0, "output: \(edge.output)")
    }

    @Test(
        "two workers mutate copies, report each outcome and leave the package and temp folder clean"
    )
    func parallelWorkersUseCopies() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let before = try MiniPackage.workerFolders()
        let result = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([Register.killed, Register.survivor, Self.otherKilled]),
            extra: ["--timeout", "90", "--record", "no", "--workers", "2"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("even-flip | KILLED |"))
        #expect(result.output.contains("unused | SURVIVED |"))
        #expect(result.output.contains("triple-flip | KILLED |"))
        #expect(result.output.contains("workers: 2\n"))
        #expect(try package.gitStatus().isEmpty)
        #expect(try MiniPackage.workerFolders().subtracting(before).isEmpty)
    }

    @Test("an interrupt during a parallel run removes the copies and stops every process")
    func interruptDuringParallelRunRemovesCopies() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let before = try MiniPackage.workerFolders()
        let registerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("register-\(UUID().uuidString).json")
        try Register.list([Register.looping, Self.otherKilled]).write(
            to: registerURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: registerURL) }
        let process = Process()
        process.executableURL = RunnerBinary.url
        process.arguments = [
            "--root", package.root.path, "--register", registerURL.path, "--timeout", "600",
            "--workers", "2", "--record", "no",
        ]
        process.currentDirectoryURL = package.root
        process.environment = double.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(300)
        var sawMutation = false
        while Date() < deadline, process.isRunning, !sawMutation {
            for folder in try MiniPackage.workerFolders().subtracting(before) {
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent(folder).appendingPathComponent(
                        "Sources/Mini/Mini.swift")
                if (try? String(contentsOf: file, encoding: .utf8))?.contains("value += 1") == true
                {
                    sawMutation = true
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        #expect(sawMutation, "no worker applied the mutation")
        kill(process.processIdentifier, SIGINT)
        let exitDeadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.1) }
        #expect(!process.isRunning, "the runner did not stop after the interrupt")
        if !process.isRunning {
            #expect(process.terminationReason == .exit && process.terminationStatus == 130)
        }
        #expect(try package.sourceText() == MiniPackage.sourceText)
        #expect(try package.gitStatus().isEmpty)
        #expect(try MiniPackage.workerFolders().subtracting(before).isEmpty)
        #expect(try MiniPackage.processes(mentioning: "mutate-worker-").isEmpty)
    }

    @Test("each entry builds once and each distinct baseline runs once without a build")
    func eachEntryBuildsOnceAndBaselinesNeverBuild() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        let result = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([Register.killed, Register.survivor, Self.otherKilled]),
            extra: ["--timeout", "90", "--record", "no", "--workers", "1"])
        #expect(result.status == 1, "output: \(result.output)")
        let calls = try double.calls().map(\.arguments)
        let even = #"test --skip-build --filter ^MiniTests\.MiniTests\/evenNumbersAreEven\(\)"#
        let triple = #"test --skip-build --filter ^MiniTests\.MiniTests\/tripledTriples\(\)"#
        #expect(
            calls == [
                "test list", even, triple, "build --build-tests", even, "build --build-tests",
                even, "build --build-tests", triple,
            ])
        #expect(try double.calls().allSatisfy { $0.folder == package.root.path })
    }

    @Test("two workers build and test only in their copies, never in the package folder")
    func parallelWorkersNeverBuildInThePackage() throws {
        let package = try MiniPackage.create()
        let double = try SwiftDouble.make()
        defer { double.remove() }
        _ = try RunnerBinary.run(
            on: package, double: double,
            register: Register.list([Register.killed, Self.otherKilled]),
            extra: ["--timeout", "90", "--record", "no", "--workers", "2"])
        let calls = try double.calls()
        let inPackage = calls.filter { $0.folder == package.root.path }.map(\.arguments)
        let inCopies = calls.filter { $0.folder != package.root.path }
        #expect(inPackage.count == 3 && inPackage.first == "test list")
        #expect(!inPackage.contains("build --build-tests"))
        #expect(inCopies.filter { $0.arguments == "build --build-tests" }.count == 2)
        #expect(Set(inCopies.map(\.folder)).count == 2)
        #expect(inCopies.allSatisfy { $0.folder.contains("mutate-worker-") })
    }
}
