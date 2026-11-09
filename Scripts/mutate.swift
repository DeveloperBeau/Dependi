// Runs the mutation register. Compile and run with: swiftc Scripts/mutate.swift -o mutate
// This file is a stand-alone tool and is built in Swift 5 mode on purpose: it keeps one piece of
// global state so a signal handler can restore the file that is being mutated.
import Foundation

struct LastRun: Decodable {
    let date: String
    let outcome: String
}

struct Entry: Decodable {
    let id: String
    let slice: String
    let file: String
    let search: String
    let replace: String
    let test: String
    /// The outcome the register expects: "killed" (the default) or "timeout".
    let expected: String?
    let lastRun: LastRun?

    var expectedName: String { expected ?? "killed" }
    var expectedOutcome: Outcome? {
        switch expectedName {
        case "killed": return .killed
        case "timeout": return .killedByTimeout
        default: return nil
        }
    }
}

enum Outcome: String {
    case killed = "KILLED"
    case killedByTimeout = "KILLED (TIMEOUT)"
    case survived = "SURVIVED"
    case invalid = "INVALID"
}

struct CommandResult {
    let status: Int32
    let output: String
    let timedOut: Bool
}

var root = FileManager.default.currentDirectoryPath
var registerPath = "Documentation/Registers/mutations.json"
var timeoutSeconds = 300.0
var buildTimeoutSeconds = 900.0
var onlyID: String?
var markdownPath: String?
var shouldRecord = true
/// The exact filter for each entry id, filled by `validate`.
var filters: [String: String] = [:]
var mutatedFile: String?
var activeProcessID: Int32?

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func parseArguments() {
    var arguments = CommandLine.arguments.dropFirst()
    while let flag = arguments.popFirst() {
        guard let value = arguments.popFirst() else { fail("missing value for \(flag)") }
        switch flag {
        case "--root": root = value
        case "--register": registerPath = value
        case "--timeout": timeoutSeconds = Double(value) ?? timeoutSeconds
        case "--build-timeout": buildTimeoutSeconds = Double(value) ?? buildTimeoutSeconds
        case "--only": onlyID = value
        case "--record": shouldRecord = value != "no"
        case "--markdown": markdownPath = value
        default: fail("unknown flag \(flag)")
        }
    }
}

/// Lists every process id with its parent id.
func processTable() -> [(pid: Int32, parent: Int32)] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,ppid="]
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ")
        guard parts.count == 2, let pid = Int32(parts[0]), let parent = Int32(parts[1]) else {
            return nil
        }
        return (pid, parent)
    }
}

/// Kills a process, its process group and every descendant. Test helpers can leave the group.
func killTree(_ root: Int32) {
    let table = processTable()
    var found: [Int32] = []
    var queue = [root]
    while let next = queue.popLast() {
        for entry in table where entry.parent == next && !found.contains(entry.pid) {
            found.append(entry.pid)
            queue.append(entry.pid)
        }
    }
    kill(-root, SIGKILL)
    for pid in found { kill(pid, SIGKILL) }
    kill(root, SIGKILL)
}

/// Runs a command in its own process group and kills the whole group on timeout.
func run(_ arguments: [String], timeout: Double) -> CommandResult {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mutate-\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: outputURL) }
    guard let sink = try? FileHandle(forWritingTo: outputURL) else { fail("cannot open output") }
    defer { try? sink.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "setpgrp(0,0); exec @ARGV or die $!;", "--"] + arguments
    process.currentDirectoryURL = URL(fileURLWithPath: root)
    process.standardOutput = sink
    process.standardError = sink
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() } catch { fail("cannot start \(arguments[0]): \(error)") }
    activeProcessID = process.processIdentifier
    defer { activeProcessID = nil }
    var timedOut = false
    if finished.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        killTree(process.processIdentifier)
        _ = finished.wait(timeout: .now() + 30)
    }
    let text = String(decoding: (try? Data(contentsOf: outputURL)) ?? Data(), as: UTF8.self)
    return CommandResult(status: process.terminationStatus, output: text, timedOut: timedOut)
}

func git(_ arguments: [String]) -> CommandResult { run(["git"] + arguments, timeout: 60) }

func restore(_ file: String) {
    _ = git(["checkout", "--", file])
}

func installSignalHandlers() {
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
        source.setEventHandler {
            if let pid = activeProcessID { killTree(pid) }
            if let file = mutatedFile { restore(file) }
            exit(130)
        }
        source.resume()
        signalSources.append(source)
    }
}
var signalSources: [DispatchSourceSignal] = []

