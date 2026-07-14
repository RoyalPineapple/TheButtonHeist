import Foundation
import ThePlans

public enum HeistExecutionStepKind: String, Codable, Sendable, Equatable {
    case action
    case wait
    case conditional
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case forEachIteration = "for_each_iteration"
    case repeatUntil = "repeat_until"
    case repeatUntilIteration = "repeat_until_iteration"
    case warn
    case fail
    case heist
    case invoke
}

package struct HeistStepReceiptKind<Evidence>: Sendable {
    package let stepKind: HeistExecutionStepKind
    fileprivate let wrapEvidence: @Sendable (Evidence) -> HeistStepEvidence

    fileprivate init(
        stepKind: HeistExecutionStepKind,
        wrapEvidence: @escaping @Sendable (Evidence) -> HeistStepEvidence
    ) {
        self.stepKind = stepKind
        self.wrapEvidence = wrapEvidence
    }
}

package extension HeistStepReceiptKind where Evidence == HeistActionEvidence {
    static var action: Self {
        Self(stepKind: .action, wrapEvidence: HeistStepEvidence.action)
    }
}

package extension HeistStepReceiptKind where Evidence == HeistWaitEvidence {
    static var wait: Self {
        Self(stepKind: .wait, wrapEvidence: HeistStepEvidence.wait)
    }
}

package extension HeistStepReceiptKind where Evidence == HeistCaseSelectionEvidence {
    static var conditional: Self {
        Self(stepKind: .conditional, wrapEvidence: HeistStepEvidence.caseSelection)
    }
}

package extension HeistStepReceiptKind where Evidence == HeistForEachElementEvidence {
    static var forEachElement: Self {
        Self(stepKind: .forEachElement, wrapEvidence: HeistStepEvidence.forEachElement)
    }

    static var forEachElementIteration: Self {
        Self(stepKind: .forEachIteration, wrapEvidence: HeistStepEvidence.forEachElement)
    }
}

package extension HeistStepReceiptKind where Evidence == HeistForEachStringEvidence {
    static var forEachString: Self {
        Self(stepKind: .forEachString, wrapEvidence: HeistStepEvidence.forEachString)
    }

    static var forEachStringIteration: Self {
        Self(stepKind: .forEachIteration, wrapEvidence: HeistStepEvidence.forEachString)
    }
}

package extension HeistStepReceiptKind where Evidence == HeistRepeatUntilEvidence {
    static var repeatUntil: Self {
        Self(stepKind: .repeatUntil, wrapEvidence: HeistStepEvidence.repeatUntil)
    }

    static var repeatUntilIteration: Self {
        Self(stepKind: .repeatUntilIteration, wrapEvidence: HeistStepEvidence.repeatUntil)
    }
}

package extension HeistStepReceiptKind where Evidence == HeistInvocationEvidence {
    static var heist: Self {
        Self(stepKind: .heist, wrapEvidence: HeistStepEvidence.invocation)
    }

    static var invocation: Self {
        Self(stepKind: .invoke, wrapEvidence: HeistStepEvidence.invocation)
    }
}

package extension HeistStepReceiptKind where Evidence == HeistExecutionWarning {
    static var warning: Self {
        Self(stepKind: .warn, wrapEvidence: HeistStepEvidence.warning)
    }
}

public enum HeistExecutionStepStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case skipped
}

/// One node in a heist execution receipt tree.
public struct HeistExecutionStepResult: Codable, Sendable, Equatable {
    /// JSON-style path to this execution node in the heist program tree.
    public let path: String
    public let kind: HeistExecutionStepKind
    public let durationMs: Int

    public let intent: HeistStepIntent?
    public let outcome: HeistExecutionStepOutcome

    public var status: HeistExecutionStepStatus {
        outcome.status
    }

    public var evidence: HeistStepEvidence? {
        outcome.evidence
    }

    public var failure: HeistFailureDetail? {
        outcome.failure
    }

    public var abortedAtChildPath: String? {
        outcome.abortedAtChildPath
    }

    public var children: [HeistExecutionStepResult] {
        outcome.children
    }

    package static func passed(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        passed(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: nil,
            children: children
        )
    }

    package static func passed<Evidence>(
        path: String,
        receiptKind: HeistStepReceiptKind<Evidence>,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: Evidence,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        passed(
            path: path,
            kind: receiptKind.stepKind,
            durationMs: durationMs,
            intent: intent,
            evidence: receiptKind.wrapEvidence(evidence),
            children: children
        )
    }

