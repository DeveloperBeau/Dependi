import CryptoKit
import Foundation

/// Makes the ids of new project objects. The same input always gives the same id.
struct ProjectObjectIDMaker {
    private let existingText: String
    private var made: Set<String> = []

    /// Creates a maker that avoids every id that already appears in the project text.
    init(existingText: String) {
        self.existingText = existingText
    }

    /// Returns 24 upper case hex digits for a role of a target. A clash with the project text or
    /// with an id made earlier gives the next id.
    mutating func make(targetID: String, role: String) -> String {
        var counter = 0
        while true {
            let digest = SHA256.hash(
                data: Data("dependi\u{0}\(targetID)\u{0}\(role)\u{0}\(counter)".utf8))
            let id = digest.prefix(12).map { String(format: "%02X", $0) }.joined()
            if !existingText.contains(id) && !made.contains(id) {
                made.insert(id)
                return id
            }
            counter += 1
        }
    }
}
