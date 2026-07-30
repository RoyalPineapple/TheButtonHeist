#if canImport(UIKit)
#if DEBUG

/// Complete lifecycle and scheduling algebra for semantic observation.
struct SemanticObservationCycle {
    struct Identity: Sendable, Equatable {
        fileprivate let rawValue: UInt64
    }

    struct Request {
        let identity: Identity
        let pulse: TheTripwire.PulseReading
        let scope: SemanticObservationScope
    }

    struct Stop {
        let activeTask: Task<Void, Never>?
    }

    private enum State {
        case stopped(lastIdentity: UInt64)
        case armed(
            demandedScope: SemanticObservationScope?,
            lastIdentity: UInt64
        )
        case active(
            identity: Identity,
            scope: SemanticObservationScope,
            demandedScope: SemanticObservationScope?,
            task: Task<Void, Never>
        )
    }

    private var state = State.stopped(lastIdentity: 0)

    var isRunning: Bool {
        if case .stopped = state { false } else { true }
    }

    mutating func start() -> Bool {
        guard case .stopped(let lastIdentity) = state else { return false }
        state = .armed(demandedScope: nil, lastIdentity: lastIdentity)
        return true
    }

    mutating func demand(
        scope: SemanticObservationScope?,
        pulseDemand: TheTripwire.TickDemand
    ) -> TheTripwire.TickDemand? {
        switch state {
        case .stopped:
            return nil
        case .armed(_, let lastIdentity):
            state = .armed(
                demandedScope: scope,
                lastIdentity: lastIdentity
            )
        case .active(let identity, let activeScope, _, let task):
            state = .active(
                identity: identity,
                scope: activeScope,
                demandedScope: scope,
                task: task
            )
        }
        return scope == nil ? nil : pulseDemand
    }

    @discardableResult
    mutating func receive(
        _ pulse: TheTripwire.PulseReading,
        start: (Request) -> Task<Void, Never>
    ) -> Identity? {
        guard case .armed(let demandedScope?, let lastIdentity) = state else {
            return nil
        }
        let (nextIdentity, overflow) = lastIdentity.addingReportingOverflow(1)
        precondition(!overflow, "Semantic observation cycle identity overflow")
        let identity = Identity(rawValue: nextIdentity)
        let request = Request(
            identity: identity,
            pulse: pulse,
            scope: demandedScope
        )
        state = .active(
            identity: identity,
            scope: demandedScope,
            demandedScope: demandedScope,
            task: start(request)
        )
        return identity
    }

    mutating func complete(
        _ identity: Identity
    ) -> SemanticObservationScope? {
        guard case .active(
            let activeIdentity,
            let scope,
            let demandedScope,
            _
        ) = state,
              activeIdentity == identity else {
            return nil
        }
        state = .armed(
            demandedScope: demandedScope,
            lastIdentity: identity.rawValue
        )
        return scope
    }

    func owns(_ identity: Identity) -> Bool {
        guard case .active(let activeIdentity, _, _, _) = state else {
            return false
        }
        return activeIdentity == identity
    }

    mutating func stop() -> Stop? {
        switch state {
        case .stopped:
            return nil
        case .armed(_, let lastIdentity):
            state = .stopped(lastIdentity: lastIdentity)
            return Stop(activeTask: nil)
        case .active(let identity, _, _, let task):
            state = .stopped(lastIdentity: identity.rawValue)
            return Stop(activeTask: task)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
