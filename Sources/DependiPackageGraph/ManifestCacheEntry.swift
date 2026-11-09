import Foundation

/// One cached `dump-package` output with the key it was made for.
struct ManifestCacheEntry: Codable {
    let key: String
    let dump: String
}
