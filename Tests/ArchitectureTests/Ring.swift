/// The ring that a module belongs to.
enum Ring: String, CaseIterable {
    case entities
    case domain
    case infrastructure
    case features
    case composition
    case testSupport
}

/// The ring map and the rule for which ring may depend on which.
enum RingRules {
    /// Every module in the package and its ring. A module that is missing here is a violation.
    static let ringByModule: [String: Ring] = [
        "DependiEntities": .entities,
        "DependiDomain": .domain,
        "DependiFileSystem": .infrastructure,
        "DependiEnvironment": .infrastructure,
        "DependiProcess": .infrastructure,
        "DependiConsole": .infrastructure,
        "DependiWorkspaceState": .infrastructure,
        "DependiProjectFile": .infrastructure,
        "DependiPackageGraph": .infrastructure,
        "DependiSettingsBundle": .infrastructure,
        "DependiGenerate": .features,
        "DependiInit": .features,
        "DependiCommandLine": .features,
        "DependiComposition": .composition,
        "dependi": .composition,
        "DependiTestSupport": .testSupport,
        "TestHelpers": .testSupport,
    ]

    /// The rings that each ring may depend on. A module never depends on its own ring, except the executable, which calls the composition library.
    static let allowedRings: [Ring: Set<Ring>] = [
        .entities: [],
        .domain: [.entities],
        .infrastructure: [.entities, .domain],
        .features: [.entities, .domain],
        .composition: [.entities, .domain, .infrastructure, .features, .composition],
        .testSupport: [.entities, .domain],
    ]

    /// System modules that any module may import.
    static let baseSystemModules: Set<String> = ["Foundation", "CryptoKit"]

    /// Extra system modules that a single module may import.
    static let extraSystemModules: [String: Set<String>] = [
        "DependiProcess": ["Dispatch", "Darwin"],
        "DependiFileSystem": ["Darwin"],
    ]

    /// Returns whether a module may import the given system module.
    static func allowsSystemImport(_ system: String, in module: String) -> Bool {
        baseSystemModules.contains(system) || extraSystemModules[module]?.contains(system) == true
    }

    /// Returns whether a dependency from one module to another respects the rings.
    static func allowsDependency(from module: String, to dependency: String) -> Bool {
        guard let from = ringByModule[module], let to = ringByModule[dependency] else {
            return false
        }
        return allowedRings[from]?.contains(to) == true
    }
}
