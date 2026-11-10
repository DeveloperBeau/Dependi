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
var changedSince: String?
var workerCount = defaultWorkerCount()
var shouldOnlyPlan = false
/// The exact filter for each entry id, filled by `validate`.
var filters: [String: String] = [:]
/// The file that is mutated in place in the package folder. Only a run with one worker sets it.
var mutatedFile: String?
/// Processes, worker copies and in-place state are shared with the signal handler, under this lock.
let stateLock = NSLock()
var activeProcessIDs: Set<Int32> = []
var workerFolders: [String] = []
var isShuttingDown = false
/// The shutdown itself runs `git` to restore a file, so only that thread may start a command.
var shutdownThread: Thread?
/// Held while a worker writes into its copy. The shutdown takes it and never gives it back, so no
/// write can put a file back into a copy after the shutdown removes it.
let copyLock = NSLock()

/// Half the performance cores, and at least one. Each worker runs its own compiler, so a full
/// count would starve the machine.
func defaultWorkerCount() -> Int {
    var cores: Int32 = 0
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) != 0 || cores <= 0 {
        cores = Int32(ProcessInfo.processInfo.activeProcessorCount)
    }
    return max(1, Int(cores) / 2)
}

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
        case "--changed-since": changedSince = value
        case "--plan": shouldOnlyPlan = value != "no"
        case "--workers":
            guard let count = Int(value), count >= 1, count <= 64 else {
                fail("--workers needs a whole number from 1 to 64, not \(value)")
            }
            workerCount = count
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
/// Each found process is stopped first, so it cannot start a child after the scan. The scan
/// repeats until it finds no new process, and only then are all of them killed.
func killTree(_ root: Int32) {
    kill(-root, SIGSTOP)
    kill(root, SIGSTOP)
    var found: [Int32] = [root]
    var isGrowing = true
    while isGrowing {
        isGrowing = false
        let table = processTable()
        for entry in table where found.contains(entry.parent) && !found.contains(entry.pid) {
            kill(entry.pid, SIGSTOP)
            found.append(entry.pid)
            isGrowing = true
        }
    }
    kill(-root, SIGKILL)
    for pid in found { kill(pid, SIGKILL) }
}

/// Runs a command in its own process group and kills the whole group on timeout.
func run(_ arguments: [String], timeout: Double, in folder: String = root) -> CommandResult {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mutate-\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: outputURL) }
    guard let sink = try? FileHandle(forWritingTo: outputURL) else { fail("cannot open output") }
    defer { try? sink.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "setpgrp(0,0); exec @ARGV or die $!;", "--"] + arguments
    process.currentDirectoryURL = URL(fileURLWithPath: folder)
    process.standardOutput = sink
    process.standardError = sink
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    stateLock.lock()
    if isShuttingDown && Thread.current != shutdownThread {
        stateLock.unlock()
        while true { sleep(60) }
    }
    do { try process.run() } catch {
        stateLock.unlock()
        fail("cannot start \(arguments[0]): \(error)")
    }
    let processID = process.processIdentifier
    activeProcessIDs.insert(processID)
    stateLock.unlock()
    defer {
        stateLock.lock()
        activeProcessIDs.remove(processID)
        stateLock.unlock()
    }
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

/// Stops every child, restores the file mutated in place, removes the worker copies and exits.
/// The first caller wins. A worker whose copy the shutdown removed must not exit with another code.
func shutDown(code: Int32) -> Never {
    stateLock.lock()
    if isShuttingDown {
        stateLock.unlock()
        while true { sleep(60) }
    }
    isShuttingDown = true
    shutdownThread = Thread.current
    let processIDs = activeProcessIDs
    let file = mutatedFile
    let folders = workerFolders
    stateLock.unlock()
    for pid in processIDs { killTree(pid) }
    if let file { restore(file) }
    copyLock.lock()
    stateLock.lock()
    let allFolders = Set(folders + workerFolders)
    stateLock.unlock()
    for folder in allFolders { try? FileManager.default.removeItem(atPath: folder) }
    // A worker can start a command between the first kill and the flag check in `run`.
    stateLock.lock()
    let lateProcessIDs = activeProcessIDs.subtracting(processIDs)
    stateLock.unlock()
    for pid in lateProcessIDs { killTree(pid) }
    exit(code)
}

