/// Works out which traits of a package are on, the way SwiftPM does.
enum TraitExpansion {
    /// The requested traits and every trait that they enable, directly or through other traits.
    static func enabled(requested: Set<String>, definitions: [String: [String]]) -> Set<String> {
        var enabled: Set<String> = []
        var pending = Array(requested)
        while let name = pending.popLast() {
            guard enabled.insert(name).inserted else { continue }
            pending.append(contentsOf: definitions[name] ?? [])
        }
        return enabled
    }
}
