import DependiEntities

/// Decides whether Dependi runs for a build.
public struct ReleaseGate: Sendable {
    /// Creates a gate.
    public init() {}

    /// Returns the decision. An archive (`install`) runs. A configuration in the gate list runs.
    /// A configuration that cannot be read fails an archive and skips any other build.
    public func decision(
        context: BuildContext, configuration: Result<ToolConfiguration, DomainError>
    ) throws(DomainError) -> GateDecision {
        let insideXcode = context.targetBuildDirectory != nil
        guard let action = context.action else {
            if insideXcode { throw .buildContextIncomplete(missing: ["ACTION"]) }
            return .skip(reason: "not run by Xcode")
        }
        let isArchive = action == "install"
        switch configuration {
        case .failure(let error):
            if isArchive { throw error }
            return .skip(reason: "the configuration cannot be read: \(error)")
        case .success(let settings):
            if isArchive { return .run(reason: "archive build") }
            if let name = context.configuration, settings.gateConfigurations.contains(name) {
                return .run(reason: "configuration \(name) is in the gate list")
            }
            return .skip(
                reason: "configuration \(context.configuration ?? "(none)") is not in the gate list"
            )
        }
    }
}
