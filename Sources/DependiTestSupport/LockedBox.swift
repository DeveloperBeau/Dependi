import Foundation

/// A value guarded by a lock, so a test double can be shared between threads.
public final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    /// Creates a box that holds a first value.
    public init(_ value: Value) {
        self.value = value
    }

    /// Runs a closure with exclusive access to the value.
    @discardableResult
    public func withValue<Result, Failure: Error>(
        _ body: (inout Value) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
