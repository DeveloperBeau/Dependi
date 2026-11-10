import Foundation

/// A `swift` command double for the runner tests. The runner finds it first on `PATH`.
///
/// The double records each call with its folder and answers from rules, so a runner test needs no
/// real build. A rule names a test key and a pattern. When a source file under `Sources` matches the
/// pattern, a test whose filter holds the key fails or hangs, and a build rule fails the build.
/// The rules copy what the real fixture package does, so each outcome has the same cause.
struct SwiftDouble {
    let folder: URL

    var logURL: URL { folder.appendingPathComponent("calls.log") }

    /// The listing of the fixture package, as `swift test list` prints it.
    static let listing = """
        MiniTests.MiniOtherTests/sharedName()
        MiniTests.MiniTests/brokenBaseline()
        MiniTests.MiniTests/countDownReachesZero()
        MiniTests.MiniTests/evenNumbersAreEven()
        MiniTests.MiniTests/evenNumbersAreEvenToo()
        MiniTests.MiniTests/sharedName()
        MiniTests.MiniTests/tripledTriples()

        """

    /// One line for each rule: the kind, the filter key and an extended regular expression.
    /// `brokenBaseline` fails on clean code, as the real fixture test does.
    static let rules =
        [
            "fail\tevenNumbersAreEven\\(\\)\tnumber % 2 == 1",
            "fail\tevenNumbersAreEvenToo\\(\\)\tnumber % 2 == 1",
            "fail\tevenNumbersAreEvenToo\\(\\)\tnumber != 0 &&",
            "fail\tMiniTests\\/sharedName\\(\\)\tnumber % 2 == 1",
            "fail\tbrokenBaseline\\(\\)\treturn 7",
            "fail\ttripledTriples\\(\\)\tnumber \\* 4",
            "hang\tcountDownReachesZero\\(\\)\tvalue \\+= 1",
            "build\t-\tnumber % 2 ==$",
        ].joined(separator: "\n") + "\n"

    /// A hang starts a child that leaves the process group, as the real test helper does. Its
    /// command line holds the folder, so a test can look for it.
    static let script = """
        #!/bin/sh
        here=$(dirname "$0")
        printf '%s\\t%s\\n' "$PWD" "$*" >>"$here/calls.log"
        matches() { grep -rqE -- "$1" Sources 2>/dev/null; }
        case "$1 $2" in
        "test list")
            cat "$here/listing.txt"
            exit 0
            ;;
        "build --build-tests")
            while IFS='\t' read -r kind key pattern; do
                if [ "$kind" = build ] && matches "$pattern"; then
                    echo "error: the double refused the build"
                    exit 1
                fi
            done <"$here/rules.txt"
            exit 0
            ;;
        "test --skip-build")
            filter=$4
            while IFS='\t' read -r kind key pattern; do
                case "$filter" in *"$key"*) ;; *) continue ;; esac
                matches "$pattern" || continue
                if [ "$kind" = fail ]; then
                    echo "✘ Test $key failed"
                    exit 1
                fi
                if [ "$kind" = hang ]; then
                    /usr/bin/perl -e 'setpgrp(0,0); sleep 1 while 1' "$PWD" &
                    while :; do sleep 1; done
                fi
            done <"$here/rules.txt"
            echo "✔ Test run passed"
            exit 0
            ;;
        esac
        echo "the double does not know: swift $*"
        exit 97

        """

    /// Writes the double into a new temporary folder.
    static func make() throws -> SwiftDouble {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-double-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tool = folder.appendingPathComponent("swift")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try listing.write(
            to: folder.appendingPathComponent("listing.txt"), atomically: true, encoding: .utf8)
        try rules.write(
            to: folder.appendingPathComponent("rules.txt"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("calls.log").path, contents: nil)
        return SwiftDouble(folder: folder)
    }

    /// The `PATH` setting that puts the double before the real tool.
    var pathSetting: String {
        "PATH=\(folder.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")"
    }

    /// The environment for a runner started with `Process`.
    var environment: [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["PATH"] = String(pathSetting.dropFirst("PATH=".count))
        return values
    }

    /// Each recorded call as its folder and its arguments.
    func calls() throws -> [(folder: String, arguments: String)] {
        try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
        }
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}
