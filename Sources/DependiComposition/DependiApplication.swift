import DependiCommandLine
import DependiConsole
import DependiDomain
import DependiEntities
import DependiEnvironment
import DependiFileSystem
import DependiGenerate
import DependiInit
import DependiProjectFile
import DependiSettingsBundle
import DependiWorkspaceState
import Foundation

/// The whole tool. It builds the real objects, runs one command and returns the exit code.
public struct DependiApplication {
    private let process: any ProcessRunning
    private let console: StandardConsole
    private let executablePath: String
    private let currentDirectory: String

    /// The exit code for a command line that cannot be parsed.
    public static let usageExitCode: Int32 = 64

    /// Creates the application. The process runner and the console handles come from outside.
    public init(
        process: any ProcessRunning, input: FileHandle, output: FileHandle, error: FileHandle,
        executablePath: String, currentDirectory: String
    ) {
        self.process = process
        self.console = StandardConsole(input: input, output: output, error: error)
        self.executablePath = executablePath
        self.currentDirectory = currentDirectory
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
        case .initialize(let path, let isDryRun):
            return initialize(path: path, isDryRun: isDryRun)
        }
    }

    private func initialize(path: String, isDryRun: Bool) -> Int32 {
        let disk = DiskFileSystem()
        let projects = ProjectFileReader(files: disk)
        let feature = InitFeature(
            files: disk, directories: disk, writer: disk, executables: disk, targets: projects,
            linkedProducts: projects, process: process, prompts: console, output: console,
            executablePath: executablePath,
            sourceRoot: SourceRootFinder.find(from: executablePath, files: disk),
            wrapperText: WrapperScript.text, version: DependiVersion.current)
        let absolute = path.hasPrefix("/") ? path : currentDirectory + "/" + path
        do {
            switch try feature.run(projectPath: absolute, isDryRun: isDryRun) {
            case .installed, .reported: return 0
            case .stopped(let reason):
                console.writeErrorLine("error: \(reason)")
                return 1
            }
        } catch {
            console.writeErrorLine("error: \(error)")
            return 1
        }
    }

    /// The configuration of the project, or the defaults if there is none. A broken file is
    /// reported later by the generate feature, which reads the same file before any process runs.
    private func configuration(environment: [String: String], files: DiskFileSystem)
        -> ToolConfiguration
    {
        if let directory = environment["PROJECT_DIR"],
            let loaded = try? ConfigurationLoader(files: files).load(projectDirectory: directory)
        {
            return loaded
        }
        return ToolConfiguration(
            excludes: [], manualEntries: [],
            gateConfigurations: ToolConfiguration.defaultGateConfigurations,
            sourcePackagesPath: nil, outputPath: nil, includeBuildTools: false,
            allowUnreached: false,
            processTimeoutSeconds: ToolConfiguration.defaultProcessTimeoutSeconds,
            runTimeoutSeconds: ToolConfiguration.defaultRunTimeoutSeconds, version: nil, commit: nil
        )
    }

    private func generate(environment: [String: String]) -> Int32 {
        let disk = DiskFileSystem()
        let settings = configuration(environment: environment, files: disk)
        let limited = DeadlineProcessRunner(
            wrapping: process, limitSeconds: settings.runTimeoutSeconds,
            now: { ProcessInfo.processInfo.systemUptime })
        let feature = GenerateFeature(
            environment: ProcessEnvironment(variables: environment), files: disk, directories: disk,
            dependencySource: WorkspaceStateReader(files: disk, directories: disk),
            linkedProducts: ProjectFileReader(files: disk),
            manifests: LazyManifestReader(
                environment: environment, configuration: settings, process: limited, files: disk,
                directories: disk, writer: disk),
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
