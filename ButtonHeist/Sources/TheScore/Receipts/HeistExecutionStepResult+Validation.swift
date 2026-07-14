import Foundation
import ThePlans

extension HeistExecutionStepResult {
    internal static func validateExternalData(
        intent: HeistStepIntent?,
        matches kind: HeistExecutionStepKind,
        outcome: HeistExecutionStepOutcome,
        intentCodingPath: [CodingKey],
        outcomeCodingPath: [CodingKey]
    ) throws {
        try validateIntent(intent, matches: kind, codingPath: intentCodingPath)
        try validateOutcome(kind: kind, outcome: outcome, codingPath: outcomeCodingPath)
    }

    private static func validateOutcome(
        kind: HeistExecutionStepKind,
        outcome: HeistExecutionStepOutcome,
        codingPath: [CodingKey]
    ) throws {
        switch (kind, outcome) {
        case (.action, .passed(let passed)):
            try validateActionEvidence(passed.evidence, receiptOutcome: .passed, codingPath: codingPath)
        case (.action, .failed(let failed)):
            try validateActionEvidence(failed.evidence, receiptOutcome: .failed, codingPath: codingPath)
        case (.action, .childAborted(let aborted)):
            try validateActionEvidence(aborted.evidence, receiptOutcome: .childAborted, codingPath: codingPath)
        case (.warn, .passed(let passed)):
            try validateEvidence(passed.evidence, matches: kind, codingPath: codingPath)
            guard case .warning? = passed.evidence else {
                throw receiptError(
                    "passed warn heist execution step requires warning evidence",
                    codingPath: evidenceCodingPath(codingPath)
                )
            }
        case (.warn, .failed), (.warn, .childAborted):
            throw receiptError(
                "warn heist execution step must use passed or skipped outcome",
                codingPath: codingPath
            )
        case (.fail, .failed(let failed)):
            try validateEvidence(failed.evidence, matches: kind, codingPath: codingPath)
        case (.fail, .passed), (.fail, .childAborted):
            throw receiptError(
                "fail heist execution step must use failed or skipped outcome",
                codingPath: codingPath
            )
        case (.wait, .passed(let passed)),
             (.conditional, .passed(let passed)),
             (.forEachElement, .passed(let passed)),
             (.forEachString, .passed(let passed)),
             (.forEachIteration, .passed(let passed)),
             (.repeatUntil, .passed(let passed)),
             (.repeatUntilIteration, .passed(let passed)),
             (.heist, .passed(let passed)),
             (.invoke, .passed(let passed)):
            try validateEvidence(passed.evidence, matches: kind, codingPath: codingPath)
            try validatePassedEvidence(passed.evidence, kind: kind, codingPath: codingPath)
        case (.wait, .failed(let failed)),
             (.conditional, .failed(let failed)),
             (.forEachElement, .failed(let failed)),
             (.forEachString, .failed(let failed)),
             (.forEachIteration, .failed(let failed)),
             (.repeatUntil, .failed(let failed)),
             (.repeatUntilIteration, .failed(let failed)),
             (.heist, .failed(let failed)),
             (.invoke, .failed(let failed)):
            try validateFailedEvidence(failed.evidence, kind: kind, codingPath: codingPath)
        case (.wait, .childAborted(let aborted)),
             (.conditional, .childAborted(let aborted)),
             (.forEachElement, .childAborted(let aborted)),
             (.forEachString, .childAborted(let aborted)),
             (.forEachIteration, .childAborted(let aborted)),
             (.repeatUntil, .childAborted(let aborted)),
             (.repeatUntilIteration, .childAborted(let aborted)),
             (.heist, .childAborted(let aborted)),
             (.invoke, .childAborted(let aborted)):
            try validateEvidence(aborted.evidence, matches: kind, codingPath: codingPath)
        case (.action, .skipped(let skipped)),
             (.wait, .skipped(let skipped)),
             (.conditional, .skipped(let skipped)),
             (.forEachElement, .skipped(let skipped)),
             (.forEachString, .skipped(let skipped)),
             (.forEachIteration, .skipped(let skipped)),
             (.repeatUntil, .skipped(let skipped)),
             (.repeatUntilIteration, .skipped(let skipped)),
             (.warn, .skipped(let skipped)),
             (.fail, .skipped(let skipped)),
             (.heist, .skipped(let skipped)),
             (.invoke, .skipped(let skipped)):
            guard skipped.children.allSatisfy({ $0.status == .skipped }) else {
                throw receiptError(
                    "skipped heist execution step children must also be skipped",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.children]
                )
            }
        }

