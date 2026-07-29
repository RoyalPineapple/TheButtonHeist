import Foundation
import ThePlans

/// Monotonic timing facts for one observed expectation.
public struct HeistExpectationTiming: Codable, Sendable, Equatable {
    public let budgetMs: ElapsedMilliseconds
    public let elapsedMs: ElapsedMilliseconds
    public let lastTreeChangeElapsedMs: ElapsedMilliseconds?

    package init(
        budgetMs: ElapsedMilliseconds,
        elapsedMs: ElapsedMilliseconds,
        lastTreeChangeElapsedMs: ElapsedMilliseconds?
    ) {
        self.budgetMs = budgetMs
        self.elapsedMs = elapsedMs
        self.lastTreeChangeElapsedMs = lastTreeChangeElapsedMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case budgetMs
        case elapsedMs
        case lastTreeChangeElapsedMs
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            typeName: "heist expectation timing"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let budgetMs = try container.decode(ElapsedMilliseconds.self, forKey: .budgetMs)
        let elapsedMs = try container.decode(ElapsedMilliseconds.self, forKey: .elapsedMs)
        let lastTreeChangeElapsedMs = try container.decodeIfPresent(
            ElapsedMilliseconds.self,
            forKey: .lastTreeChangeElapsedMs
        )
        guard lastTreeChangeElapsedMs?.milliseconds ?? 0 <= elapsedMs.milliseconds else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "last tree change cannot follow expectation completion"
            ))
        }
        self.init(
            budgetMs: budgetMs,
            elapsedMs: elapsedMs,
            lastTreeChangeElapsedMs: lastTreeChangeElapsedMs
        )
    }
}

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
    public let timing: HeistExpectationTiming
    package let boundPredicate: ObservationPredicate

    package init(
        predicate: AccessibilityPredicate,
        boundPredicate: ObservationPredicate,
        observation: Observation.Evidence,
        terminalCause: TerminalCause,
        timing: HeistExpectationTiming
    ) {
        self.predicate = predicate
        self.boundPredicate = boundPredicate
        self.observation = observation
        self.terminalCause = terminalCause
        self.timing = timing
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
        case boundPredicate
        case observation
        case terminalCause
        case timing
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist expectation evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let boundPredicate = try container.decode(
            ObservationPredicate.self,
            forKey: .boundPredicate
        )
        let observation = try container.decode(Observation.Evidence.self, forKey: .observation)
        let terminalCause = try container.decode(TerminalCause.self, forKey: .terminalCause)
        let timing = try container.decode(HeistExpectationTiming.self, forKey: .timing)
        self.init(
            predicate: predicate,
            boundPredicate: boundPredicate,
            observation: observation,
            terminalCause: terminalCause,
            timing: timing
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(boundPredicate, forKey: .boundPredicate)
        try container.encode(observation, forKey: .observation)
        try container.encode(terminalCause, forKey: .terminalCause)
        try container.encode(timing, forKey: .timing)
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
