#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

/// Owns the wait_for_change lifecycle and the last semantic state delivered to
/// the driver, which is the command's baseline for "already changed" checks.
@MainActor
final class WaitForChangeState {
    struct Predicate {
        let expectation: ActionExpectation?
        let deadline: CFAbsoluteTime
    }

    private enum Phase {
        case idle
        case waiting(Predicate)
    }

    private var phase: Phase = .idle
    private var deliveredBaseline: PostActionObservation.BeforeState?

    var lastDeliveredBaseline: PostActionObservation.BeforeState? {
        guard let deliveredBaseline, !deliveredBaseline.capture.hash.isEmpty else {
            return nil
        }
        return deliveredBaseline
    }

    func install(
        expectation: ActionExpectation?,
        timeout: TimeInterval,
        start: CFAbsoluteTime
    ) -> Predicate? {
        guard case .idle = phase else { return nil }
        let predicate = Predicate(
            expectation: expectation,
            deadline: start + timeout
        )
        phase = .waiting(predicate)
        return predicate
    }

    func finish() {
        phase = .idle
    }

    func recordDeliveredBaseline(_ beforeState: PostActionObservation.BeforeState) {
        deliveredBaseline = beforeState
    }

    func resetDeliveredBaseline() {
        deliveredBaseline = nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
