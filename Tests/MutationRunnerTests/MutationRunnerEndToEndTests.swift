import Foundation
import TestHelpers
import Testing

/// Runs the real runner with the real toolchain on the fixture package. These tests build, so the
/// default test run skips them. `Scripts/runner-check.sh` runs them, and the gate runs that
/// script when the runner or its tests change.
@Suite(
    "Mutation runner end to end", .serialized, .timeLimit(.minutes(20)),
    .enabled(if: ProcessInfo.processInfo.environment["DEPENDI_RUNNER_CHECK"] == "1"))
struct MutationRunnerEndToEndTests {
    @Test("a real build in place gives killed, survived and invalid and restores the tree")
    func realBuildInPlaceGivesEachOutcome() throws {
        let package = try MiniPackage.create()
        let result = try RunnerBinary.run(
            on: package, double: nil,
            register: Register.list([Register.killed, Register.survivor, Register.invalid]),
            extra: ["--timeout", "120", "--record", "no", "--workers", "1"])
        #expect(result.status == 1, "output: \(result.output)")
        #expect(result.output.contains("even-flip | KILLED |"))
        #expect(result.output.contains("unused | SURVIVED |"))
        #expect(result.output.contains("broken | INVALID |"))
        #expect(result.output.contains("baseline runs: 1\n"))
        #expect(try package.sourceText() == MiniPackage.sourceText)
        #expect(try package.gitStatus().isEmpty)
    }

    @Test("a real build with two workers kills a mutant in each file and leaves no copy")
    func realBuildWithTwoWorkersKillsInEachFile() throws {
        let package = try MiniPackage.create()
        let before = try MiniPackage.workerFolders()
        let other = Register.entry(
            id: "triple-flip", search: "number * 3", replace: "number * 4",
            test: "tripledTriples", file: "Sources/Mini/Other.swift")
        let result = try RunnerBinary.run(
            on: package, double: nil, register: Register.list([Register.killed, other]),
            extra: ["--timeout", "120", "--record", "no", "--workers", "2"])
        #expect(result.status == 0, "output: \(result.output)")
        #expect(result.output.contains("even-flip | KILLED |"))
        #expect(result.output.contains("triple-flip | KILLED |"))
        #expect(result.output.contains("workers: 2\n"))
        #expect(try package.gitStatus().isEmpty)
        #expect(try MiniPackage.workerFolders().subtracting(before).isEmpty)
    }

    @Test("an interrupt during a real looping test restores the file and stops every process")
    func interruptDuringRealRunRestoresFile() throws {
        let package = try MiniPackage.create()
        let registerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("register-\(UUID().uuidString).json")
        try Register.list([Register.looping]).write(
            to: registerURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: registerURL) }
        let process = Process()
        process.executableURL = RunnerBinary.url
        process.arguments = [
            "--root", package.root.path, "--register", registerURL.path, "--timeout", "600",
            "--workers", "1", "--record", "no",
        ]
        process.currentDirectoryURL = package.root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // The real test helper starts only after the build, so wait for it, not for the edit.
        let deadline = Date().addingTimeInterval(600)
        var sawHelper = false
        while Date() < deadline, process.isRunning, !sawHelper {
            let isMutated = (try? package.sourceText().contains("value += 1")) == true
            let tests = try MiniPackage.processes(mentioning: "--skip-build")
            sawHelper = isMutated && tests.contains { $0.contains("countDownReachesZero") }
            Thread.sleep(forTimeInterval: 0.25)
        }
        #expect(sawHelper, "the runner never started the looping test")
        kill(process.processIdentifier, SIGINT)
        let exitDeadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.1) }
        #expect(!process.isRunning, "the runner did not stop after the interrupt")
        #expect(try package.sourceText() == MiniPackage.sourceText)
        #expect(try package.gitStatus().isEmpty)
        #expect(try MiniPackage.processes(mentioning: package.root.path).isEmpty)
    }
}
