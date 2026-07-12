import Foundation

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
            try Self.validateIntent(intent, matches: kind, codingPath: [])
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
        let path = try container.decode(String.self, forKey: .path)
        let kind = try container.decode(HeistExecutionStepKind.self, forKey: .kind)
        let durationMs = try container.decode(Int.self, forKey: .durationMs)
        let intent = try container.decodeIfPresent(HeistStepIntent.self, forKey: .intent)
        let outcome = try container.decode(HeistExecutionStepOutcome.self, forKey: .outcome)
        try Self.validateIntent(intent, matches: kind, codingPath: container.codingPath + [CodingKeys.intent])
        try Self.validateOutcome(kind: kind, outcome: outcome, codingPath: container.codingPath + [CodingKeys.outcome])
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

    private static func validateOutcome(
        kind: HeistExecutionStepKind,
        outcome: HeistExecutionStepOutcome,
        codingPath: [CodingKey]
    ) throws {
        switch outcome {
        case .passed(let passed):
            try validateEvidence(passed.evidence, matches: kind, codingPath: codingPath)
            try validatePassedEvidence(passed.evidence, kind: kind, codingPath: codingPath)
            if let failedChildPath = firstFailedPath(in: passed.children) {
                throw receiptError(
                    "passed heist execution step must not contain failed child \(failedChildPath)",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.children]
                )
            }
        case .failed(let failed):
            try validateEvidence(failed.evidence, matches: kind, codingPath: codingPath)
            try validateChildAbortPath(
                nil,
                failedChildPath: firstFailedPath(in: failed.children),
                codingPath: codingPath
            )
        case .childAborted(let aborted):
            try validateEvidence(aborted.evidence, matches: kind, codingPath: codingPath)
            try validateChildAbortPath(
                aborted.abortedAtChildPath,
                failedChildPath: firstFailedPath(in: aborted.children),
                codingPath: codingPath
            )
        case .skipped(let skipped):
            guard skipped.children.allSatisfy({ $0.status == .skipped }) else {
                throw receiptError(
                    "skipped heist execution step children must also be skipped",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.children]
                )
            }
        }
    }

    private static func firstFailedPath(in children: [HeistExecutionStepResult]) -> String? {
        children.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
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

    private static func validateIntent(
        _ intent: HeistStepIntent?,
        matches kind: HeistExecutionStepKind,
        codingPath: [CodingKey]
    ) throws {
        guard let intent else { return }
        let isCompatible: Bool
        switch (kind, intent) {
        case (.action, .action), (.wait, .wait), (.conditional, .conditional),
             (.forEachElement, .forEachElement), (.forEachString, .forEachString),
             (.forEachIteration, .forEachElement), (.forEachIteration, .forEachString),
             (.repeatUntil, .repeatUntil), (.repeatUntilIteration, .repeatUntil),
             (.warn, .warn), (.fail, .fail), (.heist, .heist), (.invoke, .invoke):
            isCompatible = true
        default:
            isCompatible = false
        }
        guard isCompatible else {
            throw receiptError(
                "\(kind.rawValue) heist execution step cannot include mismatched intent",
                codingPath: codingPath
            )
        }
    }

    private static func validatePassedEvidence(
        _ evidence: HeistStepEvidence?,
        kind: HeistExecutionStepKind,
        codingPath: [CodingKey]
    ) throws {
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
        if evidence.expectationResult?.outcome.isSuccess == false || evidence.checkedExpectation?.met == false {
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
            try Self.rejectFields(except: [.type, .evidence, .children], in: container, type: .passed)
            self = .passed(HeistExecutionStepPassedOutcome(
                evidence: try container.decodeIfPresent(HeistStepEvidence.self, forKey: .evidence),
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .failed:
            try Self.rejectFields(except: [.type, .evidence, .failure, .children], in: container, type: .failed)
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
            try Self.rejectFields(
                except: [.type, .evidence, .failure, .abortedAtChildPath, .children],
                in: container,
                type: .childAborted
            )
            self = .childAborted(HeistExecutionStepChildAbortedOutcome(
                evidence: try container.decode(HeistStepEvidence.self, forKey: .evidence),
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                abortedAtChildPath: try container.decode(String.self, forKey: .abortedAtChildPath),
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        case .skipped:
            try Self.rejectFields(except: [.type, .children], in: container, type: .skipped)
            self = .skipped(HeistExecutionStepSkippedOutcome(
                children: try container.decode([HeistExecutionStepResult].self, forKey: .children)
            ))
        }
    }

    private static func rejectFields(
        except allowed: Set<CodingKeys>,
        in container: KeyedDecodingContainer<CodingKeys>,
        type: OutcomeType
    ) throws {
        for key in CodingKeys.allCases where !allowed.contains(key) && container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(type.rawValue) heist execution step outcome cannot include \(key.stringValue)"
            )
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

package extension HeistExecutionStepResult {
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
