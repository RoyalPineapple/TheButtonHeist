import Foundation
import ThePlans

public struct HeistCaseSelectionEvidence: Codable, Sendable, Equatable {
    public let selection: HeistCaseSelectionResult

    public init(selection: HeistCaseSelectionResult) {
        self.selection = selection
    }
}

public enum HeistCaseSelectionMissReason: String, Codable, Sendable, Equatable {
    case noMatch = "no_match"
    case timedOut = "timed_out"
}

public enum HeistCaseSelectionOutcome: Codable, Sendable, Equatable {
    case matchedCase(index: UInt)
    case elseBranch(reason: HeistCaseSelectionMissReason)
    case timedOut
    case noMatch

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case index
        case reason
    }

    private enum Kind: String, Codable {
        case matchedCase = "matched_case"
        case elseBranch = "else_branch"
        case timedOut = "timed_out"
        case noMatch = "no_match"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist case selection outcome")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let typeName = "\(kind.rawValue) outcome"
        switch kind {
        case .matchedCase:
            try container.rejectIncompatibleFields(allowing: [.kind, .index], typeName: typeName)
            guard let index = try container.decodeIfPresent(UInt.self, forKey: .index) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .index,
                    in: container,
                    debugDescription: "matched_case outcome requires index"
                )
            }
            self = .matchedCase(index: index)
        case .elseBranch:
            try container.rejectIncompatibleFields(allowing: [.kind, .reason], typeName: typeName)
            self = .elseBranch(
                reason: try container.decode(HeistCaseSelectionMissReason.self, forKey: .reason)
            )
        case .timedOut:
            try container.rejectIncompatibleFields(allowing: [.kind], typeName: typeName)
            self = .timedOut
        case .noMatch:
            try container.rejectIncompatibleFields(allowing: [.kind], typeName: typeName)
            self = .noMatch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .matchedCase(let index):
            try container.encode(Kind.matchedCase, forKey: .kind)
            try container.encode(index, forKey: .index)
        case .elseBranch(let reason):
            try container.encode(Kind.elseBranch, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .timedOut:
            try container.encode(Kind.timedOut, forKey: .kind)
        case .noMatch:
            try container.encode(Kind.noMatch, forKey: .kind)
        }
    }
}

public struct HeistCaseSelectionResult: Codable, Sendable, Equatable {
    public let cases: [HeistCaseMatchResult]
    public let outcome: HeistCaseSelectionOutcome
    public let elapsedMs: ElapsedMilliseconds
    public let timeout: Double?
    public let lastObservedSummary: String?

    public static func selectingFirstMatch(
        cases: [HeistCaseMatchResult],
        ifNone: HeistCaseSelectionMissReason,
        elapsedMs: ElapsedMilliseconds,
        timeout: Double? = nil,
        lastObservedSummary: String? = nil
    ) -> Self {
        let matchedIndex = cases.firstIndex(where: \.met).map(UInt.init)
        let outcome = matchedIndex.map(HeistCaseSelectionOutcome.matchedCase(index:))
            ?? (ifNone == .timedOut ? .timedOut : .noMatch)
        requireValidLiteralPayload {
            try Self.validate(
                outcome: outcome,
                cases: cases,
                elapsedMs: elapsedMs,
                timeout: timeout,
                codingPath: []
            )
        }
        return Self(
            cases: cases,
            outcome: outcome,
            elapsedMs: elapsedMs,
            timeout: timeout,
            lastObservedSummary: lastObservedSummary
        )
    }

    package func selectingElseBranch() -> Self {
        let reason: HeistCaseSelectionMissReason
        switch outcome {
        case .noMatch:
            reason = .noMatch
        case .timedOut:
            reason = .timedOut
        case .matchedCase, .elseBranch:
            preconditionFailure("only an unmatched case selection can enter the else branch")
        }
        return Self(
            cases: cases,
            outcome: .elseBranch(reason: reason),
            elapsedMs: elapsedMs,
            timeout: timeout,
            lastObservedSummary: lastObservedSummary
        )
    }

