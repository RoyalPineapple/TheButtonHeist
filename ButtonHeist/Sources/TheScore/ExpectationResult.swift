import ThePlans
import Foundation

/// Predicate-local evaluation facts before they are attached to an
/// `ExpectationResult` boundary value.
public struct PredicateEvaluationResult: Sendable, Equatable {
    public let met: Bool
    public let actual: String?

    public init(met: Bool, actual: String? = nil) {
        self.met = met
        self.actual = actual
    }

    public func expectation(for predicate: AccessibilityPredicate?) -> ExpectationResult {
        ExpectationResult(met: met, predicate: predicate, actual: actual)
    }
}

/// Predicate evidence derived from an observed trace before any lossy endpoint
/// projection is chosen for reporting.
public struct PredicateEvaluationEvidence: Sendable, Equatable {
    public let currentElements: [HeistElement]
    public let accumulatedDelta: AccessibilityTrace.AccumulatedDelta?

    public init(
        currentElements: [HeistElement],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) {
        self.currentElements = currentElements
        self.accumulatedDelta = accumulatedDelta
    }

    public init(trace: AccessibilityTrace) {
        self.init(
            currentElements: trace.captures.last?.interface.projectedElements ?? [],
            accumulatedDelta: trace.accumulatedDelta
        )
    }
}

/// The outcome of checking an `AccessibilityPredicate` against an observed
/// interface or transition delta.
public struct ExpectationResult: Codable, Sendable, Equatable {
    /// Whether the predicate was met.
    public let met: Bool
    /// The predicate that was checked. Nil for implicit delivery check.
    public let predicate: AccessibilityPredicate?
    /// What was actually observed (for diagnostics when `met` is false).
    public let actual: String?

    public init(met: Bool, predicate: AccessibilityPredicate?, actual: String? = nil) {
        self.met = met
        self.predicate = predicate
        self.actual = actual
    }

    public init(_ result: PredicateEvaluationResult, predicate: AccessibilityPredicate?) {
        self.init(met: result.met, predicate: predicate, actual: result.actual)
    }
}

extension ExpectationResult: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("expectation", [
            ScoreDescription.valueField("met", met),
            predicate.map { "expected=\($0)" },
            ScoreDescription.stringField("actual", actual),
        ].compactMap { $0 })
    }
}
