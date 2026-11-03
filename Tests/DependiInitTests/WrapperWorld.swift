import DependiInit
import Foundation

/// The outcome of one wrapper run.
struct WrapperRun {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// A wrapper run that has started and can be waited for.
final class RunningWrapper {
    private let process: Process
    private let outURL: URL
    private let errURL: URL

    init(process: Process, outURL: URL, errURL: URL) {
        self.process = process
        self.outURL = outURL
        self.errURL = errURL
    }

    /// Waits at most 120 seconds, then ends the process and reports status 255.
    func finish() -> WrapperRun {
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        var status = process.terminationStatus
        if process.isRunning {
            process.terminate()
            status = 255
        }
        let out = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        return WrapperRun(status: status, stdout: out, stderr: err)
    }
}

/// A temp project with stub tools. Stubs append their name and arguments to `calls.log`.
///
/// Layout under `root`: `proj/.dependi/run.sh`, `stubs/{git,xcrun}`, `ctl/` (flag files that
/// switch stub behavior), `cache/` (the cache root), `origin.git` (a bare repository).
final class WrapperWorld {
    let root: URL
    let project: URL
    let cache: URL
    let callLog: URL
    let envLog: URL
    let control: URL
    let stubs: URL
    let origin: URL
    private(set) var originHead = ""
    private let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("wrapper-" + UUID().uuidString)
        project = root.appendingPathComponent("proj")
        cache = root.appendingPathComponent("cache")
        callLog = root.appendingPathComponent("calls.log")
        envLog = root.appendingPathComponent("xcrun-env.log")
        control = root.appendingPathComponent("ctl")
        stubs = root.appendingPathComponent("stubs")
        origin = root.appendingPathComponent("origin.git")
        for folder in [project.appendingPathComponent(".dependi/bin"), control, stubs] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try fm.createDirectory(
            at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
        fm.createFile(atPath: callLog.path, contents: Data())
        try install(WrapperScript.text, at: project.appendingPathComponent(".dependi/run.sh"))
        try install(
            """
            #!/bin/sh
            echo "git $*" >> '\(callLog.path)'
            if [ "$1" = clone ] && [ -f '\(control.path)/fail-clone' ]; then
                echo 'clone refused' >&2
                exit 1
            fi
            if [ "$3" = rev-parse ] && [ -f '\(control.path)/lie-head' ]; then
                echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
                exit 0
            fi
            unset DEVELOPER_DIR SDKROOT
            exec /usr/bin/git "$@"
            """, at: stubs.appendingPathComponent("git"))
        try install(
            """
            #!/bin/sh
            echo "xcrun $*" >> '\(callLog.path)'
            env | sort >> '\(envLog.path)'
            if [ -f '\(control.path)/fail-build' ]; then
                echo 'compile error: boom' >&2
                exit 1
            fi
            if [ -f '\(control.path)/slow-build' ]; then
                sleep 1
            fi
            scratch=
            while [ $# -gt 0 ]; do
                if [ "$1" = --scratch-path ]; then scratch=$2; fi
                shift
            done
            mkdir -p "$scratch/release"
            printf '#!/bin/sh\\necho built-marker "$@"\\n' > "$scratch/release/dependi"
            chmod 755 "$scratch/release/dependi"
            """, at: stubs.appendingPathComponent("xcrun"))
        try install(
            """
            #!/bin/sh
            echo "dependi $*" >> '\(callLog.path)'
            echo installed-marker "$@"
            """, at: stubs.appendingPathComponent("installed-dependi"))
    }

    deinit {
        try? fm.removeItem(at: root)
    }

    private func install(_ text: String, at url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The wrapper under test.
    var script: URL { project.appendingPathComponent(".dependi/run.sh") }

    /// A commit hash that does not exist anywhere.
    static let missingCommit = String(repeating: "c", count: 40)

    /// Writes `.dependi.json` from a dictionary.
    func writeConfig(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: project.appendingPathComponent(".dependi.json"))
    }

