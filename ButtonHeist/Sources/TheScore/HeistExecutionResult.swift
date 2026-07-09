import Foundation
import ThePlans

// MARK: - Heist Execution Receipt

/// Durable receipt for executing a `HeistPlan`.
public struct HeistExecutionResult: Codable, Sendable, Equatable {
    public let outcome: HeistExecutionOutcome
    public let durationMs: Int

    public var steps: [HeistExecutionStepResult] {
        outcome.steps
    }

    public var abortedAtPath: String? {
        outcome.abortedAtPath
    }

    public static func passed(
        steps: [HeistExecutionStepResult],
        durationMs: Int
    ) -> HeistExecutionResult {
        do {
            return HeistExecutionResult(
                outcome: try Self.validatedOutcome(
                    steps: steps,
                    abortedAtPath: nil,
                    codingPath: []
                ),
                durationMs: durationMs
            )
        } catch {
            preconditionFailure("Invalid passed heist execution result: \(error)")
        }
    }

    public static func failed(
        steps: [HeistExecutionStepResult],
        durationMs: Int,
        abortedAtPath: String
    ) -> HeistExecutionResult {
        do {
            return HeistExecutionResult(
                outcome: try Self.validatedOutcome(
                    steps: steps,
                    abortedAtPath: abortedAtPath,
                    codingPath: []
                ),
                durationMs: durationMs
            )
        } catch {
            preconditionFailure("Invalid failed heist execution result: \(error)")
        }
    }

    package init(
        steps: [HeistExecutionStepResult],
        durationMs: Int,
        abortedAtPath: String? = nil
    ) {
        self.durationMs = durationMs
        let failedPath = steps.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
        do {
            outcome = try Self.validatedOutcome(
                steps: steps,
                abortedAtPath: abortedAtPath ?? failedPath,
                codingPath: []
            )
        } catch {
            preconditionFailure("Invalid heist execution result: \(error)")
        }
    }

    private init(
        outcome: HeistExecutionOutcome,
        durationMs: Int
    ) {
        self.outcome = outcome
        self.durationMs = durationMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case steps
        case durationMs
        case abortedAtPath
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let steps = try container.decode([HeistExecutionStepResult].self, forKey: .steps)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        outcome = try Self.validatedOutcome(
            steps: steps,
            abortedAtPath: try container.decodeIfPresent(String.self, forKey: .abortedAtPath),
            codingPath: container.codingPath
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(abortedAtPath, forKey: .abortedAtPath)
    }

    private static func validatedOutcome(
        steps: [HeistExecutionStepResult],
        abortedAtPath: String?,
        codingPath: [CodingKey]
    ) throws -> HeistExecutionOutcome {
        let failedPath = steps.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
        switch (abortedAtPath, failedPath) {
        case (.none, .none):
            return .passed(HeistExecutionPassedOutcome(steps: steps))
        case (.none, .some(let failedPath)):
            throw Self.receiptError(
                "failed heist execution result must include abortedAtPath for \(failedPath)",
                codingPath: codingPath + [CodingKeys.abortedAtPath]
            )
        case (.some(let abortedAtPath), .none):
            throw Self.receiptError(
                "passed heist execution result must not include abortedAtPath \(abortedAtPath)",
                codingPath: codingPath + [CodingKeys.abortedAtPath]
            )
        case (.some(let abortedAtPath), .some(let failedPath)):
            guard abortedAtPath == failedPath else {
                throw Self.receiptError(
                    "heist execution abortedAtPath \(abortedAtPath) must match first failed step \(failedPath)",
                    codingPath: codingPath + [CodingKeys.abortedAtPath]
                )
            }
            return .failed(HeistExecutionFailedOutcome(steps: steps, abortedAtPath: abortedAtPath))
        }
    }

    private static func receiptError(_ message: String, codingPath: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
    }
}

public enum HeistExecutionOutcome: Sendable, Equatable {
    case passed(HeistExecutionPassedOutcome)
    case failed(HeistExecutionFailedOutcome)

    public var steps: [HeistExecutionStepResult] {
        switch self {
        case .passed(let outcome):
            return outcome.steps
        case .failed(let outcome):
            return outcome.steps
        }
    }

    public var abortedAtPath: String? {
        switch self {
        case .passed:
            return nil
        case .failed(let outcome):
            return outcome.abortedAtPath
        }
    }
}

public struct HeistExecutionPassedOutcome: Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]

    fileprivate init(steps: [HeistExecutionStepResult]) {
        self.steps = steps
    }
}

public struct HeistExecutionFailedOutcome: Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]
    public let abortedAtPath: String

    fileprivate init(
        steps: [HeistExecutionStepResult],
        abortedAtPath: String
    ) {
        self.steps = steps
        self.abortedAtPath = abortedAtPath
    }
}

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

public struct HeistStepReceiptKind<Evidence>: Sendable {
    public let stepKind: HeistExecutionStepKind
    fileprivate let wrapEvidence: @Sendable (Evidence) -> HeistStepEvidence

    fileprivate init(
        stepKind: HeistExecutionStepKind,
        wrapEvidence: @escaping @Sendable (Evidence) -> HeistStepEvidence
    ) {
        self.stepKind = stepKind
        self.wrapEvidence = wrapEvidence
    }
}

public extension HeistStepReceiptKind where Evidence == HeistActionEvidence {
    static var action: Self {
        Self(stepKind: .action, wrapEvidence: HeistStepEvidence.action)
    }
}

public extension HeistStepReceiptKind where Evidence == HeistWaitEvidence {
    static var wait: Self {
        Self(stepKind: .wait, wrapEvidence: HeistStepEvidence.wait)
    }
}

public extension HeistStepReceiptKind where Evidence == HeistCaseSelectionEvidence {
    static var conditional: Self {
        Self(stepKind: .conditional, wrapEvidence: HeistStepEvidence.caseSelection)
    }
}

public extension HeistStepReceiptKind where Evidence == HeistForEachElementEvidence {
    static var forEachElement: Self {
        Self(stepKind: .forEachElement, wrapEvidence: HeistStepEvidence.forEachElement)
    }

    static var forEachElementIteration: Self {
        Self(stepKind: .forEachIteration, wrapEvidence: HeistStepEvidence.forEachElement)
    }
}

public extension HeistStepReceiptKind where Evidence == HeistForEachStringEvidence {
    static var forEachString: Self {
        Self(stepKind: .forEachString, wrapEvidence: HeistStepEvidence.forEachString)
    }

    static var forEachStringIteration: Self {
        Self(stepKind: .forEachIteration, wrapEvidence: HeistStepEvidence.forEachString)
    }
}

public extension HeistStepReceiptKind where Evidence == HeistRepeatUntilEvidence {
    static var repeatUntil: Self {
        Self(stepKind: .repeatUntil, wrapEvidence: HeistStepEvidence.repeatUntil)
    }

    static var repeatUntilIteration: Self {
        Self(stepKind: .repeatUntilIteration, wrapEvidence: HeistStepEvidence.repeatUntil)
    }
}

public extension HeistStepReceiptKind where Evidence == HeistInvocationEvidence {
    static var heist: Self {
        Self(stepKind: .heist, wrapEvidence: HeistStepEvidence.invocation)
    }

    static var invocation: Self {
        Self(stepKind: .invoke, wrapEvidence: HeistStepEvidence.invocation)
    }
}

