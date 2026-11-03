import DependiDomain
import Foundation
import Testing
import TestHelpers

@testable import DependiProcess

/// Helpers shared by the process tests.
private enum Probe {
    static let registry = ChildProcessRegistry()
    static let runner = SystemProcessRunner(children: registry)

    static func request(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = ["PATH": "/usr/bin:/bin"],
        workingDirectory: String? = nil,
        timeout: Double = 30,
        maximumBytes: Int = 64_000_000
    ) -> ProcessRequest {
        ProcessRequest(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeout,
            maximumOutputBytes: maximumBytes
        )
    }

    static func shell(
        _ script: String, _ rest: [String] = [], timeout: Double = 30,
        maximumBytes: Int = 64_000_000
    )
        -> ProcessRequest
    {
        request("/bin/sh", ["-c", script] + rest, timeout: timeout, maximumBytes: maximumBytes)
    }

    static func failureReason(_ request: ProcessRequest) -> String? {
        do {
            _ = try runner.run(request)
            return nil
        } catch {
            if case .processFailed(_, let reason) = error { return reason }
            return "other error"
        }
    }

    /// Returns whether any process has the marker in its command line.
    static func markerIsRunning(_ marker: String) -> Bool {
        let output = try? runner.run(request("/bin/ps", ["-axo", "command="]))
        let text = String(decoding: output?.standardOutput ?? Data(), as: UTF8.self)
        return text.contains(marker)
    }

    /// Waits up to three seconds for the marker to disappear.
    static func markerDisappears(_ marker: String) -> Bool {
        for _ in 0..<60 {
            if !markerIsRunning(marker) { return true }
            usleep(50_000)
        }
        return false
    }
}

@Suite(.serialized)
struct SystemProcessRunnerTests {
    @Test func bigOutputOnBothStreamsArrivesWithExactBytesAndChecksum() throws {
        let script = "(yes abc | head -c 1500000) & (yes xyz | head -c 1700000 >&2) & wait"
        let output = try Probe.runner.run(Probe.shell(script, timeout: 10))
        #expect(output.exitStatus == 0)
        #expect(output.standardOutput.count == 1_500_000)
        #expect(output.standardError.count == 1_700_000)
        let expectedOut = Data(String(repeating: "abc\n", count: 375_000).utf8)
        let expectedErr = Data(String(repeating: "xyz\n", count: 425_000).utf8)
        #expect(output.standardOutput == expectedOut)
        #expect(output.standardError == expectedErr)
        // Each four byte unit sums to 304 for abc and 373 for xyz. The totals are written by hand.
        #expect(output.standardOutput.reduce(0) { $0 + Int($1) } == 114_000_000)
        #expect(output.standardError.reduce(0) { $0 + Int($1) } == 158_525_000)
    }

    @Test func exitCodesAreReported() throws {
        for code in [0, 1, 255] {
            let output = try Probe.runner.run(Probe.shell("exit \(code)"))
            #expect(output.exitStatus == Int32(code))
        }
    }

    @Test func aChildThatDiesByASignalReportsOneHundredTwentyEightPlusTheSignal() throws {
        #expect(try Probe.runner.run(Probe.shell("kill -9 $$")).exitStatus == 137)
        #expect(try Probe.runner.run(Probe.shell("kill -15 $$")).exitStatus == 143)
    }

    @Test func aMissingExecutableFailsWithProcessFailed() {
        let reason = Probe.failureReason(Probe.request("/nonexistent/dir/tool"))
        #expect(reason?.contains("cannot start") == true)
    }

    @Test func aRelativeExecutableIsNotSearchedOnThePath() {
        #expect(Probe.failureReason(Probe.request("sh", ["-c", "exit 0"])) != nil)
    }

    @Test func aMissingWorkingDirectoryFails() {
        let request = Probe.request("/bin/pwd", workingDirectory: "/nonexistent/dir")
        #expect(Probe.failureReason(request) != nil)
    }

