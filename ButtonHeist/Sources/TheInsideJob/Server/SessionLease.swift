import Foundation

import ButtonHeistSupport
import TheScore

/// Explicit session lease state machine for ButtonHeist driver ownership.
struct SessionLease {
    enum Phase: Equatable, Sendable {
        case idle
        case active(driverId: String, clientId: Int)
        case draining(driverId: String, releaseDeadline: Date)
    }

    private enum Event: Equatable, Sendable {
        case acquire(driverIdentity: String, clientId: Int, at: Date)
        case release
        case removeConnection(clientId: Int, at: Date)
    }

    private enum Effect: Equatable, Sendable {
        case acquisition(AcquisitionEffect)
        case release(ReleaseEffect)
        case connectionRemoval(ConnectionRemoval)
    }

    private enum Rejection: Equatable, Sendable {
        case acquisition(SessionLockDiagnostic)
    }

    enum Acquisition: Equatable, Sendable {
        case accepted(AcquisitionEffect)
        case rejected(SessionLockDiagnostic)
    }

    enum AcquisitionEffect: Equatable, Sendable {
        case claimedSession
        case rejoinedDuringGracePeriod
    }

    enum ConnectionRemoval: Equatable, Sendable {
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

    private var driver: StateDriver<Machine>
    let releaseTimeout: TimeInterval

    init(releaseTimeout: TimeInterval) {
        self.releaseTimeout = releaseTimeout
        self.driver = StateDriver(
            initial: .idle,
            machine: Machine(releaseTimeout: releaseTimeout)
        )
    }

    var phase: Phase {
        driver.state
    }

    var activeSessionDriverId: String? {
        switch phase {
        case .idle: return nil
        case .active(let driverId, _), .draining(let driverId, _): return driverId
        }
    }

    var exposedActiveDriverId: String? {
        activeSessionDriverId.flatMap { Self.exposedDriverId(from: $0) }
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

    mutating func acquire(driverIdentity: String, clientId: Int, at now: Date) -> Acquisition {
        let change = driver.send(.acquire(driverIdentity: driverIdentity, clientId: clientId, at: now))
        switch change {
        case .changed:
            guard case .acquisition(let effect)? = change.singleEffect else {
                preconditionFailure("SessionLease acquire emitted unexpected effect")
            }
            return .accepted(effect)
        case .rejected(.acquisition(let diagnostic), _):
            return .rejected(diagnostic)
        }
    }

    mutating func release() -> ReleaseEffect {
        let change = driver.send(.release)
        switch change {
        case .changed:
            guard case .release(let effect)? = change.singleEffect else {
                preconditionFailure("SessionLease release emitted unexpected effect")
            }
            return effect
        case .rejected(let rejection, _):
            preconditionFailure("SessionLease release emitted unexpected rejection: \(rejection)")
        }
    }

    mutating func removeConnection(_ clientId: Int, at now: Date) -> ConnectionRemoval {
        let change = driver.send(.removeConnection(clientId: clientId, at: now))
        switch change {
        case .changed:
            guard case .connectionRemoval(let removal)? = change.singleEffect else {
                preconditionFailure("SessionLease removeConnection emitted unexpected effect")
            }
            return removal
        case .rejected(let rejection, _):
            preconditionFailure("SessionLease removeConnection emitted unexpected rejection: \(rejection)")
        }
    }

    private static func exposedDriverId(from driverIdentity: String) -> String? {
        guard case .exposed(let driverId) = ownerIdentity(from: driverIdentity) else { return nil }
        return driverId
    }

    private static func ownerIdentity(from driverIdentity: String) -> OwnerDriverIdentity {
        let prefix = "driver:"
        guard driverIdentity.hasPrefix(prefix) else { return .hidden }
        let exposedDriverId = String(driverIdentity.dropFirst(prefix.count))
        guard !exposedDriverId.isEmpty else { return .hidden }
        return .exposed(exposedDriverId)
    }

    private struct Machine: SimpleStateMachine {
        let releaseTimeout: TimeInterval

        func advance(_ state: Phase, with event: Event) -> StateChange<Phase, Effect, Rejection> {
            switch (state, event) {
            case (.idle, .acquire(let driverIdentity, let clientId, _)):
                return .changed(
                    to: .active(driverId: driverIdentity, clientId: clientId),
                    effects: [.acquisition(.claimedSession)]
                )

            case (.active(let activeId, _), .acquire(let driverIdentity, _, _)) where driverIdentity == activeId:
                return .rejected(
                    .acquisition(.sameDriverActive(owner: ownerIdentity(from: activeId))),
                    stayingIn: state
                )

            case (.draining(let activeId, _), .acquire(let driverIdentity, let clientId, _))
                where driverIdentity == activeId:
                return .changed(
                    to: .active(driverId: activeId, clientId: clientId),
                    effects: [.acquisition(.rejoinedDuringGracePeriod)]
                )

            case (.active(let driverId, _), .acquire):
                return .rejected(
                    .acquisition(.activeOwner(owner: ownerIdentity(from: driverId))),
                    stayingIn: state
                )

            case (.draining(let driverId, let releaseDeadline), .acquire(_, _, let now)):
                return .rejected(
                    .acquisition(.drainingOwner(
                        owner: ownerIdentity(from: driverId),
                        remainingTimeoutSeconds: max(0, releaseDeadline.timeIntervalSince(now))
                    )),
                    stayingIn: state
                )

            case (.idle, .release):
                return .changed(to: .idle, effects: [.release(.noActiveSession)])

            case (.active, .release), (.draining, .release):
                return .changed(to: .idle, effects: [.release(.releasedSession)])

            case (.idle, .removeConnection), (.draining, .removeConnection):
                return .changed(to: state, effects: [.connectionRemoval(.unchanged)])

            case (.active(let driverId, let activeClientId), .removeConnection(let clientId, let now))
                where activeClientId == clientId:
                let releaseDeadline = now.addingTimeInterval(releaseTimeout)
                return .changed(
                    to: .draining(driverId: driverId, releaseDeadline: releaseDeadline),
                    effects: [.connectionRemoval(.draining(releaseDeadline: releaseDeadline))]
                )

            case (.active, .removeConnection):
                return .changed(to: state, effects: [.connectionRemoval(.active)])
            }
        }
    }
}
