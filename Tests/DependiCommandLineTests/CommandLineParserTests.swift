import DependiCommandLine
import Testing

@Suite("Command line parser", .timeLimit(.minutes(1)))
struct CommandLineParserTests {
    private let parser = CommandLineParser()

    private func error(_ arguments: [String]) -> CommandLineError? {
        do {
            _ = try parser.parse(arguments)
            return nil
        } catch {
            return error
        }
    }

    @Test("every row of the command table is accepted and gives the hand-written command")
    func tableRowsAreAccepted() throws {
        let table: [([String], Command)] = [
            (["generate"], .generate),
            (["init", "--project", "App"], .initialize(projectPath: "App", isDryRun: false)),
            (
                ["init", "--project", "App", "--dry-run"],
                .initialize(projectPath: "App", isDryRun: true)
            ),
            (
                ["init", "--dry-run", "--project", "App"],
                .initialize(projectPath: "App", isDryRun: true)
            ),
            (["--version"], .version),
            (["version"], .version),
            (["help"], .help),
            (["--help"], .help),
            (["-h"], .help),
        ]
        for (arguments, expected) in table {
            #expect(try parser.parse(arguments) == expected, "arguments: \(arguments)")
        }
    }

    @Test("paths with spaces, unicode and relative parts are kept as written")
    func pathsAreKept() throws {
        for path in ["My App/App.xcodeproj", "../Prøjekt/日本語", "./a", "-single", "a=b"] {
            #expect(
                try parser.parse(["init", "--project", path])
                    == .initialize(projectPath: path, isDryRun: false))
        }
    }

    @Test("no arguments is refused as no command")
    func noArguments() {
        #expect(error([]) == .noCommand)
    }

    @Test("an extra argument after a command that takes none is refused")
    func extraArguments() {
        #expect(
            error(["generate", "x"]) == .unexpectedArgument(command: "generate", argument: "x"))
        #expect(
            error(["--version", "--dry-run"])
                == .unexpectedArgument(command: "--version", argument: "--dry-run"))
        #expect(error(["version", "x"]) == .unexpectedArgument(command: "version", argument: "x"))
        #expect(error(["help", "init"]) == .unexpectedArgument(command: "help", argument: "init"))
        #expect(error(["-h", "x"]) == .unexpectedArgument(command: "-h", argument: "x"))
        #expect(error(["--help", "x"]) == .unexpectedArgument(command: "--help", argument: "x"))
        #expect(
            error(["init", "--project", "a", "extra"])
                == .unexpectedArgument(command: "init", argument: "extra"))
    }

    @Test("a missing, empty or dashed project value is refused")
    func missingValues() {
        let expected = CommandLineError.missingValue(command: "init", flag: "--project")
        #expect(error(["init", "--project"]) == expected)
        #expect(error(["init", "--project", ""]) == expected)
        #expect(error(["init", "--project", "--dry-run"]) == expected)
        #expect(error(["init", "--project", "--other"]) == expected)
        #expect(error(["init", "--dry-run", "--project"]) == expected)
    }

    @Test("a missing project flag is refused")
    func missingRequired() {
        let expected = CommandLineError.missingRequiredFlag(command: "init", flag: "--project")
        #expect(error(["init"]) == expected)
        #expect(error(["init", "--dry-run"]) == expected)
    }

    @Test("a repeated flag is refused")
    func duplicates() {
        #expect(
            error(["init", "--project", "a", "--project", "b"])
                == .duplicateFlag(command: "init", flag: "--project"))
        #expect(
            error(["init", "--project", "a", "--dry-run", "--dry-run"])
                == .duplicateFlag(command: "init", flag: "--dry-run"))
        #expect(
            error(["init", "--dry-run", "--project", "a", "--dry-run"])
                == .duplicateFlag(command: "init", flag: "--dry-run"))
    }

    @Test("unknown flags and the equals form are refused")
    func unknownFlags() {
        #expect(
            error(["init", "--project=x"]) == .unknownFlag(command: "init", flag: "--project=x"))
        #expect(
            error(["init", "--project", "a", "--force"])
                == .unknownFlag(command: "init", flag: "--force"))
        #expect(error(["init", "-p", "a"]) == .unknownFlag(command: "init", flag: "-p"))
        #expect(
            error(["init", "--Project", "a"]) == .unknownFlag(command: "init", flag: "--Project"))
        #expect(
            error(["init", "--dry-run=true"])
                == .unknownFlag(command: "init", flag: "--dry-run=true"))
    }

    @Test("look-alike commands are refused")
    func lookAlikes() {
        for name in [
            "Generate", "gen", "generate ", " generate", "GENERATE", "Init", "initialize", "init ",
            "--Version", "-version", "-v", "--generate", "Help", "-help", "--h", "", "--",
        ] {
            #expect(error([name]) == .unknownCommand(name), "name: '\(name)'")
        }
    }

    @Test("a flag before the command is refused as an unknown command")
    func flagFirst() {
        #expect(error(["--dry-run", "init"]) == .unknownCommand("--dry-run"))
        #expect(error(["--project", "a", "init"]) == .unknownCommand("--project"))
    }

    @Test("every error has a message that names what is wrong")
    func messages() {
        #expect(CommandLineError.noCommand.description == "No command given.")
        #expect(CommandLineError.unknownCommand("x").description == "Unknown command 'x'.")
        #expect(
            CommandLineError.unknownFlag(command: "init", flag: "-p").description
                == "Unknown flag '-p' for 'init'.")
        #expect(
            CommandLineError.missingValue(command: "init", flag: "--project").description
                == "Flag '--project' for 'init' needs a value.")
        #expect(
            CommandLineError.missingRequiredFlag(command: "init", flag: "--project").description
                == "Command 'init' needs the flag '--project'.")
        #expect(
            CommandLineError.unexpectedArgument(command: "generate", argument: "x").description
                == "Command 'generate' does not take the argument 'x'.")
        #expect(
            CommandLineError.duplicateFlag(command: "init", flag: "--dry-run").description
                == "Flag '--dry-run' for 'init' is given more than once.")
    }

    @Test("the usage text mentions every command, alias and flag")
    func usageMentionsEverything() {
        for word in [
            "generate", "init", "version", "--version", "help", "--help", "-h", "--project",
            "--dry-run", "<path>",
        ] {
            #expect(UsageText.text.contains(word), "missing: \(word)")
        }
    }
}