func loadRegister() -> [Entry] {
    let url = URL(fileURLWithPath: registerPath, relativeTo: URL(fileURLWithPath: root))
    guard let data = try? Data(contentsOf: url) else { fail("cannot read register \(url.path)") }
    do { return try JSONDecoder().decode([Entry].self, from: data) } catch {
        fail("register is not valid: \(error)")
    }
}

func occurrences(of needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return text.components(separatedBy: needle).count - 1
}

/// Returns the listed test ids that name the given test. A bare name matches the function only.
func matchingTests(_ test: String, in listing: [String]) -> [String] {
    listing.filter { line in
        if test.contains("/") { return line == test || line.hasSuffix("." + test) }
        guard let slash = line.lastIndex(of: "/") else { return false }
        let name = line[line.index(after: slash)...]
        return name == test || name.hasPrefix(test + "(")
    }
}

/// Builds a filter that matches one listed test id and nothing else. The listed id ends in a
/// closing parenthesis, so it cannot be the start of a longer name. The id swift-testing matches
/// against carries a source location after it, which is why the pattern has no end anchor.
func exactFilter(for listed: String) -> String {
    "^" + NSRegularExpression.escapedPattern(for: listed)
}

func validate(_ entries: [Entry]) -> [String] {
    var problems: [String] = []
    var ids = Set<String>()
    let listing = run(["swift", "test", "list"], timeout: 600)
    let listed = listing.output.split(separator: "\n").map {
        String($0).trimmingCharacters(in: .whitespaces)
    }
    for entry in entries {
        if !ids.insert(entry.id).inserted { problems.append("\(entry.id): duplicate id") }
        if entry.expectedOutcome == nil {
            problems.append(
                "\(entry.id): expected must be killed or timeout, not \(entry.expectedName)")
        }
        let relative = entry.file
        if relative.hasPrefix("/") || relative.contains("..") || !relative.hasPrefix("Sources/") {
            problems.append("\(entry.id): file must be a relative path under Sources/")
            continue
        }
        let path = (root as NSString).appendingPathComponent(relative)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            problems.append("\(entry.id): cannot read \(relative)")
            continue
        }
        let count = occurrences(of: entry.search, in: text)
        if count != 1 {
            problems.append("\(entry.id): search text occurs \(count) times in \(relative), need 1")
        }
        if entry.search == entry.replace {
            problems.append("\(entry.id): replacement equals search")
        }
        let matches = matchingTests(entry.test, in: listed)
        if matches.isEmpty {
            problems.append("\(entry.id): test id \(entry.test) does not resolve")
        } else if matches.count > 1 {
            problems.append(
                "\(entry.id): test id \(entry.test) is ambiguous, it matches \(matches.joined(separator: ", "))"
            )
        } else {
            filters[entry.id] = exactFilter(for: matches[0])
        }
    }
    return problems
}

func writeMarkdown(_ entries: [Entry], to path: String) {
    var lines = [
        "# Mutation register",
        "",
        "This page is generated from `mutations.json` by `Scripts/mutate.swift --markdown`. Do not edit it.",
        "",
        "| Id | Slice | File | Test | Expected | Last run |",
        "|---|---|---|---|---|---|",
    ]
    for entry in entries.sorted(by: { $0.id < $1.id }) {
        let last = entry.lastRun.map { "\($0.date) \($0.outcome)" } ?? "not run"
        lines.append(
            "| \(entry.id) | \(entry.slice) | `\(entry.file)` | `\(entry.test)` | \(entry.expectedName) | \(last) |"
        )
    }
    let text = lines.joined(separator: "\n") + "\n"
    let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: root))
    do { try text.write(to: url, atomically: true, encoding: .utf8) } catch {
        fail("cannot write \(url.path): \(error)")
    }
}

func requireCleanTree() {
    let status = git(["status", "--porcelain"])
    if status.status != 0 || !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
        fail("the working tree is not clean. Commit or stash first.\n\(status.output)")
    }
}

func baseline(_ entry: Entry) -> Bool {
    let result = run(
        ["swift", "test", "--filter", filters[entry.id] ?? entry.test], timeout: buildTimeoutSeconds
    )
    return result.status == 0 && !result.timedOut
}

