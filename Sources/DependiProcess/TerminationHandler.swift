import Darwin
import Dispatch

/// Calls a handler when the process receives one of the given signals.
///
/// The default action of each signal is turned off while the handler is active, so the handler
/// decides what happens. Dependi uses it to kill its children and then exit.
public final class TerminationHandler: @unchecked Sendable {
    private let signals: [Int32]
    private let handler: @Sendable (Int32) -> Void
    private var sources: [any DispatchSourceSignal] = []

    /// Creates a handler. Nothing is installed until `start`.
    public init(signals: [Int32], handler: @escaping @Sendable (Int32) -> Void) {
        self.signals = signals
        self.handler = handler
    }

    /// Starts to watch the signals.
    public func start() {
        for number in signals {
            Darwin.signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            let handler = self.handler
            source.setEventHandler { handler(number) }
            source.resume()
            sources.append(source)
        }
    }

    /// Stops watching and gives each signal its default action back.
    public func stop() {
        for source in sources { source.cancel() }
        sources.removeAll()
        for number in signals { Darwin.signal(number, SIG_DFL) }
    }
}