public extension HeistStepReceiptKind where Evidence == HeistExecutionWarning {
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

    public static func passed(
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

    public static func passed<Evidence>(
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

    public static func failed(
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

    public static func failed<Evidence>(
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

    public static func childAborted<Evidence>(
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

    public static func childAborted<Evidence>(
        path: String,
        receiptKind: HeistStepReceiptKind<Evidence>,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: Evidence,
        failure: HeistFailureDetail,
        child: HeistExecutionStepResult,
        remainingChildren: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        childAborted(
            path: path,
            receiptKind: receiptKind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            abortedAtChildPath: child.path,
            children: [child] + remainingChildren
        )
    }

    package init(
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
            try Self.validateOutcome(kind: kind, outcome: outcome, codingPath: [])
        } catch {
            preconditionFailure("Invalid heist execution step result at \(path): \(error)")
        }
    }

    public static func skipped(
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
        path = try container.decode(String.self, forKey: .path)
        kind = try container.decode(HeistExecutionStepKind.self, forKey: .kind)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        intent = try container.decodeIfPresent(HeistStepIntent.self, forKey: .intent)
        outcome = try container.decode(HeistExecutionStepOutcome.self, forKey: .outcome)
        try Self.validateOutcome(kind: kind, outcome: outcome, codingPath: container.codingPath + [CodingKeys.outcome])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(kind, forKey: .kind)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encode(outcome, forKey: .outcome)
    }

    private static func validatedOutcome(
        kind: HeistExecutionStepKind,
        status: HeistExecutionStepStatus,
        evidence: HeistStepEvidence?,
        failure: HeistFailureDetail?,
        abortedAtChildPath: String?,
        children: [HeistExecutionStepResult],
        codingPath: [CodingKey]
    ) throws -> HeistExecutionStepOutcome {
        try validateEvidence(evidence, matches: kind, codingPath: codingPath)
        try validateEvidence(evidence, matches: status, kind: kind, codingPath: codingPath)
        let failedChildPath = children.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
        try validateChildAbortPath(
            abortedAtChildPath,
            failedChildPath: failedChildPath,
            codingPath: codingPath
        )

        switch status {
        case .passed:
            guard failure == nil else {
                throw receiptError(
                    "passed heist execution step must not include failure",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.failure]
                )
            }
            guard failedChildPath == nil else {
                throw receiptError(
                    "passed heist execution step must not contain failed child \(failedChildPath ?? "")",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.children]
                )
            }
            return .passed(HeistExecutionStepPassedOutcome(evidence: evidence, children: children))
        case .failed:
            guard let failure else {
                throw receiptError(
                    "failed heist execution step must include failure",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.failure]
                )
            }
            if let abortedAtChildPath {
                guard let evidence else {
                    throw receiptError(
                        "child-aborted heist execution step must include evidence",
                        codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
                    )
                }
                return .childAborted(HeistExecutionStepChildAbortedOutcome(
                    evidence: evidence,
                    failure: failure,
                    abortedAtChildPath: abortedAtChildPath,
                    children: children
                ))
            }
            return .failed(HeistExecutionStepFailedOutcome(
                evidence: evidence,
                failure: failure,
                children: children
            ))
        case .skipped:
            guard evidence == nil else {
                throw receiptError(
                    "skipped heist execution step must not include evidence",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
                )
            }
            guard failure == nil else {
                throw receiptError(
                    "skipped heist execution step must not include failure",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.failure]
                )
            }
            guard children.allSatisfy({ $0.status == .skipped }) else {
                throw receiptError(
                    "skipped heist execution step children must also be skipped",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.children]
                )
            }
            return .skipped(HeistExecutionStepSkippedOutcome(children: children))
        }
    }

    private static func validateOutcome(
        kind: HeistExecutionStepKind,
        outcome: HeistExecutionStepOutcome,
        codingPath: [CodingKey]
    ) throws {
        _ = try validatedOutcome(
            kind: kind,
            status: outcome.status,
            evidence: outcome.evidence,
            failure: outcome.failure,
            abortedAtChildPath: outcome.abortedAtChildPath,
            children: outcome.children,
            codingPath: codingPath
        )
    }

    private static func validateEvidence(
        _ evidence: HeistStepEvidence?,
        matches kind: HeistExecutionStepKind,
        codingPath: [CodingKey]
    ) throws {
        guard let evidence else { return }
        let isCompatible: Bool
        switch (kind, evidence) {
        case (.action, .action),
             (.wait, .wait),
             (.conditional, .caseSelection),
             (.forEachElement, .forEachElement),
             (.forEachString, .forEachString),
             (.forEachIteration, .forEachElement),
             (.forEachIteration, .forEachString),
             (.repeatUntil, .repeatUntil),
             (.repeatUntilIteration, .repeatUntil),
             (.warn, .warning),
             (.heist, .invocation),
             (.invoke, .invocation):
            isCompatible = true
        case (.fail, _),
             (.action, _),
             (.wait, _),
             (.conditional, _),
             (.forEachElement, _),
             (.forEachString, _),
             (.forEachIteration, _),
             (.repeatUntil, _),
             (.repeatUntilIteration, _),
             (.warn, _),
             (.heist, _),
             (.invoke, _):
            isCompatible = false
        }
        guard isCompatible else {
            throw receiptError(
                "\(kind.rawValue) heist execution step cannot include \(evidence.receiptKindDescription) evidence",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
            )
        }
    }

    private static func validateEvidence(
        _ evidence: HeistStepEvidence?,
        matches status: HeistExecutionStepStatus,
        kind: HeistExecutionStepKind,
        codingPath: [CodingKey]
    ) throws {
        guard status == .passed else { return }
        switch (kind, evidence) {
        case (.action, .action(let evidence)):
            try validatePassedActionEvidence(evidence, codingPath: codingPath)
        case (.wait, .wait(let evidence)):
            try validatePassedWaitEvidence(evidence, codingPath: codingPath)
        case (.forEachElement, .forEachElement(let evidence)),
             (.forEachIteration, .forEachElement(let evidence)):
            try validatePassedLoopEvidence(evidence.failureReason, codingPath: codingPath)
        case (.forEachString, .forEachString(let evidence)),
             (.forEachIteration, .forEachString(let evidence)):
            try validatePassedLoopEvidence(evidence.failureReason, codingPath: codingPath)
        case (.repeatUntil, .repeatUntil(let evidence)):
            try validatePassedRepeatUntilEvidence(evidence, allowsContinued: false, codingPath: codingPath)
        case (.repeatUntilIteration, .repeatUntil(let evidence)):
            try validatePassedRepeatUntilEvidence(evidence, allowsContinued: true, codingPath: codingPath)
        case (.action, _),
             (.wait, _),
             (.conditional, _),
             (.forEachElement, _),
             (.forEachString, _),
             (.forEachIteration, _),
             (.repeatUntil, _),
             (.repeatUntilIteration, _),
             (.warn, _),
             (.fail, _),
             (.heist, _),
             (.invoke, _):
            return
        }
    }

    private static func validatePassedWaitEvidence(
        _ evidence: HeistWaitEvidence,
        codingPath: [CodingKey]
    ) throws {
        switch evidence.outcome {
        case .matched:
            guard evidence.actionResult.outcome.isSuccess && evidence.expectation.met else {
                throw receiptError(
                    "passed matched wait step must include successful wait evidence",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
                )
            }
        case .handledElse:
            return
        case .continued, .failed:
            throw receiptError(
                "passed wait step must include matched or handled_else evidence outcome",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
            )
        }
    }

    private static func validatePassedActionEvidence(
        _ evidence: HeistActionEvidence,
        codingPath: [CodingKey]
    ) throws {
        if evidence.dispatchResult?.outcome.isSuccess == false {
            throw receiptError(
                "passed action heist execution step must not include failed action evidence",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
            )
        }
        if evidence.expectationResult?.outcome.isSuccess == false || evidence.expectation?.met == false {
            throw receiptError(
                "passed action heist execution step must not include failed expectation evidence",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
            )
        }
    }

    private static func validatePassedRepeatUntilEvidence(
        _ evidence: HeistRepeatUntilEvidence,
        allowsContinued: Bool,
        codingPath: [CodingKey]
    ) throws {
        switch evidence.outcome {
        case .matched:
            guard evidence.expectation.met, evidence.failureReason == nil else {
                throw receiptError(
                    "passed matched repeat_until step must include met predicate evidence",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
                )
            }
        case .continued:
            guard allowsContinued, !evidence.expectation.met, evidence.failureReason == nil else {
                throw receiptError(
                    "continued repeat_until evidence is only valid for passed non-terminal iterations",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
                )
            }
        case .handledElse:
            return
        case .failed:
            throw receiptError(
                "passed repeat_until step must not include failed evidence outcome",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
            )
        }
    }

    private static func validatePassedLoopEvidence(
        _ failureReason: String?,
        codingPath: [CodingKey]
    ) throws {
        guard failureReason == nil else {
            throw receiptError(
                "passed loop heist execution step must not include failure reason evidence",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
            )
        }
    }

    private static func validateChildAbortPath(
        _ abortedAtChildPath: String?,
        failedChildPath: String?,
        codingPath: [CodingKey]
    ) throws {
        switch (abortedAtChildPath, failedChildPath) {
        case (.none, .none):
            return
        case (.none, .some(let failedChildPath)):
            throw receiptError(
                "failed child \(failedChildPath) requires abortedAtChildPath",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.abortedAtChildPath]
            )
        case (.some(let abortedAtChildPath), .none):
            throw receiptError(
                "abortedAtChildPath \(abortedAtChildPath) has no failed child",
                codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.abortedAtChildPath]
            )
        case (.some(let abortedAtChildPath), .some(let failedChildPath)):
            guard abortedAtChildPath == failedChildPath else {
                throw receiptError(
                    "abortedAtChildPath \(abortedAtChildPath) must match first failed child \(failedChildPath)",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.abortedAtChildPath]
                )
            }
        }
    }

    private static func receiptError(_ message: String, codingPath: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
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
            self = .passed(HeistExecutionStepPassedOutcome(
                evidence: try container.decodeIfPresent(HeistStepEvidence.self, forKey: .evidence),
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .failed:
            self = .failed(HeistExecutionStepFailedOutcome(
                evidence: try container.decodeIfPresent(HeistStepEvidence.self, forKey: .evidence),
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .childAborted:
            self = .childAborted(HeistExecutionStepChildAbortedOutcome(
                evidence: try container.decode(HeistStepEvidence.self, forKey: .evidence),
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                abortedAtChildPath: try container.decode(String.self, forKey: .abortedAtChildPath),
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .skipped:
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

private extension HeistExecutionStepResult {
    var firstFailedStepPathForReceiptValidation: String? {
        children.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
            ?? (status == .failed ? path : nil)
    }
}

private extension HeistStepEvidence {
    var receiptKindDescription: String {
        switch self {
        case .action:
            return "action"
        case .wait:
            return "wait"
        case .caseSelection:
            return "caseSelection"
        case .forEachString:
            return "forEachString"
        case .forEachElement:
            return "forEachElement"
        case .repeatUntil:
            return "repeatUntil"
        case .invocation:
            return "invocation"
        case .warning:
            return "warning"
        }
    }
}

public enum HeistStepIntent: Codable, Sendable, Equatable {
    case action(command: HeistActionCommand)
    case wait(predicate: AccessibilityPredicateExpr, timeout: Double)
    case conditional
    case forEachString(parameter: HeistReferenceName, count: Int)
    case forEachElement(parameter: HeistReferenceName, matching: ElementPredicate, limit: Int)
    case repeatUntil(predicate: AccessibilityPredicateExpr, timeout: Double)
    case invoke(path: HeistInvocationPath, argument: HeistArgument)
    case heist(name: String?)
    case warn(message: String)
    case fail(message: String)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case command
        case predicate
        case timeout
        case parameter
        case count
        case matching
        case limit
        case path
        case argument
        case name
        case message
    }

    private enum IntentType: String, Codable {
        case action
        case wait
        case conditional
        case forEachString = "for_each_string"
        case forEachElement = "for_each_element"
        case repeatUntil = "repeat_until"
        case invoke
        case heist
        case warn
        case fail
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist step intent")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IntentType.self, forKey: .type)
        switch type {
        case .action:
            try Self.rejectFields(except: [.type, .command], in: container, type: type)
            self = .action(command: try container.decode(HeistActionCommand.self, forKey: .command))
        case .wait:
            try Self.rejectFields(except: [.type, .predicate, .timeout], in: container, type: type)
            self = .wait(
                predicate: try container.decode(AccessibilityPredicateExpr.self, forKey: .predicate),
                timeout: try container.decode(Double.self, forKey: .timeout)
            )
        case .conditional:
            try Self.rejectFields(except: [.type], in: container, type: type)
            self = .conditional
        case .forEachString:
            try Self.rejectFields(except: [.type, .parameter, .count], in: container, type: type)
            self = .forEachString(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                count: try container.decode(Int.self, forKey: .count)
            )
        case .forEachElement:
            try Self.rejectFields(except: [.type, .parameter, .matching, .limit], in: container, type: type)
            self = .forEachElement(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                matching: try container.decode(ElementPredicate.self, forKey: .matching),
                limit: try container.decode(Int.self, forKey: .limit)
            )
        case .repeatUntil:
            try Self.rejectFields(except: [.type, .predicate, .timeout], in: container, type: type)
            self = .repeatUntil(
                predicate: try container.decode(AccessibilityPredicateExpr.self, forKey: .predicate),
                timeout: try container.decode(Double.self, forKey: .timeout)
            )
        case .invoke:
            try Self.rejectFields(except: [.type, .path, .argument], in: container, type: type)
            let components = try container.decode([String].self, forKey: .path)
            do {
                self = .invoke(
                    path: try HeistInvocationPath(components: components),
                    argument: try container.decode(HeistArgument.self, forKey: .argument)
                )
            } catch let error as HeistInvocationPath.ValidationError {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: error.description
                )
            }
        case .heist:
            try Self.rejectFields(except: [.type, .name], in: container, type: type)
            self = .heist(name: try container.decodeIfPresent(String.self, forKey: .name))
        case .warn:
            try Self.rejectFields(except: [.type, .message], in: container, type: type)
            self = .warn(message: try container.decode(String.self, forKey: .message))
        case .fail:
            try Self.rejectFields(except: [.type, .message], in: container, type: type)
            self = .fail(message: try container.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let command):
            try container.encode(IntentType.action, forKey: .type)
            try container.encode(command, forKey: .command)
        case .wait(let predicate, let timeout):
            try container.encode(IntentType.wait, forKey: .type)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(timeout, forKey: .timeout)
        case .conditional:
            try container.encode(IntentType.conditional, forKey: .type)
        case .forEachString(let parameter, let count):
            try container.encode(IntentType.forEachString, forKey: .type)
            try container.encode(parameter, forKey: .parameter)
            try container.encode(count, forKey: .count)
        case .forEachElement(let parameter, let matching, let limit):
            try container.encode(IntentType.forEachElement, forKey: .type)
            try container.encode(parameter, forKey: .parameter)
            try container.encode(matching, forKey: .matching)
            try container.encode(limit, forKey: .limit)
        case .repeatUntil(let predicate, let timeout):
            try container.encode(IntentType.repeatUntil, forKey: .type)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(timeout, forKey: .timeout)
        case .invoke(let path, let argument):
            try container.encode(IntentType.invoke, forKey: .type)
            try container.encode(path.components, forKey: .path)
            try container.encode(argument, forKey: .argument)
        case .heist(let name):
            try container.encode(IntentType.heist, forKey: .type)
            try container.encodeIfPresent(name, forKey: .name)
        case .warn(let message):
            try container.encode(IntentType.warn, forKey: .type)
            try container.encode(message, forKey: .message)
        case .fail(let message):
            try container.encode(IntentType.fail, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }

    private static func rejectFields(
        except allowed: Set<CodingKeys>,
        in container: KeyedDecodingContainer<CodingKeys>,
        type: IntentType
    ) throws {
        for key in CodingKeys.allCases where !allowed.contains(key) && container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(type.rawValue) heist step intent must not include \(key.stringValue)"
            )
        }
    }
}

public enum HeistStepEvidence: Codable, Sendable, Equatable {
    case action(HeistActionEvidence)
    case wait(HeistWaitEvidence)
    case caseSelection(HeistCaseSelectionEvidence)
    case forEachString(HeistForEachStringEvidence)
    case forEachElement(HeistForEachElementEvidence)
    case repeatUntil(HeistRepeatUntilEvidence)
    case invocation(HeistInvocationEvidence)
    case warning(HeistExecutionWarning)
}

public enum HeistPredicateEvidenceOutcome: String, Codable, Sendable, Equatable {
    case matched
    case continued
    case handledElse = "handled_else"
    case failed
}

public struct HeistActionEvidence: Codable, Sendable, Equatable {
    private let storage: Storage

    public struct DispatchResultEvidence: Sendable, Equatable {
        public let dispatchResult: ActionResult
    }

    public struct ExpectationResultEvidence: Sendable, Equatable {
        public let dispatchResult: ActionResult
        public let expectationResult: ActionResult
        public let expectation: ExpectationResult
    }

    public enum ResultEvidence: Sendable, Equatable {
        case commandResolutionFailure
        case dispatch(DispatchResultEvidence)
        case expectation(ExpectationResultEvidence)
    }

    public var resultEvidence: ResultEvidence {
        switch storage {
        case .commandResolutionFailure:
            return .commandResolutionFailure
        case .dispatch(let dispatch):
            return .dispatch(DispatchResultEvidence(dispatchResult: dispatch.dispatchResult))
        case .expectation(_, let dispatchResult, let expectationResult, let expectation, _):
            return .expectation(ExpectationResultEvidence(
                dispatchResult: dispatchResult,
                expectationResult: expectationResult,
                expectation: expectation
            ))
        }
    }

    public var dispatchResult: ActionResult? {
        switch resultEvidence {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let evidence):
            return evidence.dispatchResult
        case .expectation(let evidence):
            return evidence.dispatchResult
        }
    }

    public var reportedResult: ActionResult? {
        switch resultEvidence {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let evidence):
            return evidence.dispatchResult
        case .expectation(let evidence):
            return evidence.expectationResult
        }
    }

    public var traceResult: ActionResult? {
        reportedResult
    }

    public var expectationResult: ActionResult? {
        guard case .expectation(let evidence) = resultEvidence else { return nil }
        return evidence.expectationResult
    }

    public var command: HeistActionCommand? {
        switch storage {
        case .commandResolutionFailure(let command):
            return command
        case .dispatch(let dispatch):
            return dispatch.command
        case .expectation(let command, _, _, _, _):
            return command
        }
    }

    public var expectation: ExpectationResult? {
        guard case .expectation(let evidence) = resultEvidence else { return nil }
        return evidence.expectation
    }

    public var warning: HeistActionWarning? {
        switch storage {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let dispatch):
            return dispatch.warning
        case .expectation(_, _, _, _, let warning):
            return warning
        }
    }

    public static func commandResolutionFailure(
        command: HeistActionCommand
    ) -> HeistActionEvidence {
        HeistActionEvidence(storage: .commandResolutionFailure(command: command))
    }

    public static func dispatch(
        command: HeistActionCommand,
        dispatchResult: ActionResult,
        warning: HeistActionWarning? = nil
    ) -> HeistActionEvidence {
        return HeistActionEvidence(storage: .dispatch(.command(
            command: command,
            dispatchResult: dispatchResult,
            warning: warning
        )))
    }

    public static func dispatch(
        dispatchResult: ActionResult
    ) -> HeistActionEvidence {
        HeistActionEvidence(storage: .dispatch(.commandless(dispatchResult: dispatchResult)))
    }

    public static func expectation(
        command: HeistActionCommand,
        dispatchResult: ActionResult,
        expectationResult: ActionResult,
        expectation: ExpectationResult,
        warning: HeistActionWarning? = nil
    ) -> HeistActionEvidence {
        HeistActionEvidence(storage: .expectation(
            command: command,
            dispatchResult: dispatchResult,
            expectationResult: expectationResult,
            expectation: expectation,
            warning: warning
        ))
    }

    private init(storage: Storage) {
        self.storage = storage
    }

    private enum Storage: Sendable, Equatable {
        case commandResolutionFailure(command: HeistActionCommand)
        case dispatch(Dispatch)
        case expectation(
            command: HeistActionCommand,
            dispatchResult: ActionResult,
            expectationResult: ActionResult,
            expectation: ExpectationResult,
            warning: HeistActionWarning?
        )
    }

    private enum Dispatch: Sendable, Equatable {
        case command(command: HeistActionCommand, dispatchResult: ActionResult, warning: HeistActionWarning?)
        case commandless(dispatchResult: ActionResult)

        var command: HeistActionCommand? {
            switch self {
            case .command(let command, _, _):
                return command
            case .commandless:
                return nil
            }
        }

        var dispatchResult: ActionResult {
            switch self {
            case .command(_, let dispatchResult, _),
                 .commandless(let dispatchResult):
                return dispatchResult
            }
        }

        var warning: HeistActionWarning? {
            switch self {
            case .command(_, _, let warning):
                return warning
            case .commandless:
                return nil
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case command
        case dispatchResult
        case expectationResult
        case expectation
        case warning
    }

    private enum EvidenceType: String, Codable {
        case commandResolutionFailure = "command_resolution_failure"
        case dispatch
        case commandlessDispatch = "commandless_dispatch"
        case expectation
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EvidenceType.self, forKey: .type) {
        case .commandResolutionFailure:
            self = .commandResolutionFailure(
                command: try container.decode(HeistActionCommand.self, forKey: .command)
            )
            try Self.rejectFields(
                except: [.type, .command],
                in: container,
                typeName: EvidenceType.commandResolutionFailure.rawValue
            )
        case .dispatch:
            self = .dispatch(
                command: try container.decode(HeistActionCommand.self, forKey: .command),
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult),
                warning: try container.decodeIfPresent(HeistActionWarning.self, forKey: .warning)
            )
            try Self.rejectFields(
                except: [.type, .command, .dispatchResult, .warning],
                in: container,
                typeName: EvidenceType.dispatch.rawValue
            )
        case .commandlessDispatch:
            self = .dispatch(
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult)
            )
            try Self.rejectFields(
                except: [.type, .dispatchResult],
                in: container,
                typeName: EvidenceType.commandlessDispatch.rawValue
            )
        case .expectation:
            self = .expectation(
                command: try container.decode(HeistActionCommand.self, forKey: .command),
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult),
                expectationResult: try container.decode(ActionResult.self, forKey: .expectationResult),
                expectation: try container.decode(ExpectationResult.self, forKey: .expectation),
                warning: try container.decodeIfPresent(HeistActionWarning.self, forKey: .warning)
            )
            try Self.rejectFields(
                except: [.type, .command, .dispatchResult, .expectationResult, .expectation, .warning],
                in: container,
                typeName: EvidenceType.expectation.rawValue
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch storage {
        case .commandResolutionFailure(let command):
            try container.encode(EvidenceType.commandResolutionFailure, forKey: .type)
            try container.encode(command, forKey: .command)
        case .dispatch(.command(let command, let dispatchResult, let warning)):
            try container.encode(EvidenceType.dispatch, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(dispatchResult, forKey: .dispatchResult)
            try container.encodeIfPresent(warning, forKey: .warning)
        case .dispatch(.commandless(let dispatchResult)):
            try container.encode(EvidenceType.commandlessDispatch, forKey: .type)
            try container.encode(dispatchResult, forKey: .dispatchResult)
        case .expectation(let command, let dispatchResult, let expectationResult, let expectation, let warning):
            try container.encode(EvidenceType.expectation, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(dispatchResult, forKey: .dispatchResult)
            try container.encode(expectationResult, forKey: .expectationResult)
            try container.encode(expectation, forKey: .expectation)
            try container.encodeIfPresent(warning, forKey: .warning)
        }
    }

    private static func rejectFields(
        except allowed: Set<CodingKeys>,
        in container: KeyedDecodingContainer<CodingKeys>,
        typeName: String
    ) throws {
        for key in CodingKeys.allCases where !allowed.contains(key) && container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(typeName) heist action evidence cannot include \(key.stringValue)"
            )
        }
    }
}

public struct HeistActionWarning: Codable, Sendable, Equatable {
    public static let activationWeakAffordanceEvidenceCode = "activation_weak_affordance_evidence"

    public let code: String
    public let message: String
    public let evidence: String?

    public init(
        code: String,
        message: String,
        evidence: String? = nil
    ) {
        precondition(!code.isEmpty, "HeistActionWarning code must not be empty")
        precondition(!message.isEmpty, "HeistActionWarning message must not be empty")
        self.code = code
        self.message = message
        self.evidence = evidence
    }

    public static func activationWeakAffordanceEvidence(evidence: String?) -> HeistActionWarning {
        HeistActionWarning(
            code: activationWeakAffordanceEvidenceCode,
            message: "activate succeeded, but the target does not advertise a primary activation affordance",
            evidence: evidence
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case message
        case evidence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action warning")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let message = try container.decode(String.self, forKey: .message)
        guard !code.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: container,
                debugDescription: "heist action warning code must not be empty"
            )
        }
        guard !message.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: container,
                debugDescription: "heist action warning message must not be empty"
            )
        }
        self.init(
            code: code,
            message: message,
            evidence: try container.decodeIfPresent(String.self, forKey: .evidence)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(evidence, forKey: .evidence)
    }
}

