import DependiDomain

/// Finds the Dependi source folder above a running program, if the program was built from a checkout.
enum SourceRootFinder {
    /// Walks up from the program's folder and returns the first folder that holds `Sources/DependiDomain`.
    static func find(from executablePath: String, files: any FileReading) -> String? {
        var parts = executablePath.split(separator: "/", omittingEmptySubsequences: true).map(
            String.init)
        while !parts.isEmpty {
            parts.removeLast()
            let folder = "/" + parts.joined(separator: "/")
            if files.exists(at: folder + "/Sources/DependiDomain") { return folder }
        }
        return nil
    }
}
