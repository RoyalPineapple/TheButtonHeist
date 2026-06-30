#if canImport(UIKit)
#if DEBUG
import Foundation

/// Owns the runtime lease state for a ButtonHeist session.
struct TheMuscleSession {
    enum ReleaseTimerAction: Equatable, Sendable {
        case none
        case cancel
        case replace(timeout: TimeInterval)
    }

    enum LogEvent: Equatable, Sendable {
        case sessionClaimed(clientId: Int)
        case clientRejoinedDuringGracePeriod(clientId: Int)
        case sessionReleased
        case releaseTimerStarted(timeout: TimeInterval)
    }

    struct Effect: Equatable, Sendable {
        var releaseTimerAction: ReleaseTimerAction = .none
        var logEvents: [LogEvent] = []

        static let none = Effect()
    }

    enum Acquisition: Equatable, Sendable {
        case accepted(Effect)
        case rejected(SessionLease.SessionLockDiagnostic)
    }

    private var lease: SessionLease

    init(releaseTimeout: TimeInterval) {
        self.lease = SessionLease(releaseTimeout: releaseTimeout)
    }

    var activeSessionDriverId: String? {
        lease.activeSessionDriverId
    }

    var exposedDriverId: String? {
        lease.exposedActiveDriverId
    }

    var activeSessionConnections: Set<Int> {
        lease.activeSessionConnections
    }

    var isSessionActive: Bool {
        lease.isSessionActive
    }

    var activeSessionConnectionCount: Int {
        lease.activeSessionConnectionCount
    }

    mutating func acquire(driverIdentity: String, clientId: Int) -> Acquisition {
        switch lease.acquire(driverIdentity: driverIdentity, clientId: clientId) {
        case .accepted(let effect):
            switch effect {
            case .claimedSession:
                return .accepted(Effect(logEvents: [.sessionClaimed(clientId: clientId)]))
            case .rejoinedDuringGracePeriod:
                return .accepted(Effect(
                    releaseTimerAction: .cancel,
                    logEvents: [.clientRejoinedDuringGracePeriod(clientId: clientId)]
                ))
            }

        case .rejected(let diagnostic):
            return .rejected(diagnostic)
        }
    }

    mutating func release() -> Effect {
        switch lease.release() {
        case .releasedSession:
            return Effect(releaseTimerAction: .cancel, logEvents: [.sessionReleased])
        case .noActiveSession:
            return Effect(releaseTimerAction: .cancel)
        }
    }

    mutating func removeConnection(_ clientId: Int) -> Effect {
        switch lease.removeConnection(clientId) {
        case .draining:
            let releaseTimeout = lease.releaseTimeout
            return Effect(
                releaseTimerAction: .replace(timeout: releaseTimeout),
                logEvents: [.releaseTimerStarted(timeout: releaseTimeout)]
            )
        case .active, .unchanged:
            return .none
        }
    }

    mutating func noteClientActivity(_ clientId: Int) -> Effect {
        guard lease.activeSessionConnections.contains(clientId) else { return .none }
        if lease.resetInactivityTimer() != nil {
            return Effect(releaseTimerAction: .replace(timeout: lease.releaseTimeout))
        }
        return .none
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