public struct HeistWaitEvidence: Codable, Sendable, Equatable {
    private let storage: Storage
    public let baselineSummary: String?
    public let finalSummary: String?
    public let warning: HeistPredicateWarning?

    public struct MatchedCheck: Sendable, Equatable {
        public let actionResult: ActionResult
        public let expectation: MetExpectationResult

        public init?(
            actionResult: ActionResult,
            expectation: MetExpectationResult
        ) {
            guard actionResult.outcome.isSuccess else { return nil }
            self.actionResult = actionResult
            self.expectation = expectation
        }
    }

    public struct UnmatchedCheck: Sendable, Equatable {
        public let actionResult: ActionResult
        public let expectation: PredicateExpectationCheck

        public init?(
            actionResult: ActionResult,
            expectation: PredicateExpectationCheck
        ) {
            guard !actionResult.outcome.isSuccess || !expectation.result.met else { return nil }
            self.actionResult = actionResult
            self.expectation = expectation
        }

        public init?(
            actionResult: ActionResult,
            expectation: ExpectationResult
        ) {
            self.init(
                actionResult: actionResult,
                expectation: PredicateExpectationCheck(expectation)
            )
        }
    }

    private enum Storage: Sendable, Equatable {
        case matched(MatchedCheck)
        case handledElse(UnmatchedCheck)
        case failed(UnmatchedCheck)
    }

