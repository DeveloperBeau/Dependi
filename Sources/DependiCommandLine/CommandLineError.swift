/// The ways that reading the command line can fail.
public enum CommandLineError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No arguments were given.
    case noCommand
    /// The first argument is not a command.
    case unknownCommand(String)
    /// A flag is not known for the command.
    case unknownFlag(command: String, flag: String)
    /// A flag needs a value and has none.
    case missingValue(command: String, flag: String)
    /// A flag that the command requires is absent.
    case missingRequiredFlag(command: String, flag: String)
    /// The command takes no such argument.
    case unexpectedArgument(command: String, argument: String)
    /// A flag appears more than once.
    case duplicateFlag(command: String, flag: String)

    /// A one-line message that names the problem.
    public var description: String {
        switch self {
        case .noCommand:
            return "No command given."
        case .unknownCommand(let name):
            return "Unknown command '\(name)'."
        case .unknownFlag(let command, let flag):
            return "Unknown flag '\(flag)' for '\(command)'."
        case .missingValue(let command, let flag):
            return "Flag '\(flag)' for '\(command)' needs a value."
        case .missingRequiredFlag(let command, let flag):
            return "Command '\(command)' needs the flag '\(flag)'."
        case .unexpectedArgument(let command, let argument):
            return "Command '\(command)' does not take the argument '\(argument)'."
        case .duplicateFlag(let command, let flag):
            return "Flag '\(flag)' for '\(command)' is given more than once."
        }
    }
}
