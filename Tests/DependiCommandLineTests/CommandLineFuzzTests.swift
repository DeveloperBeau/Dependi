import DependiCommandLine
import TestHelpers
import Testing

@Suite("Command line fuzz", .timeLimit(.minutes(5)))
struct CommandLineFuzzTests {
    private let parser = CommandLineParser()

    /// A reference grammar written by hand, apart from the parser. It names the outcome for any token list.
    private static func oracle(_ tokens: [String]) -> Result<Command, CommandLineError> {
        guard let name = tokens.first else { return .failure(.noCommand) }
        let rest = Array(tokens.dropFirst())
        let simple: [String: Command] = [
            "version": .version, "--version": .version, "help": .help,
            "--help": .help, "-h": .help,
        ]
        if name == "generate" {
            var forcesSinglePage = false
            for token in rest {
                if token == "--single-page" {
                    if forcesSinglePage {
                        return .failure(.duplicateFlag(command: name, flag: token))
                    }
                    forcesSinglePage = true
                } else if token.hasPrefix("-") {
                    return .failure(.unknownFlag(command: name, flag: token))
                } else {
                    return .failure(.unexpectedArgument(command: name, argument: token))
                }
            }
            return .success(.generate(forcesSinglePage: forcesSinglePage))
        }
        if let command = simple[name] {
            if let extra = rest.first {
                return .failure(.unexpectedArgument(command: name, argument: extra))
            }
            return .success(command)
        }
        guard name == "init" else { return .failure(.unknownCommand(name)) }
        var path: String?
        var dryRun = false
        var editsProject = false
        var position = 0
        while position < rest.count {
            let token = rest[position]
            if token == "--dry-run" {
                if dryRun { return .failure(.duplicateFlag(command: name, flag: token)) }
                dryRun = true
                position += 1
            } else if token == "--edit-project" {
                if editsProject { return .failure(.duplicateFlag(command: name, flag: token)) }
                editsProject = true
                position += 1
            } else if token == "--project" {
                if path != nil { return .failure(.duplicateFlag(command: name, flag: token)) }
                let value = position + 1 < rest.count ? rest[position + 1] : ""
                if value.isEmpty || value.hasPrefix("--") {
                    return .failure(.missingValue(command: name, flag: token))
                }
                path = value
                position += 2
            } else if token.hasPrefix("-") {
                return .failure(.unknownFlag(command: name, flag: token))
            } else {
                return .failure(.unexpectedArgument(command: name, argument: token))
            }
        }
        guard let path else {
            return .failure(.missingRequiredFlag(command: name, flag: "--project"))
        }
        return .success(
            .initialize(projectPath: path, isDryRun: dryRun, editsProject: editsProject))
    }

    private func check(
        _ arguments: [String], seed: UInt64, round: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let expected = Self.oracle(arguments)
        let message: Comment = "seed \(seed) round \(round): \(arguments)"
        do {
            let actual = try parser.parse(arguments)
            #expect(expected == .success(actual), message, sourceLocation: sourceLocation)
        } catch {
            #expect(expected == .failure(error), message, sourceLocation: sourceLocation)
        }
    }

