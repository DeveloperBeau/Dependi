import DependiDomain
import DependiEntities
import TestHelpers
import Testing

@Suite("Release gate", .timeLimit(.minutes(1)))
struct ReleaseGateTests {
    private let gate = ReleaseGate()

    private func context(action: String?, configuration: String?, inXcode: Bool = true)
        -> BuildContext
    {
        BuildContext(
            configuration: configuration, action: action, platformName: nil, targetName: nil,
            projectFilePath: nil, projectDirectory: nil, buildDirectory: nil,
            targetBuildDirectory: inXcode ? "/product" : nil, unlocalizedResourcesFolderPath: nil,
            wrapperName: nil, isScriptSandboxEnabled: nil)
    }

    private func settings(gate: [String] = ["Release"]) -> ToolConfiguration {
        ToolConfiguration(
            excludes: [], manualEntries: [], gateConfigurations: gate, sourcePackagesPath: nil,
            outputPath: nil, includeBuildTools: false, allowUnreached: false,
            processTimeoutSeconds: 60,
            runTimeoutSeconds: 300, version: nil, commit: nil)
    }

    @Test("an archive runs, whatever the configuration is called")
    func archiveRuns() throws {
        for name in ["Release", "Debug", "AppStore", nil] as [String?] {
            let decision = try gate.decision(
                context: context(action: "install", configuration: name),
                configuration: .success(settings()))
            #expect(decision == .run(reason: "archive build"))
        }
    }

    @Test("a build in a configuration of the gate list runs")
    func listedConfigurationRuns() throws {
        let decision = try gate.decision(
            context: context(action: "build", configuration: "AppStore"),
            configuration: .success(settings(gate: ["Release", "AppStore"])))
        #expect(decision == .run(reason: "configuration AppStore is in the gate list"))
    }

    @Test("a Debug build and a name that differs only in case skip")
    func otherConfigurationsSkip() throws {
        for name in ["Debug", "release", "RELEASE", "Release "] {
            let decision = try gate.decision(
                context: context(action: "build", configuration: name),
                configuration: .success(settings()))
            guard case .skip = decision else {
                Issue.record("\(name) was not skipped: \(decision)")
                continue
            }
        }
    }

    @Test("an empty gate list means archive only")
    func emptyGateList() throws {
        let empty = settings(gate: [])
        #expect(
            try gate.decision(
                context: context(action: "build", configuration: "Release"),
                configuration: .success(empty))
                == .skip(reason: "configuration Release is not in the gate list"))
        #expect(
            try gate.decision(
                context: context(action: "install", configuration: "Release"),
                configuration: .success(empty))
                == .run(reason: "archive build"))
    }

    @Test("a missing action inside Xcode fails and outside Xcode skips")
    func missingAction() throws {
        #expect(throws: DomainError.buildContextIncomplete(missing: ["ACTION"])) {
            try gate.decision(
                context: context(action: nil, configuration: "Release"),
                configuration: .success(settings()))
        }
        let outside = try gate.decision(
            context: context(action: nil, configuration: nil, inXcode: false),
            configuration: .success(settings()))
        #expect(outside == .skip(reason: "not run by Xcode"))
    }

    @Test("an unreadable configuration fails an archive")
    func unreadableConfigurationOnArchiveFails() {
        let error = DomainError.configurationCorrupt(
            path: "/p/.dependi.json", reason: "unknown key x")
        #expect(throws: error) {
            try gate.decision(
                context: context(action: "install", configuration: "Release"),
                configuration: .failure(error))
        }
    }

    @Test("an unreadable configuration skips a build action even in a configuration that would run")
    func unreadableConfigurationOnBuildSkips() throws {
        let error = DomainError.fileNotFound(path: "/p/.dependi.json")
        let decision = try gate.decision(
            context: context(action: "build", configuration: "Release"),
            configuration: .failure(error))
        guard case .skip(let reason) = decision else {
            Issue.record("expected a skip but got \(decision)")
            return
        }
        #expect(reason.contains("cannot be read"))
    }

    @Test("fuzz: the gate runs if and only if the action is install or the configuration is listed")
    func fuzzRule() throws {
        let actions = ["build", "install", "clean", "analyze"]
        let configurations = ["Release", "Debug", "AppStore", "release", "Beta"]
        var generator = SeededGenerator()
        for _ in 0..<400 {
            let action = actions.randomElement(using: &generator)!
            let name = configurations.randomElement(using: &generator)!
            let listed = configurations.shuffled(using: &generator).prefix(
                Int.random(in: 0...3, using: &generator))
            let decision = try gate.decision(
                context: context(action: action, configuration: name),
                configuration: .success(settings(gate: Array(listed))))
            let expected = action == "install" || listed.contains(name)
            let ran: Bool
            if case .run = decision { ran = true } else { ran = false }
            #expect(ran == expected, "action \(action) configuration \(name) list \(listed)")
        }
    }
}
