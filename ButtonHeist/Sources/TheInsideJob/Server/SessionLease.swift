import Foundation

import TheScore

/// Explicit session lease state machine for ButtonHeist driver ownership.
struct SessionLease {
    enum Phase {
        case idle
        case active(driverId: String, connections: Set<Int>)
        case draining(driverId: String, releaseTimer: Task<Void, Never>, releaseDeadline: Date)
    }

    enum Acquisition {
        case accepted(notifyActiveChanged: Bool)
        case rejected(SessionLockDiagnostic)
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
        case .active(let driverId, _), .draining(let driverId, _, _): return driverId
        }
    }

    var activeSessionConnections: Set<Int> {
        if case .active(_, let connections) = phase { return connections }
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
            cancelTimerIfDraining()
            phase = .active(driverId: driverIdentity, connections: [clientId])
            return .accepted(notifyActiveChanged: true)

        case .active(let activeId, let connections) where driverIdentity == activeId:
            return .rejected(diagnostic(
                baseMessage: "Session is already active for this driver",
                ownerDriverId: activeId,
                activeConnections: connections.count
            ))

        case .draining(let activeId, let timer, _) where driverIdentity == activeId:
            timer.cancel()
            phase = .active(driverId: activeId, connections: [clientId])
            return .accepted(notifyActiveChanged: false)

        case .active(let driverId, let connections):
            return .rejected(diagnostic(ownerDriverId: driverId, activeConnections: connections.count))

        case .draining(let driverId, _, let releaseDeadline):
            return .rejected(diagnostic(
                ownerDriverId: driverId,
                activeConnections: 0,
                remainingTimeoutSeconds: max(0, releaseDeadline.timeIntervalSince(Date()))
            ))
        }
    }

    mutating func release() -> Bool {
        let hadSession = isSessionActive
        cancelTimerIfDraining()
        phase = .idle
        return hadSession
    }

    mutating func removeConnection(_ clientId: Int, makeReleaseTimer: () -> Task<Void, Never>) -> Bool {
        guard case .active(let driverId, var connections) = phase else { return false }
        connections.remove(clientId)
        if connections.isEmpty {
            let releaseDeadline = Date().addingTimeInterval(releaseTimeout)
            phase = .draining(driverId: driverId, releaseTimer: makeReleaseTimer(), releaseDeadline: releaseDeadline)
            return true
        }
        phase = .active(driverId: driverId, connections: connections)
        return false
    }

    mutating func resetInactivityTimer(makeReleaseTimer: () -> Task<Void, Never>) {
        guard case .draining(let driverId, let oldTimer, _) = phase else { return }
        oldTimer.cancel()
        let releaseDeadline = Date().addingTimeInterval(releaseTimeout)
        phase = .draining(driverId: driverId, releaseTimer: makeReleaseTimer(), releaseDeadline: releaseDeadline)
    }

    mutating func cancelTimerIfDraining() {
        if case .draining(_, let timer, _) = phase {
            timer.cancel()
        }
    }

    func uiApprovalUnavailableDiagnostic() -> SessionLockDiagnostic? {
        switch phase {
        case .active(let driverId, let connections):
            return diagnostic(
                baseMessage: "UI approval is unavailable while a ButtonHeist session is active",
                ownerDriverId: driverId,
                activeConnections: connections.count
            )
        case .draining(let driverId, _, let releaseDeadline):
            return diagnostic(
                baseMessage: "UI approval is unavailable while a ButtonHeist session is draining",
                ownerDriverId: driverId,
                activeConnections: 0,
                remainingTimeoutSeconds: max(0, releaseDeadline.timeIntervalSince(Date()))
            )
        case .idle:
            return nil
        }
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
