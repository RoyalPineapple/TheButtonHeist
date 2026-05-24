#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

/// Owns the single in-flight wait_for_change lifecycle.
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
}

#endif // DEBUG
#endif // canImport(UIKit)