    @Test("the oracle itself names the hand-written outcome for fixed lists")
    func oracleMatchesHandWrittenCases() {
        #expect(Self.oracle([]) == .failure(.noCommand))
        #expect(Self.oracle(["generate"]) == .success(.generate(forcesSinglePage: false)))
        #expect(
            Self.oracle(["generate", "--single-page"])
                == .success(.generate(forcesSinglePage: true)))
        #expect(
            Self.oracle(["generate", "--single-page", "--single-page"])
                == .failure(.duplicateFlag(command: "generate", flag: "--single-page")))
        #expect(
            Self.oracle(["generate", "--single-page=yes"])
                == .failure(.unknownFlag(command: "generate", flag: "--single-page=yes")))
        #expect(
            Self.oracle(["generate", "x"])
                == .failure(.unexpectedArgument(command: "generate", argument: "x")))
        #expect(
            Self.oracle(["init", "--project", "a", "--dry-run"])
                == .success(.initialize(projectPath: "a", isDryRun: true, editsProject: false)))
        #expect(
            Self.oracle(["init", "--project", "a", "--edit-project", "--edit-project"])
                == .failure(.duplicateFlag(command: "init", flag: "--edit-project")))
        #expect(
            Self.oracle(["init", "--project", "--dry-run"])
                == .failure(.missingValue(command: "init", flag: "--project")))
        #expect(Self.oracle(["Generate"]) == .failure(.unknownCommand("Generate")))
    }

    @Test("random token lists give the command or the error that the reference grammar names")
    func randomListsNeverCrash() {
        let alphabet = [
            "generate", "init", "version", "--version", "help", "-h", "--help", "--project",
            "--dry-run", "--edit-project", "--single-page", "--project=x", "x", "a b", "", "--", "-", "Generate",
            "日本",
        ]
        var generator = SeededGenerator()
        let seed = generator.seed
        var successes = 0
        for round in 0..<3000 {
            let count = Int.random(in: 0...6, using: &generator)
            let arguments = (0..<count).map { _ in alphabet.randomElement(using: &generator)! }
            if case .success = Self.oracle(arguments) { successes += 1 }
            check(arguments, seed: seed, round: round)
        }
        #expect(successes > 50, "seed \(seed): the fuzz reached too few valid lists")
    }

    @Test("lists built from a valid init template give the hand-written command")
    func validTemplatesGiveExpected() throws {
        var generator = SeededGenerator()
        let seed = generator.seed
        let paths = ["App", "My App/x", "../é/日本", "./a", "-q", "a=b", "tab\tname"]
        for round in 0..<1000 {
            let path = paths.randomElement(using: &generator)!
            let isDryRun = Bool.random(using: &generator)
            let editsProject = Bool.random(using: &generator)
            let dryRunFirst = Bool.random(using: &generator)
            var arguments = ["init"]
            if isDryRun && dryRunFirst { arguments.append("--dry-run") }
            arguments += ["--project", path]
            if isDryRun && !dryRunFirst { arguments.append("--dry-run") }
            if editsProject { arguments.append("--edit-project") }
            #expect(
                try parser.parse(arguments)
                    == .initialize(
                        projectPath: path, isDryRun: isDryRun, editsProject: editsProject),
                "seed \(seed) round \(round): \(arguments)")
        }
    }

    @Test("lists built from a valid generate template give the hand-written command")
    func validGenerateTemplatesGiveExpected() throws {
        var generator = SeededGenerator()
        let seed = generator.seed
        for round in 0..<200 {
            let forcesSinglePage = Bool.random(using: &generator)
            let arguments = forcesSinglePage ? ["generate", "--single-page"] : ["generate"]
            #expect(
                try parser.parse(arguments) == .generate(forcesSinglePage: forcesSinglePage),
                "seed \(seed) round \(round): \(arguments)")
        }
    }

    @Test("a generate list with a stray or repeated token is always refused")
    func generateStrayOrRepeatedIsRefused() {
        var generator = SeededGenerator()
        let seed = generator.seed
        let strays = [
            "extra", "--force", "-x", "--single-page=yes", "--singlepage", "Generate", "",
        ]
        for round in 0..<500 {
            var arguments = ["generate"]
            if Bool.random(using: &generator) {
                arguments.append("--single-page")
                arguments.insert(
                    Bool.random(using: &generator)
                        ? "--single-page" : strays.randomElement(using: &generator)!,
                    at: Int.random(in: 1...2, using: &generator))
            } else {
                arguments.append(strays.randomElement(using: &generator)!)
            }
            #expect(throws: CommandLineError.self, "seed \(seed) round \(round): \(arguments)") {
                _ = try parser.parse(arguments)
            }
        }
    }

    @Test("a valid list with one extra stray token is always refused")
    func strayTokenIsRefused() {
        var generator = SeededGenerator()
        let seed = generator.seed
        let strays = ["extra", "--force", "-x", "--project=y", "Generate"]
        for round in 0..<500 {
            let stray = strays.randomElement(using: &generator)!
            let position = Int.random(in: 1...5, using: &generator)
            var arguments = ["init", "--project", "App", "--dry-run"]
            arguments.insert(stray, at: min(position, arguments.count))
            #expect(throws: CommandLineError.self, "seed \(seed) round \(round): \(arguments)") {
                _ = try parser.parse(arguments)
            }
        }
    }

    @Test("arbitrary unicode tokens give the command or the error that the reference grammar names")
    func unicodeTokensNeverCrash() {
        var generator = SeededGenerator()
        let seed = generator.seed
        let known = ["init", "--project", "--dry-run", "generate", "--single-page"]
        for round in 0..<2000 {
            let count = Int.random(in: 0...4, using: &generator)
            let arguments: [String] = (0..<count).map { _ in
                // Some tokens are real keywords so the parser reaches its deeper branches.
                if Int.random(in: 0...3, using: &generator) == 0 {
                    return known.randomElement(using: &generator)!
                }
                var text = ""
                for _ in 0..<Int.random(in: 0...8, using: &generator) {
                    let value = UInt32.random(in: 0...0x10FFFF, using: &generator)
                    if let scalar = Unicode.Scalar(value) { text.unicodeScalars.append(scalar) }
                }
                return text
            }
            check(arguments, seed: seed, round: round)
        }
    }
}
