import DependiComposition
import DependiProcess
import Foundation

let application = DependiApplication(
    process: SystemProcessRunner(), input: .standardInput, output: .standardOutput,
    error: .standardError)
exit(
    application.run(
        arguments: Array(CommandLine.arguments.dropFirst()),
        environment: ProcessInfo.processInfo.environment))
