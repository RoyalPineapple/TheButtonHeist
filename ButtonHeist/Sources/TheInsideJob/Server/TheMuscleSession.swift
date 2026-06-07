#if canImport(UIKit)
#if DEBUG
import Foundation
import os

private let sessionLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

/// Owns the runtime lease state for a ButtonHeist session.
struct TheMuscleSession {
    enum ReleaseTimerAction {
        case none
        case cancel
        case replace(timeout: TimeInterval)
    }

    enum Acquisition {
        case accepted(notifyActiveChanged: Bool, releaseTimerAction: ReleaseTimerAction)
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
        case .accepted(let notifyActiveChanged, let shouldCancelReleaseTimer):
            if notifyActiveChanged {
                sessionLogger.info("Session claimed by client \(clientId)")
            } else {
                sessionLogger.info("Client \(clientId) rejoined session during grace period")
            }
            return .accepted(
                notifyActiveChanged: notifyActiveChanged,
                releaseTimerAction: shouldCancelReleaseTimer ? .cancel : .none
            )

        case .rejected(let diagnostic):
            return .rejected(diagnostic)
        }
    }

    mutating func release() -> ReleaseTimerAction {
        let hadSession = lease.release()
        if hadSession {
            sessionLogger.info("Session released")
        }
        return .cancel
    }

    mutating func removeConnection(_ clientId: Int) -> ReleaseTimerAction {
        switch lease.removeConnection(clientId) {
        case .draining:
            let releaseTimeout = lease.releaseTimeout
            sessionLogger.info("All session connections gone, starting \(releaseTimeout)s release timer")
            return .replace(timeout: releaseTimeout)
        case .active, .unchanged:
            return .none
        }
    }

    mutating func noteClientActivity(_ clientId: Int) -> ReleaseTimerAction {
        guard lease.activeSessionConnections.contains(clientId) else { return .none }
        if lease.resetInactivityTimer() != nil {
            return .replace(timeout: lease.releaseTimeout)
        }
        return .none
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