    public var outcome: HeistPredicateEvidenceOutcome {
        switch storage {
        case .matched:
            return .matched
        case .handledElse:
            return .handledElse
        case .failed:
            return .failed
        }
    }

    public var actionResult: ActionResult {
        switch storage {
        case .matched(let check):
            return check.actionResult
        case .handledElse(let check),
             .failed(let check):
            return check.actionResult
        }
    }

    public var expectation: ExpectationResult {
        switch storage {
        case .matched(let check):
            return check.expectation.result
        case .handledElse(let check),
             .failed(let check):
            return check.expectation.result
        }
    }

    public static func matched(
        _ check: MatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .matched(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary,
            warning: warning
        )
    }

    public static func handledElse(
        _ check: UnmatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .handledElse(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary,
            warning: warning
        )
    }

    public static func failed(
        _ check: UnmatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .failed(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary,
            warning: warning
        )
    }

    private init(
        storage: Storage,
        baselineSummary: String?,
        finalSummary: String?,
        warning: HeistPredicateWarning?
    ) {
        self.storage = storage
        self.baselineSummary = baselineSummary
        self.finalSummary = finalSummary
        self.warning = warning
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case actionResult
        case expectation
        case baselineSummary
        case finalSummary
        case warning
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(HeistPredicateEvidenceOutcome.self, forKey: .outcome)
        let actionResult = try container.decode(ActionResult.self, forKey: .actionResult)
        let expectation = try container.decode(ExpectationResult.self, forKey: .expectation)
        storage = try Self.storage(
            outcome: outcome,
            actionResult: actionResult,
            expectation: expectation,
            codingPath: container.codingPath
        )
        baselineSummary = try container.decodeIfPresent(String.self, forKey: .baselineSummary)
        finalSummary = try container.decodeIfPresent(String.self, forKey: .finalSummary)
        warning = try container.decodeIfPresent(HeistPredicateWarning.self, forKey: .warning)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(actionResult, forKey: .actionResult)
        try container.encode(expectation, forKey: .expectation)
        try container.encodeIfPresent(baselineSummary, forKey: .baselineSummary)
        try container.encodeIfPresent(finalSummary, forKey: .finalSummary)
        try container.encodeIfPresent(warning, forKey: .warning)
    }

