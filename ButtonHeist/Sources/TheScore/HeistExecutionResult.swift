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

    public init(
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

    public init(
        path: String,
        kind: HeistExecutionStepKind,
        status: HeistExecutionStepStatus,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        abortedAtChildPath: String? = nil,
        children: [HeistExecutionStepResult] = []
    ) {
        self.path = path
        self.kind = kind
        self.durationMs = durationMs
        self.intent = intent
        let failedChildPath = children.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
        do {
            outcome = try Self.validatedOutcome(
                kind: kind,
                status: status,
                evidence: evidence,
                failure: failure ?? (status == .failed ? Self.inferredFailure(
                    kind: kind,
                    intent: intent,
                    evidence: evidence,
                    failedChildPath: failedChildPath
                ) : nil),
                abortedAtChildPath: abortedAtChildPath ?? failedChildPath,
                children: children,
                codingPath: []
            )
        } catch {
            preconditionFailure("Invalid heist execution step result at \(path): \(error)")
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case kind
        case status
        case durationMs
        case intent
        case evidence
        case failure
        case abortedAtChildPath
        case children
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution step result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        kind = try container.decode(HeistExecutionStepKind.self, forKey: .kind)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        intent = try container.decodeIfPresent(HeistStepIntent.self, forKey: .intent)
        outcome = try Self.validatedOutcome(
            kind: kind,
            status: try container.decode(HeistExecutionStepStatus.self, forKey: .status),
            evidence: try container.decodeIfPresent(HeistStepEvidence.self, forKey: .evidence),
            failure: try container.decodeIfPresent(HeistFailureDetail.self, forKey: .failure),
            abortedAtChildPath: try container.decodeIfPresent(String.self, forKey: .abortedAtChildPath),
            children: try container.decode([HeistExecutionStepResult].self, forKey: .children),
            codingPath: container.codingPath
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(kind, forKey: .kind)
        try container.encode(status, forKey: .status)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encodeIfPresent(evidence, forKey: .evidence)
        try container.encodeIfPresent(failure, forKey: .failure)
        try container.encodeIfPresent(abortedAtChildPath, forKey: .abortedAtChildPath)
        try container.encode(children, forKey: .children)
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
                    codingPath: codingPath + [CodingKeys.failure]
                )
            }
            guard failedChildPath == nil else {
                throw receiptError(
                    "passed heist execution step must not contain failed child \(failedChildPath ?? "")",
                    codingPath: codingPath + [CodingKeys.children]
                )
            }
            return .passed(HeistExecutionStepPassedOutcome(evidence: evidence, children: children))
        case .failed:
            guard let failure else {
                throw receiptError(
                    "failed heist execution step must include failure",
                    codingPath: codingPath + [CodingKeys.failure]
                )
            }
            return .failed(HeistExecutionStepFailedOutcome(
                evidence: evidence,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            ))
        case .skipped:
            guard evidence == nil else {
                throw receiptError(
                    "skipped heist execution step must not include evidence",
                    codingPath: codingPath + [CodingKeys.evidence]
                )
            }
            guard failure == nil else {
                throw receiptError(
                    "skipped heist execution step must not include failure",
                    codingPath: codingPath + [CodingKeys.failure]
                )
            }
            guard children.allSatisfy({ $0.status == .skipped }) else {
                throw receiptError(
                    "skipped heist execution step children must also be skipped",
                    codingPath: codingPath + [CodingKeys.children]
                )
            }
            return .skipped(HeistExecutionStepSkippedOutcome(children: children))
        }
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
                codingPath: codingPath + [CodingKeys.evidence]
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
            guard evidence.actionResult.success && evidence.expectation.met else {
                throw receiptError(
                    "passed matched wait step must include successful wait evidence",
                    codingPath: codingPath + [CodingKeys.evidence]
                )
            }
        case .handledElse:
            return
        case .continued, .failed:
            throw receiptError(
                "passed wait step must include matched or handled_else evidence outcome",
                codingPath: codingPath + [CodingKeys.evidence]
            )
        }
    }

    private static func validatePassedActionEvidence(
        _ evidence: HeistActionEvidence,
        codingPath: [CodingKey]
    ) throws {
        if evidence.actionResult?.success == false {
            throw receiptError(
                "passed action heist execution step must not include failed action evidence",
                codingPath: codingPath + [CodingKeys.evidence]
            )
        }
        if evidence.expectationActionResult?.success == false || evidence.expectation?.met == false {
            throw receiptError(
                "passed action heist execution step must not include failed expectation evidence",
                codingPath: codingPath + [CodingKeys.evidence]
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
                    codingPath: codingPath + [CodingKeys.evidence]
                )
            }
        case .continued:
            guard allowsContinued, !evidence.expectation.met, evidence.failureReason == nil else {
                throw receiptError(
                    "continued repeat_until evidence is only valid for passed non-terminal iterations",
                    codingPath: codingPath + [CodingKeys.evidence]
                )
            }
        case .handledElse:
            return
        case .failed:
            throw receiptError(
                "passed repeat_until step must not include failed evidence outcome",
                codingPath: codingPath + [CodingKeys.evidence]
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
                codingPath: codingPath + [CodingKeys.evidence]
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
                codingPath: codingPath + [CodingKeys.abortedAtChildPath]
            )
        case (.some(let abortedAtChildPath), .none):
            throw receiptError(
                "abortedAtChildPath \(abortedAtChildPath) has no failed child",
                codingPath: codingPath + [CodingKeys.abortedAtChildPath]
            )
        case (.some(let abortedAtChildPath), .some(let failedChildPath)):
            guard abortedAtChildPath == failedChildPath else {
                throw receiptError(
                    "abortedAtChildPath \(abortedAtChildPath) must match first failed child \(failedChildPath)",
                    codingPath: codingPath + [CodingKeys.abortedAtChildPath]
                )
            }
        }
    }

    private static func receiptError(_ message: String, codingPath: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
    }

    private static func inferredFailure(
        kind: HeistExecutionStepKind,
        intent: HeistStepIntent?,
        evidence: HeistStepEvidence?,
        failedChildPath: String?
    ) -> HeistFailureDetail? {
        if let failedChildPath {
            return HeistFailureDetail(
                category: inferredChildFailureCategory(for: kind),
                contract: "child execution completes without failure",
                observed: "child failed at \(failedChildPath)",
                expected: "all executed child steps pass"
            )
        }
        switch evidence {
        case .action(let evidence):
            return inferredActionFailure(evidence)
        case .wait(let evidence):
            return inferredWaitFailure(evidence)
        case .forEachString(let evidence):
            return inferredLoopFailure(evidence.failureReason, contract: "for_each_string completes all values")
        case .forEachElement(let evidence):
            return inferredLoopFailure(
                evidence.failureReason,
                contract: "for_each_element completes all matched iterations"
            )
        case .repeatUntil(let evidence):
            return inferredRepeatUntilFailure(evidence)
        case .invocation(let evidence):
            return evidence.childFailedPath.map {
                HeistFailureDetail(
                    category: .invocation,
                    contract: "child execution completes without failure",
                    observed: "child failed at \($0)",
                    expected: "all executed child steps pass"
                )
            }
        case .caseSelection, .warning, .none:
            break
        }
        if case .fail(let message) = intent {
            return HeistFailureDetail(
                category: .explicitFailure,
                contract: "explicit heist failure",
                observed: message
            )
        }
        return HeistFailureDetail(
            category: .validation,
            contract: "\(kind.rawValue) step completes without failure",
            observed: "heist step failed"
        )
    }

    private static func inferredChildFailureCategory(for kind: HeistExecutionStepKind) -> HeistFailureCategory {
        switch kind {
        case .wait:
            return .wait
        case .forEachElement, .forEachString, .forEachIteration, .repeatUntil, .repeatUntilIteration:
            return .loop
        case .action:
            return .action
        case .conditional, .heist, .invoke:
            return .invocation
        case .warn, .fail:
            return .validation
        }
    }

    private static func inferredActionFailure(_ evidence: HeistActionEvidence) -> HeistFailureDetail? {
        if let result = evidence.actionResult, !result.success {
            return HeistFailureDetail(
                category: result.errorKind == .elementNotFound ? .targetResolution : .action,
                contract: "action dispatch succeeds",
                observed: result.message ?? "action failed",
                expected: evidence.command?.reportTarget.map(String.init(describing:))
            )
        }
        if let expectation = evidence.expectation, !expectation.met {
            return HeistFailureDetail(
                category: .expectation,
                contract: "action expectation is met",
                observed: expectation.actual ?? "expectation not met",
                expected: expectation.predicate?.description
            )
        }
        if let result = evidence.expectationActionResult, !result.success {
            return HeistFailureDetail(
                category: .expectation,
                contract: "action expectation wait succeeds",
                observed: result.message ?? "expectation wait failed",
                expected: evidence.expectation?.predicate?.description
            )
        }
        return nil
    }

    private static func inferredWaitFailure(_ evidence: HeistWaitEvidence) -> HeistFailureDetail? {
        if !evidence.expectation.met {
            return HeistFailureDetail(
                category: .wait,
                contract: "wait predicate is met before timeout",
                observed: evidence.expectation.actual ?? evidence.actionResult.message ?? "expectation not met",
                expected: evidence.expectation.predicate?.description
            )
        }
        guard !evidence.actionResult.success else { return nil }
        return HeistFailureDetail(
            category: .wait,
            contract: "wait action succeeds",
            observed: evidence.actionResult.message ?? "wait failed",
            expected: evidence.expectation.predicate?.description
        )
    }

    private static func inferredLoopFailure(_ reason: String?, contract: String) -> HeistFailureDetail? {
        reason.map {
            HeistFailureDetail(
                category: .loop,
                contract: contract,
                observed: $0
            )
        }
    }

    private static func inferredRepeatUntilFailure(_ evidence: HeistRepeatUntilEvidence) -> HeistFailureDetail? {
        let observed = evidence.failureReason
            ?? (!evidence.expectation.met ? evidence.expectation.actual : nil)
            ?? evidence.actionResult?.message
        return observed.map {
            HeistFailureDetail(
                category: .loop,
                contract: "repeat_until predicate is met before timeout",
                observed: $0,
                expected: evidence.predicate.description
            )
        }
    }
}

