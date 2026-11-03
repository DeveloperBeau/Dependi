import Foundation

/// Builds small package dumps and source files for the planted-violation tests.
enum Planted {
    static func target(
        _ name: String, type: String = "regular", dependsOn: [String] = [],
        products: [String] = [], features: Set<String> = ["ExistentialAny"]
    ) -> PackageDump.Target {
        PackageDump.Target(
            name: name, type: type, dependencyNames: dependsOn,
            externalProductNames: products, upcomingFeatures: features)
    }

    static func dump(
        _ targets: [PackageDump.Target], languages: [String] = ["6"]
    ) -> PackageDump {
        PackageDump(languageVersions: languages, targets: targets)
    }

    static func file(_ module: String, _ text: String, name: String = "File.swift") -> SourceFile {
        SourceFile(module: module, name: name, text: text)
    }

    /// A violation list reduced to rule names, for short assertions.
    static func rules(_ violations: [ArchitectureViolation]) -> [String] {
        violations.map(\.rule)
    }
}