    private static func storage(
        outcome: HeistPredicateEvidenceOutcome,
        actionResult: ActionResult,
        expectation: ExpectationResult,
        codingPath: [CodingKey]
    ) throws -> Storage {
        let expectation = PredicateExpectationCheck(expectation)
        switch outcome {
        case .matched:
            guard case .met(let expectation) = expectation,
                  let check = MatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "matched wait evidence requires a successful action result and met expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .matched(check)
        case .handledElse:
            guard let check = UnmatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "handled_else wait evidence requires a failed action result or unmet expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .handledElse(check)
        case .failed:
            guard let check = UnmatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "failed wait evidence requires a failed action result or unmet expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .failed(check)
        case .continued:
            throw evidenceError(
                "continued outcome is only valid for repeat_until evidence",
                codingPath: codingPath + [CodingKeys.outcome]
            )
        }
    }

    private static func evidenceError(_ message: String, codingPath: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
    }
}

public struct HeistPredicateWarning: Codable, Sendable, Equatable {
    public let code: String
    public let predicate: String
    public let impliedPredicate: String?
    public let finalStateTiming: String?
    public let evidence: String?
    public let message: String

    public init(
        code: String,
        predicate: String,
        impliedPredicate: String? = nil,
        finalStateTiming: String? = nil,
        evidence: String? = nil,
        message: String
    ) {
        self.code = code
        self.predicate = predicate
        self.impliedPredicate = impliedPredicate
        self.finalStateTiming = finalStateTiming
        self.evidence = evidence
        self.message = message
    }
}

