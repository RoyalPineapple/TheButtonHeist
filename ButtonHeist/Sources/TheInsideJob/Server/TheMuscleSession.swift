#if canImport(UIKit)
#if DEBUG
import Foundation
import os

private let sessionLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

/// Owns the runtime lease plus the release timer for a ButtonHeist session.
struct TheMuscleSession {
    enum Acquisition {
        case accepted(notifyActiveChanged: Bool)
        case rejected(SessionLease.SessionLockDiagnostic)
    }

    private var lease: SessionLease
    private var releaseTimer: Task<Void, Never>?

    init(releaseTimeout: TimeInterval) {
        self.lease = SessionLease(releaseTimeout: releaseTimeout)
    }

    var activeSessionDriverId: String? {
        lease.activeSessionDriverId
    }

    var exposedActiveSessionDriverId: String? {
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

    func uiApprovalUnavailableDiagnostic() -> SessionLease.SessionLockDiagnostic? {
        lease.uiApprovalUnavailableDiagnostic()
    }

    mutating func acquire(driverIdentity: String, clientId: Int) -> Acquisition {
        switch lease.acquire(driverIdentity: driverIdentity, clientId: clientId) {
        case .accepted(let notifyActiveChanged, let shouldCancelReleaseTimer):
            if shouldCancelReleaseTimer {
                self.cancelReleaseTimer()
            }
            if notifyActiveChanged {
                sessionLogger.info("Session claimed by client \(clientId)")
            } else {
                sessionLogger.info("Client \(clientId) rejoined session during grace period")
            }
            return .accepted(notifyActiveChanged: notifyActiveChanged)

        case .rejected(let diagnostic):
            return .rejected(diagnostic)
        }
    }

    mutating func release() -> Bool {
        cancelReleaseTimer()
        let hadSession = lease.release()
        if hadSession {
            sessionLogger.info("Session released")
        }
        return hadSession
    }

    mutating func removeConnection(_ clientId: Int, owner: TheMuscle) {
        switch lease.removeConnection(clientId) {
        case .draining:
            let releaseTimeout = lease.releaseTimeout
            replaceReleaseTimer(owner: owner)
            sessionLogger.info("All session connections gone, starting \(releaseTimeout)s release timer")
        case .active, .unchanged:
            break
        }
    }

    mutating func noteClientActivity(_ clientId: Int, owner: TheMuscle) {
        guard lease.activeSessionConnections.contains(clientId) else { return }
        if lease.resetInactivityTimer() != nil {
            replaceReleaseTimer(owner: owner)
        }
    }

    mutating func cancelReleaseTimer() {
        releaseTimer?.cancel()
        releaseTimer = nil
    }

    private mutating func replaceReleaseTimer(owner: TheMuscle) {
        cancelReleaseTimer()
        let releaseTimeout = lease.releaseTimeout
        releaseTimer = Task { [weak owner, releaseTimeout] in
            guard await Task.cancellableSleep(for: .seconds(releaseTimeout)) else { return }
            guard !Task.isCancelled else { return }
            await owner?.sessionReleaseTimerFired()
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
