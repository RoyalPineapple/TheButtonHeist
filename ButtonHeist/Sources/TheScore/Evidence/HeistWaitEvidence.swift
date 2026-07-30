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
/// `ExpectationResult` by resolving `predicate` through its captured bindings
/// and evaluating that one executable predicate over `observation`.
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
    package let bindings: HeistExecutionEnvironment

    package init(
        predicate: AccessibilityPredicate,
        bindings: HeistExecutionEnvironment,
        observation: Observation.Evidence,
        terminalCause: TerminalCause,
        timing: HeistExpectationTiming
    ) throws {
        _ = try predicate.resolve(in: bindings)
        self.predicate = predicate
        self.bindings = bindings
        self.observation = observation
        self.terminalCause = terminalCause
        self.timing = timing
    }

    package func replay() throws(Observation.Gap) -> ExpectationResult {
        let boundPredicate: ObservationPredicate
        do {
            boundPredicate = try predicate.resolve(in: bindings)
        } catch {
            preconditionFailure("Admitted expectation bindings became invalid: \(error)")
        }
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
            ?? matchingNotificationText(met: met, boundPredicate: boundPredicate)
        return ExpectationResult(
            met: met,
            predicate: predicate,
            actual: actual
        )
    }

    /// Interprets durable expectation evidence without turning incomplete
    /// observation coverage into control flow.
    package var replayResult: Result<ExpectationResult, Observation.Gap> {
        do {
            return .success(try replay())
        } catch {
            return .failure(error)
        }
    }

    private func matchingNotificationText(
        met: Bool,
        boundPredicate: ObservationPredicate
    ) -> String? {
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
        case bindings
        case observation
        case terminalCause
        case timing
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist expectation evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let bindings = try container.decode(HeistExecutionEnvironment.self, forKey: .bindings)
        let observation = try container.decode(Observation.Evidence.self, forKey: .observation)
        let terminalCause = try container.decode(TerminalCause.self, forKey: .terminalCause)
        let timing = try container.decode(HeistExpectationTiming.self, forKey: .timing)
        do {
            try self.init(
                predicate: predicate,
                bindings: bindings,
                observation: observation,
                terminalCause: terminalCause,
                timing: timing
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .bindings,
                in: container,
                debugDescription: "bindings cannot resolve expectation predicate: \(error)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(bindings, forKey: .bindings)
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
