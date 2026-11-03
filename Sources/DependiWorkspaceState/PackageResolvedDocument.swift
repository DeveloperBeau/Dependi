import DependiDomain
import Foundation

/// The pins of a `Package.resolved` file in version 1, 2 or 3.
struct PackageResolvedDocument {
    struct Pin {
        let identity: String
        let location: String
        let revision: String
    }

    let version: Int
    let pins: [Pin]

    private struct Probe: Decodable {
        let version: Int?
    }

    private struct State: Decodable {
        let revision: String
    }

    private struct PinV1: Decodable {
        let package: String
        let repositoryURL: String
        let state: State
    }

    private struct PinV2: Decodable {
        let identity: String?
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
                    pins: file.object.pins.map {
                        Pin(
                            identity: $0.package, location: $0.repositoryURL,
                            revision: $0.state.revision)
                    })
            }
            let file = try decoder.decode(FileV2.self, from: data)
            return PackageResolvedDocument(
                version: version,
                pins: file.pins.map {
                    Pin(
                        identity: $0.identity ?? "", location: $0.location,
                        revision: $0.state.revision)
                })
        } catch {
            throw .fileUnreadable(
                path: path,
                reason: "version \(version): \(DecodingDescription.text(of: error))")
        }
    }
}