public struct HeistCaseSelectionEvidence: Codable, Sendable, Equatable {
    public let selection: HeistCaseSelectionResult

    public init(selection: HeistCaseSelectionResult) {
        self.selection = selection
    }
}

public struct HeistForEachStringEvidence: Codable, Sendable, Equatable {
    public let parameter: HeistReferenceName
    public let count: Int
    public let iterationCount: Int
    private let shape: Shape

    public var iterationOrdinal: Int? {
        guard case .iteration(let iterationOrdinal, _, _) = shape else {
            return nil
        }
        return iterationOrdinal
    }

    public var value: String? {
        guard case .iteration(_, let value, _) = shape else {
            return nil
        }
        return value
    }

    public var failureReason: String? {
        switch shape {
        case .summary(let failureReason), .iteration(_, _, let failureReason):
            return failureReason
        }
    }

    public init(
        parameter: HeistReferenceName,
        count: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.count = count
        self.iterationCount = iterationCount
        self.shape = .summary(failureReason: failureReason)
    }

    public init(
        parameter: HeistReferenceName,
        count: Int,
        iterationCount: Int,
        iterationOrdinal: Int,
        value: String,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.count = count
        self.iterationCount = iterationCount
        self.shape = .iteration(
            iterationOrdinal: iterationOrdinal,
            value: value,
            failureReason: failureReason
        )
    }

    private enum Shape: Sendable, Equatable {
        case summary(failureReason: String?)
        case iteration(iterationOrdinal: Int, value: String, failureReason: String?)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case parameter
        case count
        case iterationCount
        case iterationOrdinal
        case value
        case failureReason
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "HeistForEachStringEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let iterationOrdinal = try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal)
        let value = try container.decodeIfPresent(String.self, forKey: .value)
        let failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)

        switch (iterationOrdinal, value) {
        case (.some(let iterationOrdinal), .some(let value)):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                count: try container.decode(Int.self, forKey: .count),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                iterationOrdinal: iterationOrdinal,
                value: value,
                failureReason: failureReason
            )
        case (nil, nil):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                count: try container.decode(Int.self, forKey: .count),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                failureReason: failureReason
            )
        case (.some, nil), (nil, .some):
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "for_each_string iteration evidence requires iterationOrdinal and value together"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameter, forKey: .parameter)
        try container.encode(count, forKey: .count)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}

public struct HeistForEachElementEvidence: Codable, Sendable, Equatable {
    public let parameter: HeistReferenceName
    public let matching: ElementPredicate
    public let limit: Int
    public let matchedCount: Int
    public let iterationCount: Int
    private let shape: Shape

    public var iterationOrdinal: Int? {
        guard case .iteration(let iterationOrdinal, _, _, _) = shape else {
            return nil
        }
        return iterationOrdinal
    }

    public var targetOrdinal: Int? {
        guard case .iteration(_, let targetOrdinal, _, _) = shape else {
            return nil
        }
        return targetOrdinal
    }

    public var targetSummary: String? {
        guard case .iteration(_, _, let targetSummary, _) = shape else {
            return nil
        }
        return targetSummary
    }

    public var failureReason: String? {
        switch shape {
        case .summary(let failureReason), .iteration(_, _, _, let failureReason):
            return failureReason
        }
    }

    public init(
        parameter: HeistReferenceName,
        matching: ElementPredicate,
        limit: Int,
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.matching = matching
        self.limit = limit
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.shape = .summary(failureReason: failureReason)
    }

    public init(
        parameter: HeistReferenceName,
        matching: ElementPredicate,
        limit: Int,
        matchedCount: Int,
        iterationCount: Int,
        iterationOrdinal: Int,
        targetOrdinal: Int,
        targetSummary: String,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.matching = matching
        self.limit = limit
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.shape = .iteration(
            iterationOrdinal: iterationOrdinal,
            targetOrdinal: targetOrdinal,
            targetSummary: targetSummary,
            failureReason: failureReason
        )
    }

    private enum Shape: Sendable, Equatable {
        case summary(failureReason: String?)
        case iteration(
            iterationOrdinal: Int,
            targetOrdinal: Int,
            targetSummary: String,
            failureReason: String?
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case parameter
        case matching
        case limit
        case matchedCount
        case iterationCount
        case iterationOrdinal
        case targetOrdinal
        case targetSummary
        case failureReason
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "HeistForEachElementEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let iterationOrdinal = try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal)
        let targetOrdinal = try container.decodeIfPresent(Int.self, forKey: .targetOrdinal)
        let targetSummary = try container.decodeIfPresent(String.self, forKey: .targetSummary)
        let failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)

        switch (iterationOrdinal, targetOrdinal, targetSummary) {
        case (.some(let iterationOrdinal), .some(let targetOrdinal), .some(let targetSummary)):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                matching: try container.decode(ElementPredicate.self, forKey: .matching),
                limit: try container.decode(Int.self, forKey: .limit),
                matchedCount: try container.decode(Int.self, forKey: .matchedCount),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                iterationOrdinal: iterationOrdinal,
                targetOrdinal: targetOrdinal,
                targetSummary: targetSummary,
                failureReason: failureReason
            )
        case (nil, nil, nil):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                matching: try container.decode(ElementPredicate.self, forKey: .matching),
                limit: try container.decode(Int.self, forKey: .limit),
                matchedCount: try container.decode(Int.self, forKey: .matchedCount),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                failureReason: failureReason
            )
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "for_each_element iteration evidence requires iterationOrdinal, targetOrdinal, and targetSummary together"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameter, forKey: .parameter)
        try container.encode(matching, forKey: .matching)
        try container.encode(limit, forKey: .limit)
        try container.encode(matchedCount, forKey: .matchedCount)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(targetOrdinal, forKey: .targetOrdinal)
        try container.encodeIfPresent(targetSummary, forKey: .targetSummary)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}

