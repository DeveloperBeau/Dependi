/// One broken architecture rule at one place.
struct ArchitectureViolation: Equatable, CustomStringConvertible {
    /// The short name of the broken rule.
    let rule: String
    /// The module or file where the rule is broken.
    let location: String
    /// What is wrong.
    let detail: String

    var description: String { "[\(rule)] \(location): \(detail)" }
}

/// One Swift source file that belongs to a module.
struct SourceFile {
    let module: String
    let name: String
    let text: String
}
