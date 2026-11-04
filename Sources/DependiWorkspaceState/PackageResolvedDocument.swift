import DependiDomain
import Foundation

/// The pins of a `Package.resolved` file in version 1, 2 or 3.
struct PackageResolvedDocument {
    struct Pin {
        let identity: String
        let location: String
        /// The pinned revision. A registry pin has none.
        let revision: String?
    }

    let version: Int
    let pins: [Pin]

    private struct Probe: Decodable {
        let version: Int?
    }

    private struct State: Decodable {
        let revision: String?
    }

    private struct PinV1: Decodable {
        let package: String
        let repositoryURL: String
        let state: State
    }

    private struct PinV2: Decodable {
        let identity: String?
        let kind: String?
        let location: String
        let state: State
    }

    private struct FileV1: Decodable {
        struct Object: Decodable { let pins: [PinV1] }
        let object: Object
    }

    private struct FileV2: Decodable {
        let pins: [PinV2]
    }

    /// A registry pin has no revision. Any other pin must have one.
    private static func revision(_ state: State, kind: String?) throws -> String? {
        if let revision = state.revision { return revision }
        if kind == "registry" { return nil }
        throw DecodingError.keyNotFound(
            AnyKey("revision"), .init(codingPath: [AnyKey("state")], debugDescription: ""))
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ text: String) { stringValue = text }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func decode(_ data: Data, path: String) throws(DomainError) -> PackageResolvedDocument {
        let decoder = JSONDecoder()
        let probe: Probe?
        do { probe = try decoder.decode(Probe.self, from: data) } catch {
            throw .fileUnreadable(
                path: path, reason: "version unknown: \(DecodingDescription.text(of: error))")
        }
        guard let version = probe?.version, version >= 1 else {
            throw .fileUnreadable(path: path, reason: "version unknown: no usable version field")
        }
        do {
            if version == 1 {
                let file = try decoder.decode(FileV1.self, from: data)
                return PackageResolvedDocument(
                    version: version,
                    pins: try file.object.pins.map {
                        Pin(
                            identity: $0.package, location: $0.repositoryURL,
                            revision: try Self.revision($0.state, kind: nil))
                    })
            }
            let file = try decoder.decode(FileV2.self, from: data)
            return PackageResolvedDocument(
                version: version,
                pins: try file.pins.map {
                    Pin(
                        identity: $0.identity ?? "", location: $0.location,
                        revision: try Self.revision($0.state, kind: $0.kind))
                })
        } catch {
            throw .fileUnreadable(
                path: path,
                reason: "version \(version): \(DecodingDescription.text(of: error))")
        }
    }
}
