import Foundation

/// Applies every architecture rule to a package dump and its sources.
enum ArchitectureChecker {
    /// Returns every violation found. An empty list means the architecture holds.
    static func check(dump: PackageDump, sources: [SourceFile]) -> [ArchitectureViolation] {
        checkLanguageSettings(dump: dump)
            + checkRingMap(dump: dump, sources: sources)
            + checkDeclaredDependencies(dump: dump)
            + checkImports(dump: dump, sources: sources)
            + checkSourceRules(sources: sources)
    }

    private static func productionTargets(_ dump: PackageDump) -> [PackageDump.Target] {
        dump.targets.filter { $0.type != "test" }
    }

    /// Every target must use Swift 6 mode and `ExistentialAny`.
    static func checkLanguageSettings(dump: PackageDump) -> [ArchitectureViolation] {
        var result: [ArchitectureViolation] = []
        if !dump.languageVersions.contains("6") {
            result.append(
                .init(
                    rule: "swift6", location: "package", detail: "Swift 6 language mode is not set")
            )
        }
        for target in dump.targets where !target.upcomingFeatures.contains("ExistentialAny") {
            result.append(
                .init(
                    rule: "existentialAny", location: target.name,
                    detail: "ExistentialAny is not enabled"))
        }
        return result
    }

    /// Every production target and every source folder must be in the ring map.
    static func checkRingMap(dump: PackageDump, sources: [SourceFile]) -> [ArchitectureViolation] {
        var names = Set(productionTargets(dump).map(\.name))
        names.formUnion(sources.map(\.module))
        return names.sorted().compactMap { name in
            RingRules.ringByModule[name] == nil
                ? .init(
                    rule: "ringMap", location: name, detail: "the module is not in the ring map")
                : nil
        }
    }

    /// Declared target dependencies must respect the rings and use no third-party product.
    static func checkDeclaredDependencies(dump: PackageDump) -> [ArchitectureViolation] {
        var result: [ArchitectureViolation] = []
        for target in productionTargets(dump) {
            for dependency in target.dependencyNames
            where !RingRules.allowsDependency(from: target.name, to: dependency) {
                result.append(
                    .init(
                        rule: "ringEdge", location: target.name,
                        detail: "declares a dependency on \(dependency), which its ring may not use"
                    ))
            }
            for product in target.externalProductNames {
                result.append(
                    .init(
                        rule: "thirdParty", location: target.name,
                        detail: "declares the external product \(product)"))
            }
        }
        return result
    }

    /// Imports must be declared, must respect the rings and must be known.
    static func checkImports(dump: PackageDump, sources: [SourceFile]) -> [ArchitectureViolation] {
        let declared = Dictionary(
            uniqueKeysWithValues: productionTargets(dump).map { ($0.name, Set($0.dependencyNames)) }
        )
        var result: [ArchitectureViolation] = []
        for file in sources {
            for imported in Set(ImportScanner.importedModules(in: file.text)).sorted() {
                let location = "\(file.module)/\(file.name)"
                if imported == "DependiTestSupport" && file.module != "DependiTestSupport" {
                    result.append(
                        .init(
                            rule: "testSupportImport", location: location,
                            detail: "production code imports DependiTestSupport"))
                } else if RingRules.ringByModule[imported] != nil {
                    if !RingRules.allowsDependency(from: file.module, to: imported) {
                        result.append(
                            .init(
                                rule: "ringEdge", location: location,
                                detail: "imports \(imported), which its ring may not use"))
                    } else if declared[file.module]?.contains(imported) != true {
                        result.append(
                            .init(
                                rule: "undeclaredImport", location: location,
                                detail: "imports \(imported) without declaring it"))
                    }
                } else if !RingRules.allowsSystemImport(imported, in: file.module) {
                    result.append(
                        .init(
                            rule: "unknownImport", location: location,
                            detail: "imports \(imported), which is not allowed here"))
                }
            }
        }
        return result
    }

    /// Source text rules: one public type, doc comments, defaults, errors and forbidden text.
    static func checkSourceRules(sources: [SourceFile]) -> [ArchitectureViolation] {
        var result: [ArchitectureViolation] = []
        var errorEnumsByModule: [String: Int] = [:]
        for file in sources {
            let location = "\(file.module)/\(file.name)"
            let typeCount = SourceRules.topLevelPublicTypeCount(in: file.text)
            if typeCount > 1 {
                result.append(
                    .init(
                        rule: "onePublicType", location: location,
                        detail: "declares \(typeCount) public types"))
            }
            for line in SourceRules.undocumentedPublicDeclarationLines(in: file.text) {
                result.append(
                    .init(
                        rule: "docComment", location: "\(location):\(line)",
                        detail: "a public declaration has no doc comment"))
            }
            for parameter in SourceRules.collaboratorDefaults(in: file.text) {
                result.append(
                    .init(
                        rule: "collaboratorDefault", location: location,
                        detail: "a collaborator has a default value: \(parameter)"))
            }
            errorEnumsByModule[file.module, default: 0] += SourceRules.errorEnumCount(in: file.text)
            if file.module == "DependiDomain" {
                let untyped = SourceRules.untypedThrowsCount(in: file.text)
                if untyped > 0 {
                    result.append(
                        .init(
                            rule: "typedThrows", location: location,
                            detail: "\(untyped) use of throws without an error type"))
                }
            }
            for fragment in SourceRules.forbiddenFragments(in: file.text) {
                result.append(
                    .init(rule: "forbiddenText", location: location, detail: "contains \(fragment)")
                )
            }
        }
        for (module, count) in errorEnumsByModule.sorted(by: { $0.key < $1.key }) where count > 1 {
            result.append(
                .init(
                    rule: "oneErrorEnum", location: module,
                    detail: "declares \(count) error enumerations"))
        }
        return result
    }
}
