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
public enum ExpectationResult: Codable, Sendable, Equatable {
    public struct Met: Sendable, Equatable {
        public let predicate: AccessibilityPredicate<RootContext>?
        public let actual: String?

        public init(predicate: AccessibilityPredicate<RootContext>?, actual: String? = nil) {
            self.predicate = predicate
            self.actual = actual
        }

        public init?(_ result: ExpectationResult) {
            guard case .met(let evidence) = result else { return nil }
            self = evidence
        }

        public var result: ExpectationResult { .met(self) }
    }

    public struct Unmet: Sendable, Equatable {
        public let predicate: AccessibilityPredicate<RootContext>?
        public let actual: String?

        public init(predicate: AccessibilityPredicate<RootContext>?, actual: String? = nil) {
            self.predicate = predicate
            self.actual = actual
        }

        public init?(_ result: ExpectationResult) {
            guard case .unmet(let evidence) = result else { return nil }
            self = evidence
        }

        public var result: ExpectationResult { .unmet(self) }
    }

    case met(Met)
    case unmet(Unmet)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case met
        case predicate
        case actual
    }

    public init(met: Bool, predicate: AccessibilityPredicate<RootContext>?, actual: String? = nil) {
        self = met
            ? .met(Met(predicate: predicate, actual: actual))
            : .unmet(Unmet(predicate: predicate, actual: actual))
    }

    public init(_ result: PredicateEvaluationResult, predicate: AccessibilityPredicate<RootContext>?) {
        self.init(met: result.met, predicate: predicate, actual: result.actual)
    }

    public var met: Bool {
        if case .met = self { return true }
        return false
    }

    public var predicate: AccessibilityPredicate<RootContext>? {
        switch self {
        case .met(let evidence): evidence.predicate
        case .unmet(let evidence): evidence.predicate
        }
    }

    public var actual: String? {
        switch self {
        case .met(let evidence): evidence.actual
        case .unmet(let evidence): evidence.actual
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ExpectationResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            met: try container.decode(Bool.self, forKey: .met),
            predicate: try container.decodeIfPresent(
                AccessibilityPredicate<RootContext>.self,
                forKey: .predicate
            ),
            actual: try container.decodeIfPresent(String.self, forKey: .actual)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(met, forKey: .met)
        try container.encodeIfPresent(predicate, forKey: .predicate)
        try container.encodeIfPresent(actual, forKey: .actual)
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
