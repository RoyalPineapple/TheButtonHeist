import os

/// Cross-queue admission state for a connection while Network.framework
/// delivers `.ready` and `.cancelled` callbacks. The server actor owns the
/// client table, but those callbacks arrive on the NWConnection queue before
/// the actor has necessarily accepted the ready connection.
final class ConnectionAdmission: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private struct State {
        var clientId: Int?
        var isCancelled = false
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    var shouldAccept: Bool {
        state.withLock { !$0.isCancelled }
    }

    /// Records the accepted client id. Returns true if cancellation already
    /// arrived and the caller should immediately remove the just-accepted
    /// client from the actor table.
    func assign(_ clientId: Int?) -> Bool {
        state.withLock { current in
            if let clientId {
                current.clientId = clientId
            }
            return current.isCancelled
        }
    }

    /// Marks the connection cancelled/failed. Returns an already-accepted
    /// client id when cleanup must be scheduled on the server actor.
    func cancel() -> Int? {
        state.withLock { current in
            current.isCancelled = true
            return current.clientId
        }
    }
}
