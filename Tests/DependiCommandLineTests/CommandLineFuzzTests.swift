import DependiCommandLine
import TestHelpers
import Testing

@Suite("Command line fuzz")
struct CommandLineFuzzTests {
    private let parser = CommandLineParser()

    @Test("random token lists either give a command or a command line error")
    func randomListsNeverCrash() {
        let alphabet = [
            "generate", "init", "version", "--version", "help", "-h", "--help", "--project",
            "--dry-run", "--project=x", "x", "a b", "", "--", "-", "Generate", "日本",
        ]
        var generator = SeededGenerator()
        for round in 0..<3000 {
            let count = Int.random(in: 0...6, using: &generator)
            let arguments = (0..<count).map { _ in alphabet.randomElement(using: &generator)! }
            do {
                _ = try parser.parse(arguments)
            } catch let error as CommandLineError {
                #expect(!error.description.isEmpty, "round \(round): \(arguments)")
            } catch {
                Issue.record("round \(round): not a CommandLineError for \(arguments)")
            }
        }
    }

    @Test("lists built from a valid init template give the hand-written command")
    func validTemplatesGiveExpected() throws {
        var generator = SeededGenerator()
        let paths = ["App", "My App/x", "../é/日本", "./a", "-q", "a=b", "tab\tname"]
        for round in 0..<1000 {
            let path = paths.randomElement(using: &generator)!
            let isDryRun = Bool.random(using: &generator)
            let dryRunFirst = Bool.random(using: &generator)
            var arguments = ["init"]
            if isDryRun && dryRunFirst { arguments.append("--dry-run") }
            arguments += ["--project", path]
            if isDryRun && !dryRunFirst { arguments.append("--dry-run") }
            #expect(
                try parser.parse(arguments) == .initialize(projectPath: path, isDryRun: isDryRun),
                "round \(round): \(arguments)")
        }
    }

    @Test("a valid list with one extra stray token is always refused")
    func strayTokenIsRefused() {
        var generator = SeededGenerator()
        let strays = ["extra", "--force", "-x", "--project=y", "Generate"]
        for round in 0..<500 {
            let stray = strays.randomElement(using: &generator)!
            let position = Int.random(in: 1...5, using: &generator)
            var arguments = ["init", "--project", "App", "--dry-run"]
            arguments.insert(stray, at: min(position, arguments.count))
            #expect(throws: CommandLineError.self, "round \(round): \(arguments)") {
                _ = try parser.parse(arguments)
            }
        }
    }

    @Test("arbitrary unicode tokens never crash the parser")
    func unicodeTokensNeverCrash() {
        var generator = SeededGenerator()
        for round in 0..<2000 {
            let count = Int.random(in: 0...4, using: &generator)
            let arguments: [String] = (0..<count).map { _ in
                var text = ""
                for _ in 0..<Int.random(in: 0...8, using: &generator) {
                    let value = UInt32.random(in: 0...0x10FFFF, using: &generator)
                    if let scalar = Unicode.Scalar(value) { text.unicodeScalars.append(scalar) }
                }
                return text
            }
            do {
                _ = try parser.parse(arguments)
            } catch {
                #expect(error is CommandLineError, "round \(round)")
            }
        }
    }
}