    @Test func theWorkingDirectoryIsHonored() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = try Probe.runner.run(Probe.request("/bin/pwd", workingDirectory: folder.path))
        let printed = String(decoding: output.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            URL(fileURLWithPath: printed).resolvingSymlinksInPath().path
                == folder.resolvingSymlinksInPath().path)
    }

    @Test func theChildEnvironmentIsExactlyTheRequestEnvironment() throws {
        setenv("SDKROOT", "/inherited/sdk", 1)
        defer { unsetenv("SDKROOT") }
        let wanted = ["ALPHA": "1", "BETA": "two words", "EMPTY": ""]
        let output = try Probe.runner.run(Probe.request("/usr/bin/env", environment: wanted))
        let lines = String(decoding: output.standardOutput, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(Set(lines) == ["ALPHA=1", "BETA=two words", "EMPTY="])
        #expect(!lines.contains { $0.hasPrefix("SDKROOT") })
    }

    @Test func anEmptyEnvironmentGivesAnEmptyChildEnvironment() throws {
        setenv("SDKROOT", "/inherited/sdk", 1)
        defer { unsetenv("SDKROOT") }
        let output = try Probe.runner.run(Probe.request("/usr/bin/env", environment: [:]))
        #expect(output.standardOutput.isEmpty)
    }

    @Test func argumentsAreNotInterpretedByAShell() throws {
        let output = try Probe.runner.run(Probe.request("/bin/echo", ["$HOME;", "*", "a b"]))
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "$HOME; * a b\n")
    }

    @Test func outputOverTheCapFailsAndNamesTheLimit() {
        let reason = Probe.failureReason(Probe.shell("yes | head -c 5000", maximumBytes: 1000))
        #expect(reason?.contains("over the limit of 1000 bytes") == true)
    }

    @Test func standardErrorOverTheCapFails() {
        let reason = Probe.failureReason(Probe.shell("yes >&2", maximumBytes: 1000))
        #expect(reason?.contains("over the limit") == true)
    }

    @Test func outputExactlyAtTheCapIsKept() throws {
        let output = try Probe.runner.run(Probe.shell("head -c 1000 /dev/zero", maximumBytes: 1000))
        #expect(output.standardOutput.count == 1000)
    }

    @Test func aFastChildWithALongLimitIsNotTimedOut() throws {
        let output = try Probe.runner.run(Probe.shell("printf done", timeout: 30))
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "done")
    }

    @Test func aSlowChildIsTimedOutQuickly() {
        let start = Date()
        let reason = Probe.failureReason(Probe.shell("sleep 6", timeout: 0.5))
        #expect(reason == "timed out after 0.5 seconds")
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func aGrandchildHoldingStandardOutputIsKilledOnTimeout() {
        let marker = "MARK\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let script = "(sleep 30; : \(marker)) & sleep 30; : \(marker)"
        let start = Date()
        let reason = Probe.failureReason(Probe.shell(script, timeout: 0.5))
        #expect(reason?.contains("timed out") == true)
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(Probe.markerDisappears(marker))
    }

    @Test func aDescendantThatLeftTheProcessGroupIsKilledOnTimeout() {
        let marker = "MARK\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let perl = "use POSIX; POSIX::setsid(); exec q(/bin/sh), q(-c), q(sleep 30; : \(marker))"
        let script = "/usr/bin/perl -e '\(perl)' & wait"
        let start = Date()
        let reason = Probe.failureReason(Probe.shell(script, timeout: 1))
        #expect(reason?.contains("timed out") == true)
        #expect(Date().timeIntervalSince(start) < 6)
        #expect(Probe.markerDisappears(marker))
    }

    @Test func aBackgroundChildThatKeepsThePipeOpenAfterTheParentExitsStillTimesOut() {
        let marker = "MARK\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let start = Date()
        let reason = Probe.failureReason(
            Probe.shell("(sleep 30; : \(marker)) & exit 0", timeout: 0.5))
        #expect(reason?.contains("timed out") == true)
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(Probe.markerDisappears(marker))
    }

    /// The descriptors of this process that are pipes. The runner creates pipes and nothing else,
    /// and the tests of other suites that run at the same time open files, not pipes.
    private static func openPipes() -> Set<Int32> {
        var found: Set<Int32> = []
        for descriptor in 0..<Int32(1024) {
            var info = stat()
            if fstat(descriptor, &info) == 0 && (info.st_mode & S_IFMT) == S_IFIFO {
                found.insert(descriptor)
            }
        }
        return found
    }

    /// Waits until the set of pipes is the same as before. A leak never goes away, so the wait
    /// is bounded by two seconds and a late close of another test does not count.
    private static func pipesReturn(to before: Set<Int32>) -> Set<Int32> {
        var extra = openPipes().subtracting(before)
        for _ in 0..<40 where !extra.isEmpty {
            usleep(50_000)
            extra = openPipes().subtracting(before)
        }
        return extra
    }

    @Test func successfulRunsLeaveNoPipeDescriptorBehind() throws {
        let before = Self.openPipes()
        for _ in 0..<20 { _ = try Probe.runner.run(Probe.shell("printf a; printf b >&2")) }
        #expect(Self.pipesReturn(to: before).isEmpty)
    }

    @Test func timedOutRunsLeaveNoPipeDescriptorBehind() {
        let before = Self.openPipes()
        for _ in 0..<5 { _ = Probe.failureReason(Probe.shell("sleep 30", timeout: 0.1)) }
        #expect(Self.pipesReturn(to: before).isEmpty)
    }

    @Test func overflowAndSpawnFailureLeaveNoPipeDescriptorBehind() {
        let before = Self.openPipes()
        for _ in 0..<5 { _ = Probe.failureReason(Probe.shell("yes", maximumBytes: 100)) }
        for _ in 0..<5 { _ = Probe.failureReason(Probe.request("/nonexistent/tool")) }
        #expect(Self.pipesReturn(to: before).isEmpty)
    }

    @Test func theChildHoldsOnlyTheThreeStandardDescriptors() throws {
        // The listing shows the descriptors of `ls` itself. It adds two for its own scan.
        let output = try Probe.runner.run(Probe.request("/bin/ls", ["/dev/fd"]))
        let lines = String(decoding: output.standardOutput, as: UTF8.self)
            .split(separator: "\n").map(String.init)
        #expect(Array(lines.prefix(3)) == ["0", "1", "2"])
        #expect(lines.count <= 5, "\(lines)")
    }

    @Test func randomExitCodesAndOutputSizesRoundTripExactly() throws {
        var generator = SeededGenerator()
        for round in 0..<25 {
            let code = Int.random(in: 0...255, using: &generator)
            let outCount = Int.random(in: 0...200_000, using: &generator)
            let errCount = Int.random(in: 0...200_000, using: &generator)
            let script =
                "head -c $0 /dev/zero | tr '\\0' q; head -c $1 /dev/zero | tr '\\0' r >&2; exit $2"
            let request = Probe.shell(script, ["\(outCount)", "\(errCount)", "\(code)"])
            let output = try Probe.runner.run(request)
            let note = Comment(
                rawValue:
                    "seed \(SeededGenerator.defaultSeed) round \(round) code \(code) out \(outCount) err \(errCount)"
            )
            #expect(output.exitStatus == Int32(code), note)
            #expect(output.standardOutput == Data(repeating: 113, count: outCount), note)
            #expect(output.standardError == Data(repeating: 114, count: errCount), note)
        }
    }
}
