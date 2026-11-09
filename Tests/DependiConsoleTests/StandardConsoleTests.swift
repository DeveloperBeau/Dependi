import DependiDomain
import Foundation
import Testing

@testable import DependiConsole

/// A console wired to pipes, with the input already written and closed.
private struct Rig {
    let console: StandardConsole
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()

    init(input: String) {
        let inputPipe = Pipe()
        inputPipe.fileHandleForWriting.write(Data(input.utf8))
        try? inputPipe.fileHandleForWriting.close()
        console = StandardConsole(
            input: inputPipe.fileHandleForReading,
            output: outputPipe.fileHandleForWriting,
            error: errorPipe.fileHandleForWriting
        )
    }

    /// Everything written so far to the output handle.
    func printed() -> String { drain(outputPipe) }
    /// Everything written so far to the error handle.
    func printedErrors() -> String { drain(errorPipe) }

    private func drain(_ pipe: Pipe) -> String {
        try? pipe.fileHandleForWriting.close()
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

struct StandardConsoleTests {
    private let options = ["alpha", "beta", "gamma"]

    @Test func aValidNumberReturnsAZeroBasedIndex() throws {
        let rig = Rig(input: "2\n")
        #expect(try rig.console.askChoice("Pick", options: options) == 1)
        let text = rig.printed()
        #expect(text.contains("Pick"))
        #expect(text.contains("1) alpha"))
        #expect(text.contains("3) gamma"))
    }

    @Test func theFirstAndLastNumbersAreAccepted() throws {
        let rig = Rig(input: "1\n3\n")
        #expect(try rig.console.askChoice("Pick", options: options) == 0)
        #expect(try rig.console.askChoice("Pick", options: options) == 2)
    }

    @Test func aWindowsLineEndingIsAccepted() throws {
        let rig = Rig(input: "3\r\n")
        #expect(try rig.console.askChoice("Pick", options: options) == 2)
    }

    @Test func anInvalidLineIsAskedAgainAndThenAccepted() throws {
        let rig = Rig(input: "0\n4\n2\n")
        #expect(try rig.console.askChoice("Pick", options: options) == 1)
    }

    @Test func twoInvalidLinesThenAValidOneStillSucceeds() throws {
        let rig = Rig(input: "x\ny\n3\n")
        #expect(try rig.console.askChoice("Pick", options: options) == 2)
    }

    @Test func threeInvalidLinesFailEvenWhenAValidLineFollows() {
        let rig = Rig(input: "x\n9\n0\n1\n")
        #expect(throws: DomainError.inputEnded) {
            try rig.console.askChoice("Pick", options: options)
        }
    }

    @Test func endOfInputFailsAChoice() {
        let rig = Rig(input: "")
        #expect(throws: DomainError.inputEnded) {
            try rig.console.askChoice("Pick", options: options)
        }
    }

    @Test func aLastLineWithoutANewlineIsStillRead() throws {
        let rig = Rig(input: "2")
        #expect(try rig.console.askChoice("Pick", options: options) == 1)
    }

    @Test func aChoiceWithNoOptionsFailsInsteadOfLooping() {
        let rig = Rig(input: "1\n")
        #expect(throws: DomainError.inputEnded) {
            try rig.console.askChoice("Pick", options: [])
        }
    }

    @Test func confirmationAcceptsEveryYesAndNoSpellingInAnyCase() throws {
        let rig = Rig(input: "y\nYES\nYes\nn\nNO\nno\n")
        for expected in [true, true, true, false, false, false] {
            #expect(try rig.console.askConfirmation("Sure?") == expected)
        }
    }

    @Test func confirmationAsksAgainAfterAnInvalidLine() throws {
        let rig = Rig(input: "maybe\nyep\nn\n")
        #expect(try rig.console.askConfirmation("Sure?") == false)
    }

    @Test func confirmationFailsAfterThreeInvalidLines() {
        let rig = Rig(input: "a\nb\nc\ny\n")
        #expect(throws: DomainError.inputEnded) {
            try rig.console.askConfirmation("Sure?")
        }
    }

    @Test func endOfInputFailsAConfirmation() {
        let rig = Rig(input: "")
        #expect(throws: DomainError.inputEnded) {
            try rig.console.askConfirmation("Sure?")
        }
    }

    @Test func noBufferedByteIsLostBetweenTwoPrompts() throws {
        let rig = Rig(input: "3\nyes\n1\nno\n")
        #expect(try rig.console.askChoice("Pick", options: options) == 2)
        #expect(try rig.console.askConfirmation("Sure?") == true)
        #expect(try rig.console.askChoice("Pick", options: options) == 0)
        #expect(try rig.console.askConfirmation("Sure?") == false)
    }

    @Test func linesGoToTheRightHandle() {
        let rig = Rig(input: "")
        rig.console.writeLine("to output")
        rig.console.writeErrorLine("to error")
        #expect(rig.printed() == "to output\n")
        #expect(rig.printedErrors() == "to error\n")
    }

    @Test func promptsWriteNothingToTheErrorHandle() throws {
        let rig = Rig(input: "1\n")
        _ = try rig.console.askChoice("Pick", options: options)
        #expect(rig.printedErrors().isEmpty)
    }
}
