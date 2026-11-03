import DependiDomain
import Foundation

/// Prompts and prints through three file handles. Tests pass pipes.
public final class StandardConsole: Prompting, OutputWriting, @unchecked Sendable {
    private static let maximumAttempts = 3

    private let input: FileHandle
    private let output: FileHandle
    private let error: FileHandle
    private let lock = NSLock()

    /// Creates a console that reads from `input` and writes to `output` and `error`.
    public init(input: FileHandle, output: FileHandle, error: FileHandle) {
        self.input = input
        self.output = output
        self.error = error
    }

    /// Asks the user to pick one option and returns its zero-based index. It fails at the end of the input.
    public func askChoice(_ question: String, options: [String]) throws(DomainError) -> Int {
        guard !options.isEmpty else { throw DomainError.inputEnded }
        var text = question + "\n"
        for (index, option) in options.enumerated() {
            text += "  \(index + 1)) \(option)\n"
        }
        text += "Enter a number from 1 to \(options.count): "
        for _ in 0..<Self.maximumAttempts {
            write(text, to: output)
            guard let line = readLine() else { throw DomainError.inputEnded }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let number = Int(trimmed), number >= 1, number <= options.count {
                return number - 1
            }
        }
        throw DomainError.inputEnded
    }

    /// Asks a yes or no question. It fails at the end of the input.
    public func askConfirmation(_ question: String) throws(DomainError) -> Bool {
        let text = question + " [y/n]: "
        for _ in 0..<Self.maximumAttempts {
            write(text, to: output)
            guard let line = readLine() else { throw DomainError.inputEnded }
            switch line.trimmingCharacters(in: .whitespaces).lowercased() {
            case "y", "yes": return true
            case "n", "no": return false
            default: continue
            }
        }
        throw DomainError.inputEnded
    }

    /// Writes one line to the normal output.
    public func writeLine(_ text: String) {
        write(text + "\n", to: output)
    }

    /// Writes one line to the error output.
    public func writeErrorLine(_ text: String) {
        write(text + "\n", to: error)
    }

    private func write(_ text: String, to handle: FileHandle) {
        lock.withLock {
            try? handle.write(contentsOf: Data(text.utf8))
        }
    }

    /// Reads one line a byte at a time, so no byte is lost between calls. It returns `nil` at the end of the input.
    private func readLine() -> String? {
        lock.withLock {
            var bytes: [UInt8] = []
            while true {
                guard let data = try? input.read(upToCount: 1), let byte = data.first else {
                    return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
                }
                if byte == UInt8(ascii: "\n") {
                    if bytes.last == UInt8(ascii: "\r") { bytes.removeLast() }
                    return String(decoding: bytes, as: UTF8.self)
                }
                bytes.append(byte)
            }
        }
    }
}
