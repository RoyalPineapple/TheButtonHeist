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
        case accepted(AcquisitionEffect)
        case rejected(SessionLockDiagnostic)
    }

    enum AcquisitionEffect: Equatable, Sendable {
        case claimedSession
        case rejoinedDuringGracePeriod
    }

    enum ConnectionRemoval {
        case unchanged
        case active
        case draining(releaseDeadline: Date)
    }

    enum ReleaseEffect: Equatable, Sendable {
        case releasedSession
        case noActiveSession
    }

    enum OwnerDriverIdentity: Equatable, Sendable {
        case exposed(String)
        case hidden
    }

    enum SessionLockDiagnostic: Equatable, Sendable {
        case sameDriverActive(owner: OwnerDriverIdentity)
        case activeOwner(owner: OwnerDriverIdentity)
        case drainingOwner(owner: OwnerDriverIdentity, remainingTimeoutSeconds: TimeInterval)

        func payload() -> SessionLockedPayload {
            SessionLockedPayload(message: message, activeConnections: activeConnections)
        }

        private var baseMessage: String {
            switch self {
            case .sameDriverActive:
                return "Session is already active for this driver"
            case .activeOwner, .drainingOwner:
                return "Session is locked by another driver"
            }
        }

        private var owner: OwnerDriverIdentity {
            switch self {
            case .sameDriverActive(let owner), .activeOwner(let owner), .drainingOwner(let owner, _):
                return owner
            }
        }

        private var activeConnections: Int {
            switch self {
            case .sameDriverActive, .activeOwner:
                return 1
            case .drainingOwner:
                return 0
            }
        }

        private var message: String {
            var details = [baseMessage]
            if case .exposed(let ownerDriverId) = owner {
                details.append("owner driver id: \(ownerDriverId)")
            }
            details.append("active connections: \(activeConnections)")

            if case .drainingOwner(_, let remainingTimeoutSeconds) = self {
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
            return .accepted(.claimedSession)

        case .active(let activeId, _) where driverIdentity == activeId:
            return .rejected(.sameDriverActive(owner: ownerIdentity(from: activeId)))

        case .draining(let activeId, _) where driverIdentity == activeId:
            phase = .active(driverId: activeId, clientId: clientId)
            return .accepted(.rejoinedDuringGracePeriod)

        case .active(let driverId, _):
            return .rejected(.activeOwner(owner: ownerIdentity(from: driverId)))

        case .draining(let driverId, let releaseDeadline):
            return .rejected(.drainingOwner(
                owner: ownerIdentity(from: driverId),
                remainingTimeoutSeconds: max(0, releaseDeadline.timeIntervalSince(Date()))
            ))
        }
    }

    mutating func release() -> ReleaseEffect {
        let hadSession = isSessionActive
        phase = .idle
        return hadSession ? .releasedSession : .noActiveSession
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

    private func exposedDriverId(from driverIdentity: String) -> String? {
        guard case .exposed(let driverId) = ownerIdentity(from: driverIdentity) else { return nil }
        return driverId
    }

    private func ownerIdentity(from driverIdentity: String) -> OwnerDriverIdentity {
        let prefix = "driver:"
        guard driverIdentity.hasPrefix(prefix) else { return .hidden }
        let exposedDriverId = String(driverIdentity.dropFirst(prefix.count))
        guard !exposedDriverId.isEmpty else { return .hidden }
        return .exposed(exposedDriverId)
    }
}
