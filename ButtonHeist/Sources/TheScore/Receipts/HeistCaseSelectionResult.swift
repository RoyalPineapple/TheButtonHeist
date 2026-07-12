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
    case matchedCase(index: Int)
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
        switch try container.decode(Kind.self, forKey: .kind) {
        case .matchedCase:
            try Self.rejectIfPresent(.reason, in: container, kind: .matchedCase)
            guard let index = try container.decodeIfPresent(Int.self, forKey: .index) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .index,
                    in: container,
                    debugDescription: "matched_case outcome requires index"
                )
            }
            guard index >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .index,
                    in: container,
                    debugDescription: "matched_case index must be non-negative"
                )
            }
            self = .matchedCase(index: index)
        case .elseBranch:
            try Self.rejectIfPresent(.index, in: container, kind: .elseBranch)
            self = .elseBranch(
                reason: try container.decode(HeistCaseSelectionMissReason.self, forKey: .reason)
            )
        case .timedOut:
            try Self.rejectIfPresent(.index, in: container, kind: .timedOut)
            try Self.rejectIfPresent(.reason, in: container, kind: .timedOut)
            self = .timedOut
        case .noMatch:
            try Self.rejectIfPresent(.index, in: container, kind: .noMatch)
            try Self.rejectIfPresent(.reason, in: container, kind: .noMatch)
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

    private static func rejectIfPresent(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        kind: Kind
    ) throws {
        guard container.contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(kind.rawValue) outcome must not include \(key.stringValue)"
        )
    }
}

public struct HeistCaseSelectionResult: Codable, Sendable, Equatable {
    public let cases: [HeistCaseMatchResult]
    public let outcome: HeistCaseSelectionOutcome
    public let elapsedMs: Int
    public let timeout: Double?
    public let lastObservedSummary: String?

    public init(
        cases: [HeistCaseMatchResult],
        outcome: HeistCaseSelectionOutcome,
        elapsedMs: Int,
        timeout: Double? = nil,
        lastObservedSummary: String? = nil
    ) {
        do {
            try Self.validate(outcome: outcome, cases: cases, codingPath: [])
        } catch {
            preconditionFailure("Invalid heist case selection result: \(error)")
        }
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
        try Self.validate(outcome: outcome, cases: cases, codingPath: container.codingPath)

        self.cases = cases
        self.outcome = outcome
        elapsedMs = try container.decode(Int.self, forKey: .elapsedMs)
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
        lastObservedSummary = try container.decodeIfPresent(String.self, forKey: .lastObservedSummary)
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
        codingPath: [CodingKey]
    ) throws {
        guard case .matchedCase(let index) = outcome else { return }
        guard cases.indices.contains(index) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath + [CodingKeys.outcome],
                debugDescription: "matched_case index \(index) is out of range for \(cases.count) case(s)"
            ))
        }
        guard cases[index].result.met else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath + [CodingKeys.outcome],
                debugDescription: "matched_case index \(index) refers to an unmet case"
            ))
        }
    }
}

public struct HeistCaseMatchResult: Codable, Sendable, Equatable {
    public let result: ExpectationResult
    public var predicate: AccessibilityPredicate { result.predicate }

    public init(
        predicate: AccessibilityPredicate,
        result: ExpectationResult
    ) {
        precondition(result.predicate == predicate, "HeistCaseMatchResult result predicate must match predicate")
        self.result = result
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate
        case result
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist case match result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let result = try container.decode(ExpectationResult.self, forKey: .result)
        guard result.predicate == predicate else {
            throw DecodingError.dataCorruptedError(
                forKey: .result,
                in: container,
                debugDescription: "heist case match result predicate must match nested expectation result predicate"
            )
        }
        self.result = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(result, forKey: .result)
    }
}