    private init(
        cases: [HeistCaseMatchResult],
        outcome: HeistCaseSelectionOutcome,
        elapsedMs: ElapsedMilliseconds,
        timeout: Double?,
        lastObservedSummary: String?
    ) {
        self.cases = cases
        self.outcome = outcome
        self.elapsedMs = elapsedMs
        self.timeout = timeout
        self.lastObservedSummary = lastObservedSummary
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cases
        case outcome
        case elapsedMs
        case timeout
        case lastObservedSummary
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist case selection result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cases = try container.decode([HeistCaseMatchResult].self, forKey: .cases)
        let outcome = try container.decode(HeistCaseSelectionOutcome.self, forKey: .outcome)
        let elapsedMs = try container.decode(ElapsedMilliseconds.self, forKey: .elapsedMs)
        let timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
        try Self.validate(
            outcome: outcome,
            cases: cases,
            elapsedMs: elapsedMs,
            timeout: timeout,
            codingPath: container.codingPath
        )
        self.init(
            cases: cases,
            outcome: outcome,
            elapsedMs: elapsedMs,
            timeout: timeout,
            lastObservedSummary: try container.decodeIfPresent(String.self, forKey: .lastObservedSummary)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cases, forKey: .cases)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(lastObservedSummary, forKey: .lastObservedSummary)
    }

    private static func validate(
        outcome: HeistCaseSelectionOutcome,
        cases: [HeistCaseMatchResult],
        elapsedMs: ElapsedMilliseconds,
        timeout: Double?,
        codingPath: [CodingKey]
    ) throws {
        guard timeout.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath + [CodingKeys.timeout],
                debugDescription: "case selection timeout must be finite and non-negative"
            ))
        }

        switch outcome {
        case .matchedCase(let ordinal):
            guard let index = Int(exactly: ordinal), cases.indices.contains(index) else {
                throw invalidOutcome(
                    codingPath: codingPath,
                    description: "matched_case index \(ordinal) is out of range for \(cases.count) case(s)"
                )
            }
            guard cases[index].met else {
                throw invalidOutcome(
                    codingPath: codingPath,
                    description: "matched_case index \(ordinal) refers to an unmet case"
                )
            }
            guard cases.firstIndex(where: \.met) == index else {
                throw invalidOutcome(
                    codingPath: codingPath,
                    description: "matched_case index \(ordinal) is not the first matched case"
                )
            }
        case .elseBranch, .timedOut, .noMatch:
            guard !cases.contains(where: \.met) else {
                throw invalidOutcome(
                    codingPath: codingPath,
                    description: "unmatched case selection outcome cannot contain a matched case"
                )
            }
        }

        switch outcome {
        case .timedOut, .elseBranch(reason: .timedOut):
            guard timeout.map({ $0 > 0 }) ?? false else {
                throw invalidOutcome(
                    codingPath: codingPath,
                    description: "timed_out outcome requires a positive timeout"
                )
            }
        case .matchedCase, .elseBranch, .noMatch:
            break
        }
    }

    private static func invalidOutcome(
        codingPath: [CodingKey],
        description: String
    ) -> DecodingError {
        .dataCorrupted(.init(
            codingPath: codingPath + [CodingKeys.outcome],
            debugDescription: description
        ))
    }
}

public struct HeistCaseMatchResult: Codable, Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let met: Bool
    public let actual: String?

    public var result: ExpectationResult {
        ExpectationResult(met: met, predicate: predicate, actual: actual)
    }

    public init(
        predicate: AccessibilityPredicate,
        met: Bool,
        actual: String? = nil
    ) {
        self.predicate = predicate
        self.met = met
        self.actual = actual
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate
        case met
        case actual
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist case match result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            met: try container.decode(Bool.self, forKey: .met),
            actual: try container.decodeIfPresent(String.self, forKey: .actual)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(met, forKey: .met)
        try container.encodeIfPresent(actual, forKey: .actual)
    }
}
