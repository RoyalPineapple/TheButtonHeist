import Foundation

import TheScore

/// Explicit session lease state machine for ButtonHeist driver ownership.
struct SessionLease {
    enum Phase {
        case idle
        case active(driverId: String, clientId: Int)
        case draining(driverId: String, releaseDeadline: Date)
    }

    enum Acquisition {
        case accepted(notifyActiveChanged: Bool, cancelReleaseTimer: Bool)
        case rejected(SessionLockDiagnostic)
    }

    enum ConnectionRemoval {
        case unchanged
        case active
        case draining(releaseDeadline: Date)
    }

    struct SessionLockDiagnostic: Equatable, Sendable {
        var baseMessage: String
        var ownerDriverId: String?
        var activeConnections: Int
        var remainingTimeoutSeconds: TimeInterval?

        func payload() -> SessionLockedPayload {
            SessionLockedPayload(message: message, activeConnections: activeConnections)
        }

        private var message: String {
            var details = [baseMessage]
            if let ownerDriverId, !ownerDriverId.isEmpty {
                details.append("owner driver id: \(ownerDriverId)")
            }
            details.append("active connections: \(activeConnections)")
            if let remainingTimeoutSeconds {
                details.append("remaining timeout: \(Int(max(remainingTimeoutSeconds, 0).rounded(.up)))s")
            }
            return details.joined(separator: "; ") + "."
        }
    }

    private(set) var phase: Phase = .idle
    let releaseTimeout: TimeInterval

    init(releaseTimeout: TimeInterval) {
        self.releaseTimeout = releaseTimeout
    }

    var activeSessionDriverId: String? {
        switch phase {
        case .idle: return nil
        case .active(let driverId, _), .draining(let driverId, _): return driverId
        }
    }

    var exposedActiveDriverId: String? {
        activeSessionDriverId.flatMap(exposedDriverId(from:))
    }

    var activeSessionConnections: Set<Int> {
        if case .active(_, let clientId) = phase { return [clientId] }
        return []
    }

    var isSessionActive: Bool {
        activeSessionDriverId != nil
    }

    var activeSessionConnectionCount: Int {
        activeSessionConnections.count
    }

    mutating func acquire(driverIdentity: String, clientId: Int) -> Acquisition {
        switch phase {
        case .idle:
            phase = .active(driverId: driverIdentity, clientId: clientId)
            return .accepted(notifyActiveChanged: true, cancelReleaseTimer: false)

        case .active(let activeId, _) where driverIdentity == activeId:
            return .rejected(diagnostic(
                baseMessage: "Session is already active for this driver",
                ownerDriverId: activeId,
                activeConnections: 1
            ))

        case .draining(let activeId, _) where driverIdentity == activeId:
            phase = .active(driverId: activeId, clientId: clientId)
            return .accepted(notifyActiveChanged: false, cancelReleaseTimer: true)

        case .active(let driverId, _):
            return .rejected(diagnostic(ownerDriverId: driverId, activeConnections: 1))

        case .draining(let driverId, let releaseDeadline):
            return .rejected(diagnostic(
                ownerDriverId: driverId,
                activeConnections: 0,
                remainingTimeoutSeconds: max(0, releaseDeadline.timeIntervalSince(Date()))
            ))
        }
    }

    mutating func release() -> Bool {
        let hadSession = isSessionActive
        phase = .idle
        return hadSession
    }

    mutating func removeConnection(_ clientId: Int) -> ConnectionRemoval {
        guard case .active(let driverId, let activeClientId) = phase else {
            return .unchanged
        }
        guard activeClientId == clientId else {
            return .active
        }
        let releaseDeadline = Date().addingTimeInterval(releaseTimeout)
        phase = .draining(driverId: driverId, releaseDeadline: releaseDeadline)
        return .draining(releaseDeadline: releaseDeadline)
    }

    mutating func resetInactivityTimer() -> Date? {
        guard case .draining(let driverId, _) = phase else { return nil }
        let releaseDeadline = Date().addingTimeInterval(releaseTimeout)
        phase = .draining(driverId: driverId, releaseDeadline: releaseDeadline)
        return releaseDeadline
    }

    private func diagnostic(
        baseMessage: String = "Session is locked by another driver",
        ownerDriverId: String,
        activeConnections: Int,
        remainingTimeoutSeconds: TimeInterval? = nil
    ) -> SessionLockDiagnostic {
        SessionLockDiagnostic(
            baseMessage: baseMessage,
            ownerDriverId: exposedDriverId(from: ownerDriverId),
            activeConnections: activeConnections,
            remainingTimeoutSeconds: remainingTimeoutSeconds
        )
    }

    private func exposedDriverId(from driverIdentity: String) -> String? {
        let prefix = "driver:"
        guard driverIdentity.hasPrefix(prefix) else { return nil }
        return String(driverIdentity.dropFirst(prefix.count))
    }
}
