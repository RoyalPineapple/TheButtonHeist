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

/// The result of checking a structural expectation, including an optional
/// authored predicate and observed evidence.
public enum ExpectationResult: Codable, Sendable, Equatable {
    public struct Met: Codable, Sendable, Equatable {
        public let predicate: AccessibilityPredicate?
        public let actual: String?

        public init(predicate: AccessibilityPredicate?, actual: String? = nil) {
            self.predicate = predicate
            self.actual = actual
        }

        public init?(_ result: ExpectationResult) {
            guard case .met(let evidence) = result else { return nil }
            self = evidence
        }

        public var result: ExpectationResult { .met(self) }
    }

    public struct Unmet: Codable, Sendable, Equatable {
        public let predicate: AccessibilityPredicate?
        public let actual: String?

        public init(predicate: AccessibilityPredicate?, actual: String? = nil) {
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

    public init(met: Bool, predicate: AccessibilityPredicate?, actual: String? = nil) {
        self = met
            ? .met(Met(predicate: predicate, actual: actual))
            : .unmet(Unmet(predicate: predicate, actual: actual))
    }

    public init(_ result: PredicateEvaluationResult, predicate: AccessibilityPredicate?) {
        self.init(met: result.met, predicate: predicate, actual: result.actual)
    }

    public var met: Bool {
        if case .met = self { return true }
        return false
    }

    public var predicate: AccessibilityPredicate? {
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

    package var matchedAnnouncement: String? {
        guard met,
              let predicate,
              case .notification = predicate.core else { return nil }
        return actual
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ExpectationResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            met: try container.decode(Bool.self, forKey: .met),
            predicate: try container.decodeIfPresent(
                AccessibilityPredicate.self,
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
        CanonicalValueDescription.call("expectation", [
            CanonicalValueDescription.valueField("met", met),
            predicate.map { "expected=\($0)" },
            CanonicalValueDescription.stringField("actual", actual),
        ].compactMap { $0 })
    }
}