    /// Puts the stub binary and a `VERSION` file with the given text in `.dependi/bin`.
    func installProjectBinary(contents: String) throws {
        let bin = project.appendingPathComponent(".dependi/bin")
        let stub = try String(contentsOf: stubs.appendingPathComponent("installed-dependi"))
        try install(stub, at: bin.appendingPathComponent("dependi"))
        try contents.write(
            to: bin.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
    }

    /// Sets a control flag that changes a stub.
    func flag(_ name: String) throws {
        fm.createFile(atPath: control.appendingPathComponent(name).path, contents: Data())
    }

    /// Creates the bare origin with one commit and returns the commit hash.
    @discardableResult
    func makeOrigin() throws -> String {
        let work = root.appendingPathComponent("work")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try git(["init", "--quiet"], in: work)
        try "package\n".write(
            to: work.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try git(["add", "file.txt"], in: work)
        try git(
            [
                "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m",
                "one",
            ],
            in: work)
        try git(["clone", "--quiet", "--bare", work.path, origin.path], in: root)
        originHead = try git(["rev-parse", "HEAD"], in: work).trimmingCharacters(
            in: .whitespacesAndNewlines)
        return originHead
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "HOME": root.appendingPathComponent("home").path, "PATH": "/usr/bin:/bin",
        ]
        let out = root.appendingPathComponent("git-\(UUID().uuidString).out")
        fm.createFile(atPath: out.path, contents: Data())
        process.standardOutput = try FileHandle(forWritingTo: out)
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return (try? String(contentsOf: out, encoding: .utf8)) ?? ""
    }

    /// The environment for a run that passes the gate and uses the stubs and the origin.
    func buildEnvironment(_ extra: [String: String] = [:]) -> [String: String] {
        var env = baseEnvironment(["ACTION": "install", "CONFIGURATION": "Release"])
        env["DEPENDI_TESTING"] = "1"
        env["DEPENDI_REPO_URL"] = origin.path
        env["DEPENDI_XCRUN"] = stubs.appendingPathComponent("xcrun").path
        for (key, value) in extra { env[key] = value }
        return env
    }

    /// A small environment: stubs first on `PATH`, a temp `HOME` and the temp cache root.
    func baseEnvironment(_ extra: [String: String] = [:]) -> [String: String] {
        var env = [
            "PATH": stubs.path + ":/usr/bin:/bin",
            "HOME": root.appendingPathComponent("home").path,
            "TMPDIR": root.path,
            "DEPENDI_CACHE_ROOT": cache.path,
        ]
        for (key, value) in extra { env[key] = value }
        return env
    }

    /// Starts the wrapper and returns at once.
    func start(environment: [String: String], arguments: [String] = []) throws -> RunningWrapper {
        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = root
        let outURL = root.appendingPathComponent("out-\(UUID().uuidString)")
        let errURL = root.appendingPathComponent("err-\(UUID().uuidString)")
        fm.createFile(atPath: outURL.path, contents: Data())
        fm.createFile(atPath: errURL.path, contents: Data())
        process.standardOutput = try FileHandle(forWritingTo: outURL)
        process.standardError = try FileHandle(forWritingTo: errURL)
        try process.run()
        return RunningWrapper(process: process, outURL: outURL, errURL: errURL)
    }

    /// Runs the wrapper to its end.
    func run(environment: [String: String], arguments: [String] = []) throws -> WrapperRun {
        try start(environment: environment, arguments: arguments).finish()
    }

    /// The recorded stub calls, one per line.
    func calls() -> [String] {
        let text = (try? String(contentsOf: callLog, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// The calls whose first word is the tool name.
    func calls(of tool: String) -> [String] {
        calls().filter { $0.hasPrefix(tool + " ") }
    }

    /// What is inside the cache root, by name.
    func cacheEntries() -> [String] {
        ((try? fm.contentsOfDirectory(atPath: cache.path)) ?? []).sorted()
    }

    /// Writes a cache entry for a pin. Pass a sha to override the real one.
    func seedCache(version: String, commit: String, sha: String?, writeSha: Bool = true) throws {
        let bin = cache.appendingPathComponent("\(version)-\(commit)/bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let body = "#!/bin/sh\necho cached-marker \"$@\"\n"
        try install(body, at: bin.appendingPathComponent("dependi"))
        if writeSha {
            let real = Self.sha256(of: Data(body.utf8))
            try ((sha ?? real) + "\n").write(
                to: bin.appendingPathComponent("dependi.sha256"), atomically: true, encoding: .utf8)
        }
    }

    private static func sha256(of data: Data) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try? process.run()
        input.fileHandleForWriting.write(data)
        try? input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: result, as: UTF8.self)
        return String(text.split(separator: " ").first ?? "")
    }
}
