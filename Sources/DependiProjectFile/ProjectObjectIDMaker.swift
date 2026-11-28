import CryptoKit
import Foundation

/// Makes the ids of new project objects. The same input always gives the same id.
struct ProjectObjectIDMaker {
    private let existingText: String
    private let attemptLimit: Int
    private var made: Set<String> = []

    /// Creates a maker that avoids every id that already appears in the project text.
    ///
    /// A clash is not possible in practice, so the search stops after `attemptLimit` ids.
    init(existingText: String, attemptLimit: Int = 1000) {
        self.existingText = existingText
        self.attemptLimit = attemptLimit
    }

    /// Returns 24 upper case hex digits for a role of a target. A clash with the project text or
    /// with an id made earlier gives the next id. It returns `nil` when every id tried clashes.
    mutating func make(targetID: String, role: String) -> String? {
        for counter in 0..<attemptLimit {
            let id = Self.id(targetID, role, counter)
            if !existingText.contains(id), !made.contains(id) {
                made.insert(id)
                return id
            }
        }
        return nil
    }

    private static func id(_ targetID: String, _ role: String, _ counter: Int) -> String {
        let digest = SHA256.hash(
            data: Data("dependi\u{0}\(targetID)\u{0}\(role)\u{0}\(counter)".utf8))
        return digest.prefix(12).map { String(format: "%02X", $0) }.joined()
    }
}
