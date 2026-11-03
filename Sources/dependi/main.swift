import DependiComposition
import DependiProcess
import Foundation

let children = ChildProcessRegistry()
// A signal never reaches the children, because each one leads its own process group.
let termination = TerminationHandler(signals: [SIGINT, SIGTERM, SIGHUP]) { number in
    children.terminateAll()
    exit(128 + number)
}
termination.start()

let application = DependiApplication(
    process: SystemProcessRunner(children: children), input: .standardInput,
    output: .standardOutput, error: .standardError,
    executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0],
    currentDirectory: FileManager.default.currentDirectoryPath)
exit(
    application.run(
        arguments: Array(CommandLine.arguments.dropFirst()),
        environment: ProcessInfo.processInfo.environment))
