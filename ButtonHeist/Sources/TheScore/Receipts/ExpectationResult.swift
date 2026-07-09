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
    public let currentInterface: Interface?
    public let currentElements: [HeistElement]
    public let accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    public let geometryAccumulatedDelta: AccessibilityTrace.AccumulatedDelta?

    public init(
        currentInterface: Interface? = nil,
        currentElements: [HeistElement],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?,
        geometryAccumulatedDelta: AccessibilityTrace.AccumulatedDelta? = nil
    ) {
        self.currentInterface = currentInterface
        self.currentElements = currentElements
        self.accumulatedDelta = accumulatedDelta
        self.geometryAccumulatedDelta = geometryAccumulatedDelta
    }

    public init(
        currentElements: [HeistElement],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?,
        geometryAccumulatedDelta: AccessibilityTrace.AccumulatedDelta? = nil
    ) {
        self.init(
            currentInterface: nil,
            currentElements: currentElements,
            accumulatedDelta: accumulatedDelta,
            geometryAccumulatedDelta: geometryAccumulatedDelta
        )
    }

    public init(trace: AccessibilityTrace) {
        let interface = trace.captures.last?.interface
        self.init(
            currentInterface: interface,
            currentElements: interface?.projectedElements ?? [],
            accumulatedDelta: trace.accumulatedDelta,
            geometryAccumulatedDelta: trace.accumulatedDelta(projection: .geometryAware)
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

public struct MetExpectationResult: Sendable, Equatable {
    public let result: ExpectationResult

    fileprivate init(unchecked result: ExpectationResult) {
        self.result = result
    }

    public init?(_ result: ExpectationResult) {
        guard result.met else { return nil }
        self.result = result
    }

    public init(predicate: AccessibilityPredicate?, actual: String? = nil) {
        result = ExpectationResult(met: true, predicate: predicate, actual: actual)
    }
}

public struct UnmetExpectationResult: Sendable, Equatable {
    public let result: ExpectationResult

    fileprivate init(unchecked result: ExpectationResult) {
        self.result = result
    }

    public init?(_ result: ExpectationResult) {
        guard !result.met else { return nil }
        self.result = result
    }

    public init(predicate: AccessibilityPredicate?, actual: String? = nil) {
        result = ExpectationResult(met: false, predicate: predicate, actual: actual)
    }
}

public enum PredicateExpectationCheck: Sendable, Equatable {
    case met(MetExpectationResult)
    case unmet(UnmetExpectationResult)

    public init(_ result: ExpectationResult) {
        if result.met {
            self = .met(MetExpectationResult(unchecked: result))
        } else {
            self = .unmet(UnmetExpectationResult(unchecked: result))
        }
    }

    public var result: ExpectationResult {
        switch self {
        case .met(let expectation):
            return expectation.result
        case .unmet(let expectation):
            return expectation.result
        }
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
