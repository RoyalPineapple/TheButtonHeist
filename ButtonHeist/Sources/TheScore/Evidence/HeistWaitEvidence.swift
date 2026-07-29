import Foundation
import ThePlans

/// Replayable facts supporting one authored expectation.
///
/// This value stores no verdict. Live and decoded results both derive their
/// `ExpectationResult` by evaluating the bound predicate over `observation`.
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
    private let boundPredicate: ObservationPredicate

    package init(
        predicate: AccessibilityPredicate,
        observation: Observation.Evidence,
        terminalCause: TerminalCause
    ) throws {
        self.predicate = predicate
        self.boundPredicate = try predicate.resolve(in: .empty)
        self.observation = observation
        self.terminalCause = terminalCause
    }

    package func replay() throws(Observation.Gap) -> ExpectationResult {
        let result = Expectation(
            [boundPredicate, .noChange],
            baseline: observation.baseline,
            events: observation.events
        ).result
        if case .incomplete(let gap) = observation.coverage {
            throw gap
        }
        let met = result == .satisfied && terminalCause.admitsMatch
        let actual = terminalCause.unmetDescription
            ?? result.outstandingDescription
            ?? matchingNotificationText(met: met)
        return ExpectationResult(
            met: met,
            predicate: predicate,
            actual: actual
        )
    }

    private func matchingNotificationText(met: Bool) -> String? {
        guard met, case .notification(let predicate) = boundPredicate else { return nil }
        return observation.events.lazy.compactMap { event -> Observation.Notification? in
            guard case .notification(let notification) = event else { return nil }
            return notification
        }
        .first(where: predicate.matches)?
        .text
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate
        case observation
        case terminalCause
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist expectation evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let observation = try container.decode(Observation.Evidence.self, forKey: .observation)
        let terminalCause = try container.decode(TerminalCause.self, forKey: .terminalCause)
        do {
            try self.init(
                predicate: predicate,
                observation: observation,
                terminalCause: terminalCause
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.predicate],
                debugDescription: "heist expectation predicate must be fully bound: \(error)"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(observation, forKey: .observation)
        try container.encode(terminalCause, forKey: .terminalCause)
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
