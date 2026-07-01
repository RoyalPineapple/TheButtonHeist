#if canImport(UIKit)
#if DEBUG
import Foundation

/// Owns the runtime lease state for a ButtonHeist session.
struct TheMuscleSession {
    enum LogEvent: Equatable, Sendable {
        case sessionClaimed(clientId: Int)
        case clientRejoinedDuringGracePeriod(clientId: Int)
        case sessionReleased
        case releaseTimerStarted(timeout: TimeInterval)
    }

    enum Effect: Equatable, Sendable {
        case log(LogEvent)
        case cancelReleaseTimer
        case replaceReleaseTimer(timeout: TimeInterval)
    }

    enum Acquisition: Equatable, Sendable {
        case accepted([Effect])
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
                return .accepted([.log(.sessionClaimed(clientId: clientId))])
            case .rejoinedDuringGracePeriod:
                return .accepted([
                    .cancelReleaseTimer,
                    .log(.clientRejoinedDuringGracePeriod(clientId: clientId)),
                ])
            }

        case .rejected(let diagnostic):
            return .rejected(diagnostic)
        }
    }

    mutating func release() -> [Effect] {
        switch lease.release() {
        case .releasedSession:
            return [.cancelReleaseTimer, .log(.sessionReleased)]
        case .noActiveSession:
            return [.cancelReleaseTimer]
        }
    }

    mutating func removeConnection(_ clientId: Int) -> [Effect] {
        switch lease.removeConnection(clientId) {
        case .draining:
            let releaseTimeout = lease.releaseTimeout
            return [
                .replaceReleaseTimer(timeout: releaseTimeout),
                .log(.releaseTimerStarted(timeout: releaseTimeout)),
            ]
        case .active, .unchanged:
            return []
        }
    }

    mutating func noteClientActivity(_ clientId: Int) -> [Effect] {
        guard lease.activeSessionConnections.contains(clientId) else { return [] }
        if lease.resetInactivityTimer() != nil {
            return [.replaceReleaseTimer(timeout: lease.releaseTimeout)]
        }
        return []
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
