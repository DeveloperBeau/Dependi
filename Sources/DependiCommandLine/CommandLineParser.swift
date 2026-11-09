/// Turns the program arguments into a command. It does no input or output.
public struct CommandLineParser: Sendable {
    /// Creates a parser.
    public init() {}

    /// Reads the arguments, which exclude the program name, and returns the command.
    public func parse(_ arguments: [String]) throws(CommandLineError) -> Command {
        guard let name = arguments.first else {
            throw CommandLineError.noCommand
        }
        let rest = Array(arguments.dropFirst())
        switch name {
        case "generate":
            try rejectArguments(rest, command: name)
            return .generate
        case "--version", "version":
            try rejectArguments(rest, command: name)
            return .version
        case "help", "--help", "-h":
            try rejectArguments(rest, command: name)
            return .help
        case "init":
            return try parseInitialize(rest, command: name)
        default:
            throw CommandLineError.unknownCommand(name)
        }
    }

    private func rejectArguments(_ rest: [String], command: String) throws(CommandLineError) {
        if let first = rest.first {
            throw CommandLineError.unexpectedArgument(command: command, argument: first)
        }
    }

    private func parseInitialize(_ rest: [String], command: String) throws(CommandLineError)
        -> Command
    {
        var projectPath: String?
        var isDryRun = false
        var index = 0
        while index < rest.count {
            let token = rest[index]
            switch token {
            case "--project":
                if projectPath != nil {
                    throw CommandLineError.duplicateFlag(command: command, flag: token)
                }
                let valueIndex = index + 1
                guard valueIndex < rest.count, !rest[valueIndex].isEmpty,
                    !rest[valueIndex].hasPrefix("--")
                else {
                    throw CommandLineError.missingValue(command: command, flag: token)
                }
                projectPath = rest[valueIndex]
                index += 2
            case "--dry-run":
                if isDryRun {
                    throw CommandLineError.duplicateFlag(command: command, flag: token)
                }
                isDryRun = true
                index += 1
            default:
                if token.hasPrefix("-") {
                    throw CommandLineError.unknownFlag(command: command, flag: token)
                }
                throw CommandLineError.unexpectedArgument(command: command, argument: token)
            }
        }
        guard let projectPath else {
            throw CommandLineError.missingRequiredFlag(command: command, flag: "--project")
        }
        return .initialize(projectPath: projectPath, isDryRun: isDryRun)
    }
}