public struct HeistRepeatUntilEvidence: Codable, Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let timeout: Double
    public let iterationCount: Int
    public let lastObservedSummary: String?
    private let storage: Storage

    private enum Storage: Sendable, Equatable {
        case matched(
            iterationOrdinal: Int?,
            expectation: MetExpectationResult,
            actionResult: ActionResult?
        )
        case continued(
            iterationOrdinal: Int,
            expectation: UnmetExpectationResult,
            actionResult: ActionResult?
        )
        case handledElse(
            expectation: UnmetExpectationResult,
            failureReason: String?
        )
        case failed(
            iterationOrdinal: Int?,
            expectation: UnmetExpectationResult,
            failureReason: String
        )
    }

    public var outcome: HeistPredicateEvidenceOutcome {
        switch storage {
        case .matched:
            return .matched
        case .continued:
            return .continued
        case .handledElse:
            return .handledElse
        case .failed:
            return .failed
        }
    }

    public var iterationOrdinal: Int? {
        switch storage {
        case .matched(let iterationOrdinal, _, _),
             .failed(let iterationOrdinal, _, _):
            return iterationOrdinal
        case .continued(let iterationOrdinal, _, _):
            return iterationOrdinal
        case .handledElse:
            return nil
        }
    }

    public var expectation: ExpectationResult {
        switch storage {
        case .matched(_, let expectation, _):
            return expectation.result
        case .continued(_, let expectation, _),
             .handledElse(let expectation, _),
             .failed(_, let expectation, _):
            return expectation.result
        }
    }

    public var actionResult: ActionResult? {
        switch storage {
        case .matched(_, _, let actionResult),
             .continued(_, _, let actionResult):
            return actionResult
        case .handledElse, .failed:
            return nil
        }
    }

    public var failureReason: String? {
        switch storage {
        case .handledElse(_, let failureReason):
            return failureReason
        case .failed(_, _, let failureReason):
            return failureReason
        case .matched, .continued:
            return nil
        }
    }

    private init(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int = 0,
        lastObservedSummary: String?,
        storage: Storage
    ) {
        self.predicate = predicate
        self.timeout = timeout
        self.iterationCount = iterationCount
        self.lastObservedSummary = lastObservedSummary
        self.storage = storage
    }

    public static func predicateMet(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: MetExpectationResult,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .matched(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        )
    }

    public static func continued(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int,
        expectation: UnmetExpectationResult,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .continued(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        )
    }

    public static func timedOut(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        expectation: UnmetExpectationResult,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .failed(
                iterationOrdinal: nil,
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    public static func bodyFailed(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        expectation: UnmetExpectationResult,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .failed(
                iterationOrdinal: nil,
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    public static func initialObservationUnavailable(
        predicate: AccessibilityPredicate,
        timeout: Double,
        expectation: UnmetExpectationResult,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: 0,
            lastObservedSummary: lastObservedSummary,
            storage: .failed(
                iterationOrdinal: nil,
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    public static func failedIteration(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int,
        expectation: UnmetExpectationResult,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .failed(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    public static func timeoutHandledByElse(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        expectation: UnmetExpectationResult,
        lastObservedSummary: String?,
        failureReason: String? = nil
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .handledElse(
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    public static func timeoutElseFailed(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        expectation: UnmetExpectationResult,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        return HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .failed(
                iterationOrdinal: nil,
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case predicate
        case timeout
        case iterationCount
        case iterationOrdinal
        case expectation
        case actionResult
        case lastObservedSummary
        case failureReason
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "repeat_until evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(HeistPredicateEvidenceOutcome.self, forKey: .outcome)
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let timeout = try container.decode(Double.self, forKey: .timeout)
        let iterationCount = try container.decode(Int.self, forKey: .iterationCount)
        let iterationOrdinal = try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal)
        let expectation = try container.decode(ExpectationResult.self, forKey: .expectation)
        let actionResult = try container.decodeIfPresent(ActionResult.self, forKey: .actionResult)
        let lastObservedSummary = try container.decodeIfPresent(String.self, forKey: .lastObservedSummary)
        let failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        let storage = try Self.storage(
            outcome: outcome,
            iterationOrdinal: iterationOrdinal,
            expectation: expectation,
            actionResult: actionResult,
            failureReason: failureReason,
            codingPath: container.codingPath
        )
        self.init(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: storage
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(timeout, forKey: .timeout)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encode(expectation, forKey: .expectation)
        try container.encodeIfPresent(actionResult, forKey: .actionResult)
        try container.encodeIfPresent(lastObservedSummary, forKey: .lastObservedSummary)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }

    private static func storage(
        outcome: HeistPredicateEvidenceOutcome,
        iterationOrdinal: Int?,
        expectation: ExpectationResult,
        actionResult: ActionResult?,
        failureReason: String?,
        codingPath: [CodingKey]
    ) throws -> Storage {
        switch (outcome, PredicateExpectationCheck(expectation)) {
        case (.matched, .met(let expectation)) where failureReason == nil:
            return .matched(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        case (.continued, .unmet(let expectation)) where failureReason == nil:
            guard let iterationOrdinal else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath + [CodingKeys.iterationOrdinal],
                    debugDescription: "continued repeat_until evidence requires iterationOrdinal"
                ))
            }
            return .continued(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        case (.handledElse, .unmet(let expectation)) where iterationOrdinal == nil && actionResult == nil:
            return .handledElse(expectation: expectation, failureReason: failureReason)
        case (.failed, .unmet(let expectation)) where actionResult == nil:
            guard let failureReason else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath + [CodingKeys.failureReason],
                    debugDescription: "failed repeat_until evidence requires failureReason"
                ))
            }
            return .failed(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                failureReason: failureReason
            )
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath + [CodingKeys.outcome],
                debugDescription: "repeat_until evidence outcome does not match its required fields"
            ))
        }
    }
}

public struct HeistInvocationEvidence: Codable, Sendable, Equatable {
    private let storage: Storage

    public struct InvocationExpectationEvidence: Sendable, Equatable {
        public let actionResult: ActionResult
        public let expectation: ExpectationResult
        public let waitEvidence: HeistWaitEvidence?

        public init(
            actionResult: ActionResult,
            expectation: ExpectationResult,
            waitEvidence: HeistWaitEvidence? = nil
        ) {
            if let waitEvidence {
                precondition(
                    waitEvidence.actionResult == actionResult && waitEvidence.expectation == expectation,
                    "Invocation expectation evidence must match its summarized action result and expectation"
                )
            }
            self.actionResult = actionResult
            self.expectation = expectation
            self.waitEvidence = waitEvidence
        }
    }

    private enum Storage: Sendable, Equatable {
        case heist(name: String?, childFailedPath: String?)
        case invocation(
            invocation: HeistInvocationStep,
            name: String?,
            argument: String?,
            childFailedPath: String?,
            expectation: InvocationExpectationEvidence?
        )
    }

    public static func heist(
        name: String?,
        childFailedPath: String? = nil
    ) -> HeistInvocationEvidence {
        HeistInvocationEvidence(storage: .heist(name: name, childFailedPath: childFailedPath))
    }

    public static func invocation(
        _ invocation: HeistInvocationStep,
        name: String?,
        argument: String? = nil,
        childFailedPath: String? = nil,
        expectation: InvocationExpectationEvidence? = nil
    ) -> HeistInvocationEvidence {
        precondition(
            childFailedPath == nil || expectation == nil,
            "Child-aborted invocation evidence cannot include expectation evidence"
        )
        return HeistInvocationEvidence(storage: .invocation(
            invocation: invocation,
            name: name,
            argument: argument,
            childFailedPath: childFailedPath,
            expectation: expectation
        ))
    }

    private init(storage: Storage) {
        self.storage = storage
    }

    public var invocation: HeistInvocationStep? {
        guard case .invocation(let invocation, _, _, _, _) = storage else { return nil }
        return invocation
    }

    public var name: String? {
        switch storage {
        case .heist(let name, _),
             .invocation(_, let name, _, _, _):
            return name
        }
    }

    public var argument: String? {
        guard case .invocation(_, _, let argument, _, _) = storage else { return nil }
        return argument
    }

    public var childFailedPath: String? {
        switch storage {
        case .heist(_, let childFailedPath),
             .invocation(_, _, _, let childFailedPath, _):
            return childFailedPath
        }
    }

    public var expectationActionResult: ActionResult? {
        guard case .invocation(_, _, _, _, let expectation) = storage else { return nil }
        return expectation?.actionResult
    }

    public var expectation: ExpectationResult? {
        guard case .invocation(_, _, _, _, let expectation) = storage else { return nil }
        return expectation?.expectation
    }

    public var expectationEvidence: HeistWaitEvidence? {
        guard case .invocation(_, _, _, _, let expectation) = storage else { return nil }
        return expectation?.waitEvidence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case invocation
        case name
        case argument
        case childFailedPath
        case expectationActionResult
        case expectation
        case expectationEvidence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist invocation evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let invocation = try container.decodeIfPresent(HeistInvocationStep.self, forKey: .invocation)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let argument = try container.decodeIfPresent(String.self, forKey: .argument)
        let childFailedPath = try container.decodeIfPresent(String.self, forKey: .childFailedPath)
        let expectationActionResult = try container.decodeIfPresent(ActionResult.self, forKey: .expectationActionResult)
        let expectation = try container.decodeIfPresent(ExpectationResult.self, forKey: .expectation)
        let expectationEvidence = try container.decodeIfPresent(HeistWaitEvidence.self, forKey: .expectationEvidence)

        if let invocation {
            if childFailedPath != nil,
               expectationActionResult != nil || expectation != nil || expectationEvidence != nil {
                throw Self.decodingError(
                    "child-aborted invocation evidence must not include expectation evidence",
                    key: .childFailedPath,
                    container: container
                )
            }
            let expectationSummary = try Self.decodeExpectationEvidence(
                actionResult: expectationActionResult,
                expectation: expectation,
                waitEvidence: expectationEvidence,
                container: container
            )
            storage = .invocation(
                invocation: invocation,
                name: name,
                argument: argument,
                childFailedPath: childFailedPath,
                expectation: expectationSummary
            )
        } else {
            guard argument == nil,
                  childFailedPath == nil || expectationActionResult == nil && expectation == nil && expectationEvidence == nil,
                  expectationActionResult == nil,
                  expectation == nil,
                  expectationEvidence == nil
            else {
                throw Self.decodingError(
                    "inline heist invocation evidence must not include invoke-only fields",
                    key: .invocation,
                    container: container
                )
            }
            storage = .heist(name: name, childFailedPath: childFailedPath)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(invocation, forKey: .invocation)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(argument, forKey: .argument)
        try container.encodeIfPresent(childFailedPath, forKey: .childFailedPath)
        try container.encodeIfPresent(expectationActionResult, forKey: .expectationActionResult)
        try container.encodeIfPresent(expectation, forKey: .expectation)
        try container.encodeIfPresent(expectationEvidence, forKey: .expectationEvidence)
    }

    private static func decodeExpectationEvidence(
        actionResult: ActionResult?,
        expectation: ExpectationResult?,
        waitEvidence: HeistWaitEvidence?,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> InvocationExpectationEvidence? {
        switch (actionResult, expectation, waitEvidence) {
        case (.none, .none, .none):
            return nil
        case (.some(let actionResult), .some(let expectation), .none):
            return InvocationExpectationEvidence(actionResult: actionResult, expectation: expectation)
        case (.some(let actionResult), .some(let expectation), .some(let waitEvidence)):
            guard waitEvidence.actionResult == actionResult && waitEvidence.expectation == expectation else {
                throw decodingError(
                    "invocation expectation evidence must match expectationActionResult and expectation",
                    key: .expectationEvidence,
                    container: container
                )
            }
            return InvocationExpectationEvidence(
                actionResult: actionResult,
                expectation: expectation,
                waitEvidence: waitEvidence
            )
        case (.none, _, .some), (_, .none, .some), (.some, .none, .none), (.none, .some, .none):
            throw decodingError(
                "invocation expectation evidence requires expectationActionResult and expectation",
                key: .expectationEvidence,
                container: container
            )
        }
    }

    private static func decodingError(
        _ message: String,
        key: CodingKeys,
        container: KeyedDecodingContainer<CodingKeys>
    ) -> DecodingError {
        DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: message)
    }
}

/// One warning emitted by a `Warn(...)` heist step.
public struct HeistExecutionWarning: Codable, Sendable, Equatable {
    public let path: String
    public let message: String

    public init(
        path: String,
        message: String
    ) {
        self.path = path
        self.message = message
    }
}

public struct HeistFailureDetail: Codable, Sendable, Equatable {
    public let category: HeistFailureCategory
    public let contract: String
    public let observed: String
    public let expected: String?
    public let activationTrace: ActivationTrace?

    public init(
        category: HeistFailureCategory,
        contract: String,
        observed: String,
        expected: String? = nil
    ) {
        self.init(
            category: category,
            contract: contract,
            observed: observed,
            expected: expected,
            activationTrace: nil
        )
    }

    public init(
        category: HeistFailureCategory,
        contract: String,
        observed: String,
        expected: String? = nil,
        activationTrace: ActivationTrace?
    ) {
        self.category = category
        self.contract = contract
        self.observed = observed
        self.expected = expected
        self.activationTrace = activationTrace
    }
}

public enum HeistFailureCategory: String, Codable, Sendable, Equatable {
    case validation
    case runtimeUnavailable
    case targetResolution
    case action
    case expectation
    case wait
    case invocation
    case loop
    case explicitFailure
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
    public let predicate: AccessibilityPredicate
    public let result: ExpectationResult

    public init(
        predicate: AccessibilityPredicate,
        result: ExpectationResult
    ) {
        precondition(result.predicate == predicate, "HeistCaseMatchResult result predicate must match predicate")
        self.predicate = predicate
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
        self.predicate = predicate
        self.result = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(result, forKey: .result)
    }
}