    package static func passed(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence?,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            outcome: .passed(HeistExecutionStepPassedOutcome(
                evidence: evidence,
                children: children
            ))
        )
    }

    package static func failed(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        failure: HeistFailureDetail,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        failed(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: nil,
            failure: failure,
            children: children
        )
    }

    package static func failed<Evidence>(
        path: String,
        receiptKind: HeistStepReceiptKind<Evidence>,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: Evidence,
        failure: HeistFailureDetail,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        failed(
            path: path,
            kind: receiptKind.stepKind,
            durationMs: durationMs,
            intent: intent,
            evidence: receiptKind.wrapEvidence(evidence),
            failure: failure,
            children: children
        )
    }

    package static func failed(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence?,
        failure: HeistFailureDetail,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            outcome: .failed(HeistExecutionStepFailedOutcome(
                evidence: evidence,
                failure: failure,
                children: children
            ))
        )
    }

    package static func childAborted(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence,
        failure: HeistFailureDetail,
        abortedAtChildPath: String,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            outcome: .childAborted(HeistExecutionStepChildAbortedOutcome(
                evidence: evidence,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            ))
        )
    }

    package static func childAborted<Evidence>(
        path: String,
        receiptKind: HeistStepReceiptKind<Evidence>,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: Evidence,
        failure: HeistFailureDetail,
        abortedAtChildPath: String,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: receiptKind.stepKind,
            durationMs: durationMs,
            intent: intent,
            outcome: .childAborted(HeistExecutionStepChildAbortedOutcome(
                evidence: receiptKind.wrapEvidence(evidence),
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            ))
        )
    }

    package static func childAborted<Evidence>(
        path: String,
        receiptKind: HeistStepReceiptKind<Evidence>,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: Evidence,
        failure: HeistFailureDetail,
        child: HeistExecutionStepResult,
        remainingChildren: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        var children = [child]
        children.append(contentsOf: remainingChildren)
        return childAborted(
            path: path,
            receiptKind: receiptKind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            abortedAtChildPath: child.path,
            children: children
        )
    }

    private init(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        outcome: HeistExecutionStepOutcome
    ) {
        self.path = path
        self.kind = kind
        self.durationMs = durationMs
        self.intent = intent
        self.outcome = outcome
        do {
            try Self.validateExternalData(
                intent: intent,
                matches: kind,
                outcome: outcome,
                intentCodingPath: [],
                outcomeCodingPath: []
            )
        } catch {
            preconditionFailure("Invalid heist execution step result at \(path): \(error)")
        }
    }

    package static func skipped(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int = 0,
        intent: HeistStepIntent? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            outcome: .skipped(HeistExecutionStepSkippedOutcome(children: children))
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case kind
        case durationMs
        case intent
        case outcome
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution step result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .path)
        let kind = try container.decode(HeistExecutionStepKind.self, forKey: .kind)
        let durationMs = try container.decode(Int.self, forKey: .durationMs)
        let intent = try container.decodeIfPresent(HeistStepIntent.self, forKey: .intent)
        let outcome = try container.decode(HeistExecutionStepOutcome.self, forKey: .outcome)
        try Self.validateExternalData(
            intent: intent,
            matches: kind,
            outcome: outcome,
            intentCodingPath: container.codingPath + [CodingKeys.intent],
            outcomeCodingPath: container.codingPath + [CodingKeys.outcome]
        )
        self.path = path
        self.kind = kind
        self.durationMs = durationMs
        self.intent = intent
        self.outcome = outcome
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(kind, forKey: .kind)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encode(outcome, forKey: .outcome)
    }

    package func walk(
        enter: (HeistExecutionStepResult) throws -> Void,
        leave: (HeistExecutionStepResult) throws -> Void
    ) rethrows {
        try enter(self)
        for child in children {
            try child.walk(enter: enter, leave: leave)
        }
        try leave(self)
    }

    package var firstFailedStepInReceiptOrder: HeistExecutionStepResult? {
        var firstFailure: HeistExecutionStepResult?
        walk(
            enter: { _ in },
            leave: { step in
                if firstFailure == nil, step.status == .failed {
                    firstFailure = step
                }
            }
        )
        return firstFailure
    }
}

package extension Sequence where Element == HeistExecutionStepResult {
    func walk(
        enter: (HeistExecutionStepResult) throws -> Void,
        leave: (HeistExecutionStepResult) throws -> Void
    ) rethrows {
        for step in self {
            try step.walk(enter: enter, leave: leave)
        }
    }

    var firstFailedStepInReceiptOrder: HeistExecutionStepResult? {
        lazy.compactMap(\.firstFailedStepInReceiptOrder).first
    }
}