public enum HeistExecutionStepOutcome: Sendable, Equatable {
    case passed(HeistExecutionStepPassedOutcome)
    case failed(HeistExecutionStepFailedOutcome)
    case skipped(HeistExecutionStepSkippedOutcome)

    public var status: HeistExecutionStepStatus {
        switch self {
        case .passed:
            return .passed
        case .failed:
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
        }
    }

    public var abortedAtChildPath: String? {
        switch self {
        case .passed, .skipped:
            return nil
        case .failed(let outcome):
            return outcome.abortedAtChildPath
        }
    }

    public var children: [HeistExecutionStepResult] {
        switch self {
        case .passed(let outcome):
            return outcome.children
        case .failed(let outcome):
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
    public let abortedAtChildPath: String?
    public let children: [HeistExecutionStepResult]

    fileprivate init(
        evidence: HeistStepEvidence?,
        failure: HeistFailureDetail,
        abortedAtChildPath: String?,
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
    case action(command: String, target: String?)
    case wait(predicate: String, timeout: Double)
    case conditional
    case forEachString(parameter: HeistReferenceName, count: Int)
    case forEachElement(parameter: HeistReferenceName, matching: String, limit: Int)
    case repeatUntil(predicate: String, timeout: Double)
    case invoke(path: String, argument: String?)
    case heist(name: String?)
    case warn(message: String)
    case fail(message: String)
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
    public let command: HeistActionCommand?
    public let actionResult: ActionResult?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?

    public init(
        command: HeistActionCommand?,
        actionResult: ActionResult?,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.command = command
        self.actionResult = actionResult
        self.expectationActionResult = expectationActionResult
        self.expectation = expectation
    }
}

public struct HeistWaitEvidence: Codable, Sendable, Equatable {
    public let outcome: HeistPredicateEvidenceOutcome
    public let actionResult: ActionResult
    public let expectation: ExpectationResult
    public let baselineSummary: String?
    public let finalSummary: String?
    public let warning: HeistPredicateWarning?

    public init(
        outcome: HeistPredicateEvidenceOutcome,
        actionResult: ActionResult,
        expectation: ExpectationResult,
        baselineSummary: String? = nil,
        finalSummary: String? = nil,
        warning: HeistPredicateWarning? = nil
    ) {
        self.outcome = outcome
        self.actionResult = actionResult
        self.expectation = expectation
        self.baselineSummary = baselineSummary
        self.finalSummary = finalSummary
        self.warning = warning
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
    public let iterationOrdinal: Int?
    public let value: String?
    public let failureReason: String?

    public init(
        parameter: HeistReferenceName,
        count: Int,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        value: String? = nil,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.count = count
        self.iterationCount = iterationCount
        self.iterationOrdinal = iterationOrdinal
        self.value = value
        self.failureReason = failureReason
    }
}

public struct HeistForEachElementEvidence: Codable, Sendable, Equatable {
    public let parameter: HeistReferenceName
    public let matching: ElementPredicate
    public let limit: Int
    public let matchedCount: Int
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let targetOrdinal: Int?
    public let targetSummary: String?
    public let failureReason: String?

    public init(
        parameter: HeistReferenceName,
        matching: ElementPredicate,
        limit: Int,
        matchedCount: Int,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        targetOrdinal: Int? = nil,
        targetSummary: String? = nil,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.matching = matching
        self.limit = limit
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.iterationOrdinal = iterationOrdinal
        self.targetOrdinal = targetOrdinal
        self.targetSummary = targetSummary
        self.failureReason = failureReason
    }
}

public struct HeistRepeatUntilEvidence: Codable, Sendable, Equatable {
    public let outcome: HeistPredicateEvidenceOutcome
    public let predicate: AccessibilityPredicate
    public let timeout: Double
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let expectation: ExpectationResult
    public let actionResult: ActionResult?
    public let lastObservedSummary: String?
    public let failureReason: String?

    public init(
        outcome: HeistPredicateEvidenceOutcome,
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil,
        failureReason: String? = nil
    ) {
        self.outcome = outcome
        self.predicate = predicate
        self.timeout = timeout
        self.iterationCount = iterationCount
        self.iterationOrdinal = iterationOrdinal
        self.expectation = expectation
        self.actionResult = actionResult
        self.lastObservedSummary = lastObservedSummary
        self.failureReason = failureReason
    }
}

public struct HeistInvocationEvidence: Codable, Sendable, Equatable {
    public let invocation: HeistInvocationStep?
    public let name: String?
    public let argument: String?
    public let childFailedPath: String?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?
    public let expectationEvidence: HeistWaitEvidence?

    public init(
        invocation: HeistInvocationStep? = nil,
        name: String? = nil,
        argument: String? = nil,
        childFailedPath: String? = nil,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        expectationEvidence: HeistWaitEvidence? = nil
    ) {
        self.invocation = invocation
        self.name = name
        self.argument = argument
        self.childFailedPath = childFailedPath
        self.expectationActionResult = expectationActionResult
        self.expectation = expectation
        self.expectationEvidence = expectationEvidence
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

    public init(
        category: HeistFailureCategory,
        contract: String,
        observed: String,
        expected: String? = nil
    ) {
        self.category = category
        self.contract = contract
        self.observed = observed
        self.expected = expected
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
            let index = try container.decode(Int.self, forKey: .index)
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
        self.cases = cases
        self.outcome = Self.normalized(outcome: outcome, cases: cases)
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

        self.init(
            cases: cases,
            outcome: try container.decode(HeistCaseSelectionOutcome.self, forKey: .outcome),
            elapsedMs: try container.decode(Int.self, forKey: .elapsedMs),
            timeout: try container.decodeIfPresent(Double.self, forKey: .timeout),
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

    private static func normalized(
        outcome: HeistCaseSelectionOutcome,
        cases: [HeistCaseMatchResult]
    ) -> HeistCaseSelectionOutcome {
        switch outcome {
        case .matchedCase(let index):
            return cases.indices.contains(index) ? .matchedCase(index: index) : .noMatch
        case .elseBranch, .timedOut, .noMatch:
            return outcome
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
        self.predicate = predicate
        self.result = result
    }
}