func installSignalHandlers() {
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
        source.setEventHandler { shutDown(code: 130) }
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

/// A mutation may change production code, or the checker code of the architecture test, which has
/// no other home. A test file is never mutated.
func isMutableFile(_ relative: String) -> Bool {
    if relative.hasPrefix("/") || relative.contains("..") { return false }
    if relative.hasPrefix("Sources/") { return true }
    return relative.hasPrefix("Tests/ArchitectureTests/") && !relative.hasSuffix("Tests.swift")
        && relative.hasSuffix(".swift")
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
        if !isMutableFile(relative) {
            problems.append(
                "\(entry.id): file must be a relative path under Sources/ or an architecture checker file under Tests/ArchitectureTests/"
            )
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

/// Runs each distinct filter once on clean code. `swift test list` in `validate` built the tests,
/// so no baseline builds again.
func baselines(for entries: [Entry]) -> (passed: Set<String>, runs: Int) {
    var passed: Set<String> = []
    var seen: Set<String> = []
    for entry in entries {
        let filter = filters[entry.id] ?? entry.test
        guard seen.insert(filter).inserted else { continue }
        let result = run(
            ["swift", "test", "--skip-build", "--filter", filter], timeout: buildTimeoutSeconds)
        if result.status == 0 && !result.timedOut { passed.insert(filter) }
    }
    return (passed, seen.count)
}

/// One folder where mutants are built and run. A run with one worker mutates the package folder
/// itself. A run with more workers gives each worker a copy of the tracked files, so the package
/// folder is never mutated and each copy has its own build folder.
struct Workspace {
    let folder: String
    let isCopy: Bool
}

func makeCopy(index: Int) -> Workspace {
    copyLock.lock()
    defer { copyLock.unlock() }
    let folder = (NSTemporaryDirectory() as NSString).appendingPathComponent(
        "mutate-worker-\(UUID().uuidString)-\(index)")
    stateLock.lock()
    workerFolders.append(folder)
    stateLock.unlock()
    let listing = git(["ls-files", "-z"])
    if listing.status != 0 { fail("cannot list the tracked files") }
    let manager = FileManager.default
    for relative in listing.output.split(separator: "\0").map(String.init) {
        let source = (root as NSString).appendingPathComponent(relative)
        let target = (folder as NSString).appendingPathComponent(relative)
        do {
            try manager.createDirectory(
                atPath: (target as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try manager.copyItem(atPath: source, toPath: target)
        } catch { fail("cannot copy \(relative) for a worker: \(error)") }
    }
    return Workspace(folder: folder, isCopy: true)
}

/// Applies one mutation, builds, runs the named test and restores the file. The build is the only
/// build for this entry: the next entry's build also picks up this restore.
func mutate(_ entry: Entry, in workspace: Workspace) -> Outcome {
    let path = (workspace.folder as NSString).appendingPathComponent(entry.file)
    guard let original = try? String(contentsOfFile: path, encoding: .utf8) else { return .invalid }
    let mutated = original.replacingOccurrences(of: entry.search, with: entry.replace)
    if !workspace.isCopy {
        stateLock.lock()
        mutatedFile = entry.file
        stateLock.unlock()
    }
    defer {
        if workspace.isCopy {
            copyLock.lock()
            try? original.write(toFile: path, atomically: true, encoding: .utf8)
            copyLock.unlock()
            if (try? String(contentsOfFile: path, encoding: .utf8)) != original {
                FileHandle.standardError.write(
                    Data("cannot restore \(entry.file) in a copy\n".utf8))
                shutDown(code: 3)
            }
        } else {
            restore(entry.file)
            stateLock.lock()
            mutatedFile = nil
            stateLock.unlock()
        }
    }
    if workspace.isCopy { copyLock.lock() }
    let isWritten = (try? mutated.write(toFile: path, atomically: true, encoding: .utf8)) != nil
    if workspace.isCopy { copyLock.unlock() }
    if !isWritten { return .invalid }
    let build = run(
        ["swift", "build", "--build-tests"], timeout: buildTimeoutSeconds, in: workspace.folder)
    if build.status != 0 || build.timedOut { return .invalid }
    let test = run(
        ["swift", "test", "--skip-build", "--filter", filters[entry.id] ?? entry.test],
        timeout: timeoutSeconds, in: workspace.folder)
    if test.timedOut { return .killedByTimeout }
    if test.status == 0 { return .survived }
    let ranAndFailed = test.output.contains("✘ Test") || test.output.contains("error: -[")
    return ranAndFailed ? .killed : .invalid
}

/// Groups entries by file, in file order, and keeps register order inside a file. A worker takes
/// a whole group, so its builds stay incremental in one module.
func groupsByFile(_ entries: [Entry]) -> [[Entry]] {
    var order: [String] = []
    var byFile: [String: [Entry]] = [:]
    for entry in entries {
        if byFile[entry.file] == nil { order.append(entry.file) }
        byFile[entry.file, default: []].append(entry)
    }
    return order.sorted().compactMap { byFile[$0] }
}

/// The files that differ between a git ref and the working tree.
func filesChanged(since ref: String) -> Set<String> {
    let check = git(["rev-parse", "--verify", "--quiet", ref + "^{commit}"])
    if check.status != 0 { fail("--changed-since: \(ref) is not a commit") }
    let diff = git(["diff", "--name-only", ref, "--"])
    if diff.status != 0 { fail("--changed-since: git diff failed\n\(diff.output)") }
    return Set(diff.output.split(separator: "\n").map(String.init))
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
var entries = allEntries.filter { onlyID == nil || $0.id == onlyID }
if entries.isEmpty, onlyID != nil { fail("no register entry has that id") }
if let changedSince {
    let changed = filesChanged(since: changedSince)
    entries = entries.filter { changed.contains($0.file) }
    if entries.isEmpty {
        print("no register entry has a file that changed since \(changedSince), nothing to run")
        exit(0)
    }
}
if entries.isEmpty {
    print("the register is empty, nothing to run")
    exit(0)
}
let groups = groupsByFile(entries)
workerCount = min(workerCount, groups.count)
if shouldOnlyPlan {
    print("workers: \(workerCount)")
    for group in groups {
        print("GROUP \(group[0].file): \(group.map(\.id).joined(separator: ", "))")
    }
    var seenTests: [String] = []
    for entry in groups.joined() where !seenTests.contains(entry.test) {
        seenTests.append(entry.test)
    }
    for test in seenTests { print("BASELINE \(test)") }
    exit(0)
}
requireCleanTree()

let problems = validate(entries)
if !problems.isEmpty {
    for problem in problems { print("REGISTER ERROR \(problem)") }
    exit(2)
}

let started = Date()
let baseline = baselines(for: entries)
var baselineFailures: [String] = []
var queue: [[Entry]] = []
for group in groups {
    let runnable = group.filter { baseline.passed.contains(filters[$0.id] ?? $0.test) }
    baselineFailures += group.filter { !runnable.map(\.id).contains($0.id) }.map(\.id)
    if !runnable.isEmpty { queue.append(runnable) }
}
var results: [String: (Outcome, Double)] = [:]
let workers = DispatchGroup()
let startedWorkers = min(workerCount, queue.count)
for index in 0..<startedWorkers {
    workers.enter()
    Thread.detachNewThread {
        defer { workers.leave() }
        let workspace =
            workerCount == 1 ? Workspace(folder: root, isCopy: false) : makeCopy(index: index)
        while true {
            stateLock.lock()
            let next = queue.isEmpty ? nil : queue.removeFirst()
            stateLock.unlock()
            guard let group = next else { break }
            for entry in group {
                let begin = Date()
                let outcome = mutate(entry, in: workspace)
                stateLock.lock()
                results[entry.id] = (outcome, Date().timeIntervalSince(begin))
                stateLock.unlock()
                if !workspace.isCopy {
                    let clean = git(["status", "--porcelain"]).output.trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        FileHandle.standardError.write(
                            Data("the tree is not clean after \(entry.id):\n\(clean)\n".utf8))
                        shutDown(code: 3)
                    }
                }
            }
        }
        if workspace.isCopy {
            copyLock.lock()
            try? FileManager.default.removeItem(atPath: workspace.folder)
            copyLock.unlock()
        }
    }
}
workers.wait()
let rows = groups.joined().compactMap { entry in
    results[entry.id].map { (entry.id, $0.0, $0.1) }
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
print("baseline runs: \(baseline.runs)")
print("workers: \(workerCount)")
print("total seconds: \(String(format: "%.1f", Date().timeIntervalSince(started)))")
let bad =
    rows.filter { $0.1 == .survived || $0.1 == .invalid }.count + unexpected
    + baselineFailures.count
exit(bad == 0 ? 0 : 1)
