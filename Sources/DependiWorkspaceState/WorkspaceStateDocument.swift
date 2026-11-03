import DependiDomain
import Foundation

/// The fields of `workspace-state.json` that the reader uses. Other fields are ignored.
struct WorkspaceStateDocument: Decodable {
    struct Reference: Decodable {
        let identity: String?
        let kind: String?
        let location: String?
    }

    struct Checkout: Decodable {
        let revision: String?
        let version: String?
    }

    struct State: Decodable {
        let name: String?
        let path: String?
        let checkoutState: Checkout?
    }

    struct Dependency: Decodable {
        let packageRef: Reference
        let state: State?
        let subpath: String?
    }

    struct Object: Decodable {
        let dependencies: [Dependency]
    }

    private let object: Object
    let version: Int
    var dependencies: [Dependency] { object.dependencies }

    private struct VersionProbe: Decodable {
        let version: Int?
    }

    static func decode(_ data: Data, path: String) throws(DomainError) -> WorkspaceStateDocument {
        let decoder = JSONDecoder()
        let probe = try? decoder.decode(VersionProbe.self, from: data)
        let label = probe?.version.map(String.init) ?? "unknown"
        do {
            return try decoder.decode(WorkspaceStateDocument.self, from: data)
        } catch {
            throw .fileUnreadable(
                path: path,
                reason: "version \(label): \(DecodingDescription.text(of: error))")
        }
    }
}
