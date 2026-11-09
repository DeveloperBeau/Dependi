import Foundation

/// Turns a decoding failure into one short sentence that names the field.
enum DecodingDescription {
    static func text(of error: any Error) -> String {
        guard let error = error as? DecodingError else { return "the file cannot be read" }
        switch error {
        case .keyNotFound(let key, let context):
            return "the field \(path(context.codingPath + [key])) is missing"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "the field \(path(context.codingPath)) has the wrong type"
        case .dataCorrupted:
            return "the file is not valid JSON"
        @unknown default:
            return "the file cannot be decoded"
        }
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        keys.map(\.stringValue).joined(separator: ".")
    }
}
