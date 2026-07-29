#if canImport(UIKit)
#if DEBUG

/// Pure scheduling algebra for semantic observation.
///
/// The boundary owns `CADisplayLink` and capture tasks. This value decides
/// whether a delivered pulse starts a cycle or is dropped because a cycle is
/// already active or nobody currently demands observation.
struct SemanticObservationCycle {
    struct Request {
        let pulse: TheTripwire.PulseReading
        let scope: SemanticObservationScope
    }

    private enum Phase {
        case dormant
        case armed
        case cycling
    }

    private var phase = Phase.dormant
    private var demandedScope: SemanticObservationScope?

    mutating func demand(
        scope: SemanticObservationScope?,
        pulseDemand: TheTripwire.TickDemand
    ) -> TheTripwire.TickDemand? {
        demandedScope = scope
        switch (scope, phase) {
        case (.some, .dormant):
            phase = .armed
        case (.none, .armed):
            phase = .dormant
        case (.some, .armed),
             (.some, .cycling),
             (.none, .dormant),
             (.none, .cycling):
            break
        }
        return scope == nil ? nil : pulseDemand
    }

    mutating func receive(
        _ pulse: TheTripwire.PulseReading
    ) -> Request? {
        guard let demandedScope else { return nil }
        switch phase {
        case .dormant:
            return nil
        case .armed:
            phase = .cycling
            return Request(pulse: pulse, scope: demandedScope)
        case .cycling:
            return nil
        }
    }

    mutating func complete() {
        guard case .cycling = phase else { return }
        phase = demandedScope == nil ? .dormant : .armed
    }

    mutating func stop() {
        demandedScope = nil
        phase = .dormant
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