        switch outcome {
        case .passed(let passed):
            if let failedChildPath = passed.children.firstFailedStepInReceiptOrder?.path {
                throw receiptError(
                    "passed heist execution step must not contain failed child \(failedChildPath)",
                    codingPath: codingPath + [HeistExecutionStepOutcome.CodingKeys.children]
                )
            }
        case .failed(let failed):
            try validateChildAbortPath(
                nil,
                failedChildPath: failed.children.firstFailedStepInReceiptOrder?.path,
                codingPath: codingPath
            )
        case .childAborted(let aborted):
            try validateChildAbortPath(
                aborted.abortedAtChildPath,
                failedChildPath: aborted.children.firstFailedStepInReceiptOrder?.path,
                codingPath: codingPath
            )
        case .skipped:
            break
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

    private static func validateFailedEvidence(
        _ evidence: HeistStepEvidence?,
        kind: HeistExecutionStepKind,
        codingPath: [CodingKey]
    ) throws {
        try validateEvidence(evidence, matches: kind, codingPath: codingPath)
        guard let evidence else { return }

        let failureDescription: String?
        switch (kind, evidence) {
        case (.wait, .wait(let evidence)) where evidence.outcome != .failed:
            failureDescription = "failed wait step requires failed wait evidence outcome"
        case (.forEachElement, .forEachElement(let evidence)) where evidence.failureReason == nil,
             (.forEachIteration, .forEachElement(let evidence)) where evidence.failureReason == nil:
            failureDescription = "failed loop step requires failure reason evidence"
        case (.forEachString, .forEachString(let evidence)) where evidence.failureReason == nil,
             (.forEachIteration, .forEachString(let evidence)) where evidence.failureReason == nil:
            failureDescription = "failed loop step requires failure reason evidence"
        case (.repeatUntil, .repeatUntil(let evidence)) where evidence.outcome != .failed,
             (.repeatUntilIteration, .repeatUntil(let evidence)) where evidence.outcome != .failed:
            failureDescription = "failed repeat_until step requires failed repeat_until evidence outcome"
        case (.heist, .invocation(let evidence)) where !evidence.provesInvocationFailure,
             (.invoke, .invocation(let evidence)) where !evidence.provesInvocationFailure:
            failureDescription = "failed invocation step requires child failure or unmet expectation evidence"
        default:
            failureDescription = nil
        }

        if let failureDescription {
            throw receiptError(
                failureDescription,
                codingPath: evidenceCodingPath(codingPath)
            )
        }
    }

    private enum ActionReceiptOutcome {
        case passed
        case failed
        case childAborted

        var requiresSuccessfulEvidence: Bool {
            switch self {
            case .passed, .childAborted:
                return true
            case .failed:
                return false
            }
        }

        var description: String {
            switch self {
            case .passed:
                return "passed"
            case .failed:
                return "failed"
            case .childAborted:
                return "child_aborted"
            }
        }
    }

    private static func validateActionEvidence(
        _ stepEvidence: HeistStepEvidence?,
        receiptOutcome: ActionReceiptOutcome,
        codingPath: [CodingKey]
    ) throws {
        try validateEvidence(stepEvidence, matches: .action, codingPath: codingPath)
        guard case .action(let evidence)? = stepEvidence else {
            throw receiptError(
                "\(receiptOutcome.description) action heist execution step requires action evidence",
                codingPath: evidenceCodingPath(codingPath)
            )
        }

        let evidenceSucceeded: Bool
        switch evidence {
        case .commandResolutionFailure:
            evidenceSucceeded = false
        case .dispatch(let command, let dispatchResult):
            try validate(command: command, matches: dispatchResult, codingPath: codingPath)
            evidenceSucceeded = dispatchResult.outcome.isSuccess
        case .commandlessDispatch(let dispatchResult):
            evidenceSucceeded = dispatchResult.outcome.isSuccess
        case .expectation(let command, let dispatchResult, let expectationResult, let expectation):
            try validate(command: command, matches: dispatchResult, codingPath: codingPath)
            guard dispatchResult.outcome.isSuccess else {
                throw receiptError(
                    "action expectation evidence requires successful dispatch result",
                    codingPath: evidenceCodingPath(codingPath)
                )
            }
            guard expectationResult.method == .wait else {
                throw receiptError(
                    "action expectation result method must be wait, got \(expectationResult.method.rawValue)",
                    codingPath: evidenceCodingPath(codingPath)
                )
            }
            guard expectationResult.outcome.isSuccess == expectation.met else {
                throw receiptError(
                    "action expectation result success must match expectation met=\(expectation.met)",
                    codingPath: evidenceCodingPath(codingPath)
                )
            }
            evidenceSucceeded = expectation.met
        }

        guard evidenceSucceeded == receiptOutcome.requiresSuccessfulEvidence else {
            throw receiptError(
                "\(receiptOutcome.description) action heist execution step requires "
                    + "\(receiptOutcome.requiresSuccessfulEvidence ? "successful" : "failed") action evidence",
                codingPath: evidenceCodingPath(codingPath)
            )
        }
    }

    private static func validate(
        command: HeistActionCommand,
        matches result: ActionResult,
        codingPath: [CodingKey]
    ) throws {
        guard command.actionResultMethod == result.method else {
            throw receiptError(
                "action command \(command.wireType.rawValue) requires \(command.actionResultMethod.rawValue) "
                    + "result method, got \(result.method.rawValue)",
                codingPath: evidenceCodingPath(codingPath)
            )
        }
    }

    private static func evidenceCodingPath(_ codingPath: [CodingKey]) -> [CodingKey] {
        codingPath + [HeistExecutionStepOutcome.CodingKeys.evidence]
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
