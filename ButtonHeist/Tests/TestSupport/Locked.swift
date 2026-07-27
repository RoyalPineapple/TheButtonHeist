import Foundation

/// A value one closure reads while another changes it.
///
/// Swift refuses to let a `@Sendable` closure capture a mutable local, so a
/// value a test swaps out mid-run lives here instead of in a `var`. Every read
/// and every write takes the lock.
///
/// The conformance is unchecked because a class with mutable state cannot
/// satisfy checked `Sendable`; `Synchronization.Mutex` can, and needs iOS 18,
/// which is past this package's floor. Holding the exception in one reviewed
/// type is the point — callers get a `Sendable` value and write no exception
/// of their own.
public final class Locked<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public var current: Value {
        lock.withLock { value }
    }

    public func set(_ value: Value) {
        lock.withLock { self.value = value }
    }

    /// Reads and writes under one acquisition, for a change that depends on
    /// what is already there.
    @discardableResult
    public func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }
}
