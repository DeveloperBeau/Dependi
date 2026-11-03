import DependiComposition
import DependiProcess
import Foundation

let application = DependiApplication(
    process: SystemProcessRunner(children: ChildProcessRegistry()), input: .standardInput,
    output: .standardOutput, error: .standardError,
    executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0],
    currentDirectory: FileManager.default.currentDirectoryPath)
exit(
    application.run(
        arguments: Array(CommandLine.arguments.dropFirst()),
        environment: ProcessInfo.processInfo.environment))
