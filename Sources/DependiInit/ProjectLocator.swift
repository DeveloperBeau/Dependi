import DependiDomain

/// Finds the project from the path that the user gave. It accepts the project folder, an `.xcodeproj`
/// or the `.xcworkspace` that sits next to one.
struct ProjectLocator {
    let files: any FileReading
    let directories: any DirectoryListing
    let prompts: any Prompting

    private func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[..<slash])
    }

    private func name(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    func locate(_ given: String) throws(DomainError) -> ProjectLocation {
        let real: String
        do {
            real = try files.realPath(of: given)
        } catch .fileNotFound {
            throw .projectNotFound(path: given)
        }
        let leaf = name(real)
        if leaf.hasSuffix(".xcodeproj") {
            return ProjectLocation(root: parent(real), projectFile: real)
        }
        let folder: String
        if leaf.hasSuffix(".xcworkspace") {
            let sibling = String(real.dropLast(".xcworkspace".count)) + ".xcodeproj"
            guard files.exists(at: sibling) else {
                throw .initRefused(
                    reason:
                        "the workspace \(leaf) has no project of the same name next to it. Pass the .xcodeproj."
                )
            }
            return ProjectLocation(root: parent(real), projectFile: sibling)
        }
        folder = real
        let names = try directories.topLevelNames(in: folder)
        if names.contains("DependiDomain")
            || (try? directories.topLevelNames(in: folder + "/Sources"))?.contains("DependiDomain")
                == true
        {
            throw .initRefused(
                reason:
                    "this folder holds the Dependi source itself. Pass the folder of your app project."
            )
        }
        let projects = names.filter { $0.hasSuffix(".xcodeproj") }.sorted()
        switch projects.count {
        case 0:
            if names.contains("Package.swift") {
                throw .initRefused(
                    reason:
                        "\(folder) is a Swift package. Dependi sets up app projects with an .xcodeproj."
                )
            }
            throw .projectNotFound(path: given)
        case 1:
            return ProjectLocation(root: folder, projectFile: folder + "/" + projects[0])
        default:
            let index = try prompts.askChoice("Which project?", options: projects)
            return ProjectLocation(root: folder, projectFile: folder + "/" + projects[index])
        }
    }
}
