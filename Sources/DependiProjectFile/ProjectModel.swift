import DependiDomain
import Foundation

/// One parsed `project.pbxproj`: its objects, its project object and where it lives.
struct ProjectModel {
    typealias Object = [String: Any]

    /// The resolved path of the `project.pbxproj` file.
    let path: String
    /// The folder that holds the `.xcodeproj` folder.
    let folder: String
    let objects: [String: Object]
    let projectID: String
    let project: Object
    /// Maps the id of a product file reference to the id of the native target that builds it.
    let targetIDByProduct: [String: String]

    /// Parses the bytes of a project file. Any malformed structure becomes `fileUnreadable`.
    static func parse(_ data: Data, path: String, folder: String) throws(DomainError)
        -> ProjectModel
    {
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw .fileUnreadable(path: path, reason: "it is not a readable project file")
        }
        guard let top = root as? [String: Any] else {
            throw .fileUnreadable(path: path, reason: "the top level is not a dictionary")
        }
        guard let rawObjects = top["objects"] as? [String: Any] else {
            throw .fileUnreadable(path: path, reason: "the objects table is missing")
        }
        var objects: [String: Object] = [:]
        for (id, value) in rawObjects {
            guard let object = value as? Object else {
                throw .fileUnreadable(path: path, reason: "object \(id) is not a dictionary")
            }
            objects[id] = object
        }
        guard let projectID = top["rootObject"] as? String else {
            throw .fileUnreadable(path: path, reason: "the root object id is missing")
        }
        guard let project = objects[projectID], project["isa"] as? String == "PBXProject" else {
            throw .fileUnreadable(path: path, reason: "the root object is not a project")
        }
        var byProduct: [String: String] = [:]
        for (id, object) in objects where object["isa"] as? String == "PBXNativeTarget" {
            if let product = object["productReference"] as? String { byProduct[product] = id }
        }
        return ProjectModel(
            path: path, folder: folder, objects: objects, projectID: projectID, project: project,
            targetIDByProduct: byProduct)
    }

    /// Returns the object with the given id when its `isa` matches.
    func object(_ id: String, isa: String) -> Object? {
        guard let object = objects[id], object["isa"] as? String == isa else { return nil }
        return object
    }

    /// Returns a list of text values. A missing key gives an empty list. A wrong type fails.
    func strings(_ object: Object, _ key: String) throws(DomainError) -> [String] {
        guard let value = object[key] else { return [] }
        guard let list = value as? [Any] else {
            throw .fileUnreadable(path: path, reason: "\(key) is not a list")
        }
        var result: [String] = []
        for item in list {
            guard let text = item as? String else {
                throw .fileUnreadable(path: path, reason: "\(key) holds a value that is not text")
            }
            result.append(text)
        }
        return result
    }

    /// The ids and names of the native targets of the project, in file order.
    func nativeTargets() throws(DomainError) -> [(id: String, name: String)] {
        var result: [(id: String, name: String)] = []
        for id in try strings(project, "targets") {
            guard let target = object(id, isa: "PBXNativeTarget"),
                let name = target["name"] as? String
            else { continue }
            result.append((id, name))
        }
        return result
    }

    /// The build settings of every configuration of a project or target object.
    func buildSettings(of owner: Object) throws(DomainError) -> [[String: Any]] {
        guard let listID = owner["buildConfigurationList"] as? String,
            let list = object(listID, isa: "XCConfigurationList")
        else { return [] }
        var result: [[String: Any]] = []
        for id in try strings(list, "buildConfigurations") {
            if let configuration = object(id, isa: "XCBuildConfiguration"),
                let settings = configuration["buildSettings"] as? [String: Any]
            {
                result.append(settings)
            }
        }
        return result
    }
}
