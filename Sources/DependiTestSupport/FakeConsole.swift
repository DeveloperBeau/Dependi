import DependiDomain

/// A console with scripted answers. It records the questions asked and the lines written.
public final class FakeConsole: Prompting, OutputWriting, @unchecked Sendable {
    /// One scripted answer.
    public enum Answer: Sendable, Equatable {
        /// The index of the chosen option.
        case choice(Int)
        /// A yes or no answer.
        case confirmation(Bool)
    }

    private struct State: Sendable {
        var answers: [Answer]
        var questions: [String] = []
        var lines: [String] = []
        var errorLines: [String] = []
    }

    private let state: LockedBox<State>

    /// Creates a console that gives the answers in order.
    public init(answers: [Answer]) {
        state = LockedBox(State(answers: answers))
    }

    /// The questions asked so far.
    public var questions: [String] { state.withValue { $0.questions } }
    /// The lines written to the normal output.
    public var lines: [String] { state.withValue { $0.lines } }
    /// The lines written to the error output.
    public var errorLines: [String] { state.withValue { $0.errorLines } }

    /// Implements `askChoice` for `FakeConsole`.
    public func askChoice(_ question: String, options: [String]) throws(DomainError) -> Int {
        let answer = state.withValue { state -> Answer? in
            state.questions.append(question)
            return state.answers.isEmpty ? nil : state.answers.removeFirst()
        }
        guard case .choice(let index)? = answer, options.indices.contains(index) else {
            throw .inputEnded
        }
        return index
    }

    /// Implements `askConfirmation` for `FakeConsole`.
    public func askConfirmation(_ question: String) throws(DomainError) -> Bool {
        let answer = state.withValue { state -> Answer? in
            state.questions.append(question)
            return state.answers.isEmpty ? nil : state.answers.removeFirst()
        }
        guard case .confirmation(let value)? = answer else { throw .inputEnded }
        return value
    }

    /// Implements `writeLine` for `FakeConsole`.
    public func writeLine(_ text: String) { state.withValue { $0.lines.append(text) } }

    /// Implements `writeErrorLine` for `FakeConsole`.
    public func writeErrorLine(_ text: String) { state.withValue { $0.errorLines.append(text) } }
}
