import Foundation

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
