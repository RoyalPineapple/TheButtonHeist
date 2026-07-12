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

    public func expectation(for predicate: AccessibilityPredicate<RootContext>?) -> ExpectationResult {
        ExpectationResult(met: met, predicate: predicate, actual: actual)
    }
}

/// Predicate evidence derived from one canonical observed trace.
public struct PredicateEvaluationEvidence: Sendable, Equatable {
    public let trace: AccessibilityTrace
    public let isComplete: Bool

    public init?(trace: AccessibilityTrace, isComplete: Bool) {
        guard trace.captures.last != nil else { return nil }
        self.trace = trace
        self.isComplete = isComplete
    }

    package var currentInterface: Interface {
        guard let current = trace.captures.last?.interface else {
            preconditionFailure("PredicateEvaluationEvidence requires a current capture")
        }
        return current
    }

    package var changeFacts: [AccessibilityTrace.ChangeFact] {
        trace.changeFacts
    }
}

/// The outcome of checking an `AccessibilityPredicate` against an observed
/// interface or transition delta.
public struct ExpectationResult: Codable, Sendable, Equatable {
    /// Whether the predicate was met.
    public let met: Bool
    /// The predicate that was checked. Nil for implicit delivery check.
    public let predicate: AccessibilityPredicate<RootContext>?
    /// What was actually observed (for diagnostics when `met` is false).
    public let actual: String?

    public init(met: Bool, predicate: AccessibilityPredicate<RootContext>?, actual: String? = nil) {
        self.met = met
        self.predicate = predicate
        self.actual = actual
    }

    public init(_ result: PredicateEvaluationResult, predicate: AccessibilityPredicate<RootContext>?) {
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

    public init(predicate: AccessibilityPredicate<RootContext>?, actual: String? = nil) {
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

    public init(predicate: AccessibilityPredicate<RootContext>?, actual: String? = nil) {
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
