import DependiCommandLine
import DependiConsole
import DependiDomain
import DependiEnvironment
import DependiFileSystem
import DependiGenerate
import DependiProjectFile
import DependiSettingsBundle
import DependiWorkspaceState
import Foundation

/// The whole tool. It builds the real objects, runs one command and returns the exit code.
public struct DependiApplication {
    private let process: any ProcessRunning
    private let console: StandardConsole

    /// The exit code for a command line that cannot be parsed.
    public static let usageExitCode: Int32 = 64
    /// The exit code for a command that is not available yet.
    public static let unavailableExitCode: Int32 = 70

    /// Creates the application. The process runner and the console handles come from outside.
    public init(
        process: any ProcessRunning, input: FileHandle, output: FileHandle, error: FileHandle
    ) {
        self.process = process
        self.console = StandardConsole(input: input, output: output, error: error)
    }

    /// Runs the command in `arguments` (without the program name) and returns the exit code.
    public func run(arguments: [String], environment: [String: String]) -> Int32 {
        let command: Command
        do {
            command = try CommandLineParser().parse(arguments)
        } catch {
            console.writeErrorLine("error: \(error)")
            console.writeErrorLine(UsageText.text)
            return Self.usageExitCode
        }
        switch command {
        case .help:
            console.writeLine(UsageText.text)
            return 0
        case .version:
            console.writeLine("dependi \(DependiVersion.current)")
            return 0
        case .generate:
            return generate(environment: environment)
        case .initialize:
            console.writeErrorLine("error: the init command is not available in this build.")
            return Self.unavailableExitCode
        }
    }

    private func generate(environment: [String: String]) -> Int32 {
        let disk = DiskFileSystem()
        let feature = GenerateFeature(
            environment: ProcessEnvironment(variables: environment), files: disk, directories: disk,
            dependencySource: WorkspaceStateReader(files: disk, directories: disk),
            linkedProducts: ProjectFileReader(files: disk),
            manifests: LazyManifestReader(
                environment: environment, process: process, files: disk, directories: disk,
                writer: disk),
            writer: SettingsBundleWriter(
                files: disk, directories: disk, writer: disk, slugger: OutputNameSlugger()),
            output: console)
        do {
            _ = try feature.run()
            return 0
        } catch {
            console.writeErrorLine("error: \(error)")
            return 1
        }
    }
}
