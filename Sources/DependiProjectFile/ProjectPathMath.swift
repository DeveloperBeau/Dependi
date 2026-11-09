/// Pure text operations on paths. They never touch the file system.
enum ProjectPathMath {
    /// Joins a base folder and a relative path, then removes `.` and `..` parts.
    static func resolve(_ relative: String, against base: String) -> String {
        standardize(relative.hasPrefix("/") ? relative : base + "/" + relative)
    }

    /// Removes empty, `.` and `..` components from an absolute path.
    static func standardize(_ path: String) -> String {
        var parts: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." {
                _ = parts.popLast()
            } else {
                parts.append(component)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Returns the path without its last component.
    static func parent(of path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).dropLast()
        return "/" + parts.joined(separator: "/")
    }
}