public enum HeistExecutionStepOutcome: Codable, Sendable, Equatable {
    case passed(HeistExecutionStepPassedOutcome)
    case failed(HeistExecutionStepFailedOutcome)
    case childAborted(HeistExecutionStepChildAbortedOutcome)
    case skipped(HeistExecutionStepSkippedOutcome)

    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case evidence
        case failure
        case abortedAtChildPath
        case children
    }

    private enum OutcomeType: String, Codable {
        case passed
        case failed
        case childAborted = "child_aborted"
        case skipped
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution step outcome")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(OutcomeType.self, forKey: .type) {
        case .passed:
            try container.rejectIncompatibleFields(
                allowing: [.type, .evidence, .children],
                typeName: "passed heist execution step outcome"
            )
            self = .passed(HeistExecutionStepPassedOutcome(
                evidence: try container.decodeIfPresent(HeistStepEvidence.self, forKey: .evidence),
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .failed:
            try container.rejectIncompatibleFields(
                allowing: [.type, .evidence, .failure, .children],
                typeName: "failed heist execution step outcome"
            )
            guard let failure = try container.decodeIfPresent(HeistFailureDetail.self, forKey: .failure) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .failure,
                    in: container,
                    debugDescription: "failed heist execution step outcome must include failure"
                )
            }
            self = .failed(HeistExecutionStepFailedOutcome(
                evidence: try container.decodeIfPresent(HeistStepEvidence.self, forKey: .evidence),
                failure: failure,
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .childAborted:
            try container.rejectIncompatibleFields(
                allowing: [.type, .evidence, .failure, .abortedAtChildPath, .children],
                typeName: "child_aborted heist execution step outcome"
            )
            self = .childAborted(HeistExecutionStepChildAbortedOutcome(
                evidence: try container.decode(HeistStepEvidence.self, forKey: .evidence),
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                abortedAtChildPath: try container.decode(String.self, forKey: .abortedAtChildPath),
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .skipped:
            try container.rejectIncompatibleFields(
                allowing: [.type, .children],
                typeName: "skipped heist execution step outcome"
            )
            self = .skipped(HeistExecutionStepSkippedOutcome(
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .passed(let outcome):
            try container.encode(OutcomeType.passed, forKey: .type)
            try container.encodeIfPresent(outcome.evidence, forKey: .evidence)
            try container.encode(outcome.children, forKey: .children)
        case .failed(let outcome):
            try container.encode(OutcomeType.failed, forKey: .type)
            try container.encodeIfPresent(outcome.evidence, forKey: .evidence)
            try container.encode(outcome.failure, forKey: .failure)
            try container.encode(outcome.children, forKey: .children)
        case .childAborted(let outcome):
            try container.encode(OutcomeType.childAborted, forKey: .type)
            try container.encode(outcome.evidence, forKey: .evidence)
            try container.encode(outcome.failure, forKey: .failure)
            try container.encode(outcome.abortedAtChildPath, forKey: .abortedAtChildPath)
            try container.encode(outcome.children, forKey: .children)
        case .skipped(let outcome):
            try container.encode(OutcomeType.skipped, forKey: .type)
            try container.encode(outcome.children, forKey: .children)
        }
    }

    public var status: HeistExecutionStepStatus {
        switch self {
        case .passed:
            return .passed
        case .failed, .childAborted:
            return .failed
        case .skipped:
            return .skipped
        }
    }

    public var evidence: HeistStepEvidence? {
        switch self {
        case .passed(let outcome):
            return outcome.evidence
        case .failed(let outcome):
            return outcome.evidence
        case .childAborted(let outcome):
            return outcome.evidence
        case .skipped:
            return nil
        }
    }

    public var failure: HeistFailureDetail? {
        switch self {
        case .passed, .skipped:
            return nil
        case .failed(let outcome):
            return outcome.failure
        case .childAborted(let outcome):
            return outcome.failure
        }
    }

    public var abortedAtChildPath: String? {
        switch self {
        case .passed, .failed, .skipped:
            return nil
        case .childAborted(let outcome):
            return outcome.abortedAtChildPath
        }
    }

    public var children: [HeistExecutionStepResult] {
        switch self {
        case .passed(let outcome):
            return outcome.children
        case .failed(let outcome):
            return outcome.children
        case .childAborted(let outcome):
            return outcome.children
        case .skipped(let outcome):
            return outcome.children
        }
    }
}

public struct HeistExecutionStepPassedOutcome: Sendable, Equatable {
    public let evidence: HeistStepEvidence?
    public let children: [HeistExecutionStepResult]

    fileprivate init(
        evidence: HeistStepEvidence?,
        children: [HeistExecutionStepResult]
    ) {
        self.evidence = evidence
        self.children = children
    }
}

public struct HeistExecutionStepFailedOutcome: Sendable, Equatable {
    public let evidence: HeistStepEvidence?
    public let failure: HeistFailureDetail
    public let children: [HeistExecutionStepResult]

    fileprivate init(
        evidence: HeistStepEvidence?,
        failure: HeistFailureDetail,
        children: [HeistExecutionStepResult]
    ) {
        self.evidence = evidence
        self.failure = failure
        self.children = children
    }
}

public struct HeistExecutionStepChildAbortedOutcome: Sendable, Equatable {
    public let evidence: HeistStepEvidence
    public let failure: HeistFailureDetail
    public let abortedAtChildPath: String
    public let children: [HeistExecutionStepResult]

    fileprivate init(
        evidence: HeistStepEvidence,
        failure: HeistFailureDetail,
        abortedAtChildPath: String,
        children: [HeistExecutionStepResult]
    ) {
        self.evidence = evidence
        self.failure = failure
        self.abortedAtChildPath = abortedAtChildPath
        self.children = children
    }
}

public struct HeistExecutionStepSkippedOutcome: Sendable, Equatable {
    public let children: [HeistExecutionStepResult]

    fileprivate init(children: [HeistExecutionStepResult]) {
        self.children = children
    }
}
