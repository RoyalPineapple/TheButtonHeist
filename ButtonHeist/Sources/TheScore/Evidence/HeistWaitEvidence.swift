import Foundation
import ThePlans

/// Replayable facts supporting one authored expectation.
///
/// This value stores no verdict. Live and decoded results both derive their
/// `ExpectationResult` by evaluating the resolved predicate over `observation`.
public struct HeistExpectationEvidence: Codable, Sendable, Equatable {
    public enum TerminalCause: String, Codable, Sendable, Equatable {
        case observed
        case deadline
        case cancelled
        case unavailable
        case viewportFailure = "viewport_failure"
    }

    public let predicate: AccessibilityPredicate
    public let observation: Observation.Evidence
    public let terminalCause: TerminalCause
    package let resolvedPredicate: ObservationPredicate

    package init(
        predicate: AccessibilityPredicate,
        resolvedPredicate: ObservationPredicate,
        observation: Observation.Evidence,
        terminalCause: TerminalCause
    ) {
        self.predicate = predicate
        self.resolvedPredicate = resolvedPredicate
        self.observation = observation
        self.terminalCause = terminalCause
    }

    package func replay() throws(Observation.Gap) -> ExpectationResult {
        let evaluation = try resolvedPredicate.evaluate(in: observation)
        let met = evaluation.met && terminalCause.admitsMatch
        let actual = terminalCause.unmetDescription
            ?? evaluation.actual
            ?? matchingNotificationText(met: met)
        return ExpectationResult(
            met: met,
            predicate: predicate,
            actual: actual
        )
    }

    private func matchingNotificationText(met: Bool) -> String? {
        guard met, case .notification(let predicate) = resolvedPredicate else { return nil }
        return observation.events.lazy.compactMap { event -> Observation.Notification? in
            guard case .notification(let notification) = event else { return nil }
            return notification
        }
        .first(where: predicate.matches)?
        .text
    }
}

private extension HeistExpectationEvidence.TerminalCause {
    var admitsMatch: Bool {
        switch self {
        case .observed, .deadline:
            true
        case .cancelled, .unavailable, .viewportFailure:
            false
        }
    }

    var unmetDescription: String? {
        admitsMatch ? nil : "terminal cause: \(rawValue)"
    }
}