func mutate(_ entry: Entry) -> Outcome {
    let path = (root as NSString).appendingPathComponent(entry.file)
    guard let original = try? String(contentsOfFile: path, encoding: .utf8) else { return .invalid }
    let mutated = original.replacingOccurrences(of: entry.search, with: entry.replace)
    mutatedFile = entry.file
    defer {
        restore(entry.file)
        mutatedFile = nil
    }
    do { try mutated.write(toFile: path, atomically: true, encoding: .utf8) } catch {
        return .invalid
    }
    let build = run(["swift", "build", "--build-tests"], timeout: buildTimeoutSeconds)
    if build.status != 0 || build.timedOut { return .invalid }
    let test = run(
        ["swift", "test", "--skip-build", "--filter", filters[entry.id] ?? entry.test],
        timeout: timeoutSeconds)
    if test.timedOut { return .killedByTimeout }
    if test.status == 0 { return .survived }
    let ranAndFailed = test.output.contains("✘ Test") || test.output.contains("error: -[")
    return ranAndFailed ? .killed : .invalid
}

/// Writes the outcome of each run into its register entry without touching the rest of the text.
func recordRuns(_ results: [(id: String, outcome: Outcome)]) {
    let url = URL(fileURLWithPath: registerPath, relativeTo: URL(fileURLWithPath: root))
    guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let today = formatter.string(from: Date())
    for result in results {
        guard let range = objectRange(forID: result.id, in: text) else { continue }
        var object = String(text[range])
        if let old = object.range(
            of: #",\s*"lastRun"\s*:\s*\{[^}]*\}"#, options: .regularExpression)
        {
            object.removeSubrange(old)
        }
        guard let close = object.lastIndex(of: "}") else { continue }
        var body = object[..<close]
        var trailing = ""
        while let last = body.last, last.isWhitespace {
            trailing = String(last) + trailing
            body = body.dropLast()
        }
        let separator = object.contains("\n") ? "\n    " : ""
        let field =
            "\"lastRun\": {\"date\": \"\(today)\", \"outcome\": \"\(result.outcome.rawValue)\"}"
        text.replaceSubrange(range, with: body + "," + separator + field + trailing + "}")
    }
    try? text.write(to: url, atomically: true, encoding: .utf8)
}

/// Finds the text range of the top-level object whose id is given.
func objectRange(forID id: String, in text: String) -> Range<String.Index>? {
    var depth = 0
    var start: String.Index?
    var inString = false
    var escaped = false
    var index = text.startIndex
    while index < text.endIndex {
        let character = text[index]
        if inString {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString = false
            }
        } else if character == "\"" {
            inString = true
        } else if character == "{" {
            if depth == 1 { start = index }
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 1, let begin = start {
                let range = begin..<text.index(after: index)
                if let data = String(text[range]).data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    object["id"] as? String == id
                {
                    return range
                }
            }
        } else if character == "[" {
            if depth == 0 { depth = 1 }
        }
        index = text.index(after: index)
    }
    return nil
}

parseArguments()
installSignalHandlers()
let allEntries = loadRegister()
if let markdownPath {
    writeMarkdown(allEntries, to: markdownPath)
    exit(0)
}
let entries = allEntries.filter { onlyID == nil || $0.id == onlyID }
if entries.isEmpty {
    if onlyID != nil { fail("no register entry has that id") }
    print("the register is empty, nothing to run")
    exit(0)
}
requireCleanTree()

let problems = validate(entries)
if !problems.isEmpty {
    for problem in problems { print("REGISTER ERROR \(problem)") }
    exit(2)
}

var rows: [(String, Outcome, Double)] = []
var baselineFailures: [String] = []
let started = Date()
for entry in entries.sorted(by: { $0.file < $1.file }) {
    if !baseline(entry) {
        baselineFailures.append(entry.id)
        continue
    }
    let begin = Date()
    let outcome = mutate(entry)
    rows.append((entry.id, outcome, Date().timeIntervalSince(begin)))
    let clean = git(["status", "--porcelain"]).output.trimmingCharacters(
        in: .whitespacesAndNewlines)
    if !clean.isEmpty { fail("the tree is not clean after \(entry.id):\n\(clean)", code: 3) }
}

print("id | result | seconds")
var unexpected = 0
for (id, outcome, seconds) in rows {
    print("\(id) | \(outcome.rawValue) | \(String(format: "%.1f", seconds))")
    if let entry = entries.first(where: { $0.id == id }), outcome != .survived, outcome != .invalid,
        outcome != entry.expectedOutcome
    {
        unexpected += 1
        print(
            "UNEXPECTED \(id): the register expects \(entry.expectedName) and the run gave \(outcome.rawValue)"
        )
    }
}
if shouldRecord { recordRuns(rows.map { (id: $0.0, outcome: $0.1) }) }
for id in baselineFailures { print("\(id) | BASELINE FAILED | 0.0") }
print("total seconds: \(String(format: "%.1f", Date().timeIntervalSince(started)))")
let bad =
    rows.filter { $0.1 == .survived || $0.1 == .invalid }.count + unexpected
    + baselineFailures.count
exit(bad == 0 ? 0 : 1)
