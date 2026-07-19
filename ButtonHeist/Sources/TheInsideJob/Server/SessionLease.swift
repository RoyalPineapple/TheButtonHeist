import Foundation

import ButtonHeistSupport
import TheScore

/// Explicit session lease state machine for ButtonHeist driver ownership.
struct SessionLease {
    enum Phase: Equatable, Sendable {
        case idle
        case active(owner: SessionOwner, clientId: Int)
        case draining(owner: SessionOwner, releaseDeadline: Date)
    }

    private enum Event: Equatable, Sendable {
        case acquisitionRequested(owner: SessionOwner, clientId: Int, at: Date)
        case releaseRequested
        case connectionRemoved(clientId: Int, at: Date)
    }

    private enum Rejection: Equatable, Sendable {
        case acquisition(SessionLockDiagnostic)
    }

    enum Acquisition: Equatable, Sendable {
        case accepted([Effect])
        case rejected(SessionLockDiagnostic)
    }

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

    enum OwnerDriverIdentity: Equatable, Sendable {
        case exposed(DriverID)
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

    private var store: StateStore<Reducer>
    init(releaseTimeout: TimeInterval) {
        self.store = StateStore(
            initial: .idle,
            reducer: Reducer(releaseTimeout: releaseTimeout)
        )
    }

    var phase: Phase {
        store.state
    }

    var activeSessionOwner: SessionOwner? {
        switch phase {
        case .idle: return nil
        case .active(let owner, _), .draining(let owner, _): return owner
        }
    }

    var exposedDriverId: DriverID? {
        guard let activeSessionOwner,
              case .driver(let driverId) = activeSessionOwner else { return nil }
        return driverId
    }

    var activeSessionConnections: Set<Int> {
        if case .active(_, let clientId) = phase { return [clientId] }
        return []
    }

    var isSessionActive: Bool {
        activeSessionOwner != nil
    }

    var activeSessionConnectionCount: Int {
        activeSessionConnections.count
    }

    mutating func acquire(owner: SessionOwner, clientId: Int, at now: Date) -> Acquisition {
        let transition = store.reduce(.acquisitionRequested(owner: owner, clientId: clientId, at: now))
        switch transition {
        case .changed:
            return .accepted(transition.effects)
        case .rejected(.acquisition(let diagnostic), _):
            return .rejected(diagnostic)
        }
    }

    mutating func release() -> [Effect] {
        let transition = store.reduce(.releaseRequested)
        switch transition {
        case .changed:
            return transition.effects
        case .rejected(let rejection, _):
            preconditionFailure("SessionLease release emitted unexpected rejection: \(rejection)")
        }
    }

    mutating func removeConnection(_ clientId: Int, at now: Date) -> [Effect] {
        let transition = store.reduce(.connectionRemoved(clientId: clientId, at: now))
        switch transition {
        case .changed:
            return transition.effects
        case .rejected(let rejection, _):
            preconditionFailure("SessionLease removeConnection emitted unexpected rejection: \(rejection)")
        }
    }

    private static func driverIdentity(from owner: SessionOwner) -> OwnerDriverIdentity {
        guard case .driver(let driverId) = owner else { return .hidden }
        return .exposed(driverId)
    }

    private struct Reducer: StateReducer {
        let releaseTimeout: TimeInterval

        func reduce(_ state: Phase, event: Event) -> StateTransition<Phase, Effect, Rejection> {
            switch (state, event) {
            case (.idle, .acquisitionRequested(let owner, let clientId, _)):
                return .changed(
                    to: .active(owner: owner, clientId: clientId),
                    effects: [.log(.sessionClaimed(clientId: clientId))]
                )

            case (.active(let activeOwner, _), .acquisitionRequested(let owner, _, _))
                where owner == activeOwner:
                return .rejected(
                    .acquisition(.sameDriverActive(owner: driverIdentity(from: activeOwner))),
                    stayingIn: state
                )

            case (.draining(let activeOwner, _), .acquisitionRequested(let owner, let clientId, _))
                where owner == activeOwner:
                return .changed(
                    to: .active(owner: activeOwner, clientId: clientId),
                    effects: [
                        .cancelReleaseTimer,
                        .log(.clientRejoinedDuringGracePeriod(clientId: clientId)),
                    ]
                )

            case (.active(let owner, _), .acquisitionRequested):
                return .rejected(
                    .acquisition(.activeOwner(owner: driverIdentity(from: owner))),
                    stayingIn: state
                )

            case (
                .draining(let owner, let releaseDeadline),
                .acquisitionRequested(_, _, let now)
            ):
                return .rejected(
                    .acquisition(.drainingOwner(
                        owner: driverIdentity(from: owner),
                        remainingTimeoutSeconds: max(0, releaseDeadline.timeIntervalSince(now))
                    )),
                    stayingIn: state
                )

            case (.idle, .releaseRequested):
                return .changed(to: .idle, effects: [.cancelReleaseTimer])

            case (.active, .releaseRequested), (.draining, .releaseRequested):
                return .changed(
                    to: .idle,
                    effects: [.cancelReleaseTimer, .log(.sessionReleased)]
                )

            case (.idle, .connectionRemoved), (.draining, .connectionRemoved):
                return .changed(to: state)

            case (
                .active(let owner, let activeClientId),
                .connectionRemoved(let clientId, let now)
            )
                where activeClientId == clientId:
                let releaseDeadline = now.addingTimeInterval(releaseTimeout)
                return .changed(
                    to: .draining(owner: owner, releaseDeadline: releaseDeadline),
                    effects: [
                        .replaceReleaseTimer(timeout: releaseTimeout),
                        .log(.releaseTimerStarted(timeout: releaseTimeout)),
                    ]
                )

            case (.active, .connectionRemoved):
                return .changed(to: state)
            }
        }
    }
}
