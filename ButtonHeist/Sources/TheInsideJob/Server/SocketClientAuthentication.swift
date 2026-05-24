/// Per-client authentication lifecycle. Deadline task ownership lives inside
/// awaiting phases so impossible states cannot keep a stale deadline after auth.
enum SocketClientAuthentication: Equatable, Sendable {
    case awaitingAuthentication(deadline: Task<Void, Never>)
    case awaitingApproval(deadline: Task<Void, Never>)
    case authenticated

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    /// Deadline task identity is deliberately ignored; equality describes the authentication phase.
    static func == (lhs: SocketClientAuthentication, rhs: SocketClientAuthentication) -> Bool {
        switch (lhs, rhs) {
        case (.awaitingAuthentication, .awaitingAuthentication),
             (.awaitingApproval, .awaitingApproval),
             (.authenticated, .authenticated):
            return true
        default:
            return false
        }
    }

    /// Move to authenticated when still awaiting auth or approval.
    /// Returns false when the client is already authenticated.
    @discardableResult
    mutating func markAuthenticated() -> Bool {
        guard !isAuthenticated else { return false }
        cancelDeadline()
        self = .authenticated
        return true
    }

    /// Move to approval-pending while unauthenticated.
    /// Returns false once authentication has already completed.
    @discardableResult
    mutating func markApprovalPending() -> Bool {
        switch self {
        case .awaitingAuthentication(let deadline):
            self = .awaitingApproval(deadline: deadline)
            return true
        case .awaitingApproval:
            return true
        case .authenticated:
            return false
        }
    }

    /// Cancels the deadline task owned by an awaiting state.
    func cancelDeadline() {
        switch self {
        case .awaitingAuthentication(let deadline), .awaitingApproval(let deadline):
            deadline.cancel()
        case .authenticated:
            return
        }
    }
}
