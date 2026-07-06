#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    struct HeistReceiptChildren: Equatable {
        let children: [HeistExecutionStepResult]
        let abortedAtChildPath: String?

        static let empty = HeistReceiptChildren([])

        init(_ children: [HeistExecutionStepResult]) {
            self.children = children
            abortedAtChildPath = children.firstFailedStep?.path
        }
    }

    enum HeistStepReceiptOutcome {
        case passed(evidence: HeistStepEvidence? = nil, children: HeistReceiptChildren = .empty)
        case failed(evidence: HeistStepEvidence? = nil, failure: HeistFailureDetail, children: HeistReceiptChildren = .empty)
        case childAborted(evidence: HeistStepEvidence, failure: HeistFailureDetail, abortedAtChildPath: String, children: HeistReceiptChildren)
        case skipped(children: HeistReceiptChildren = .empty)
    }

    func heistActionReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistStepReceiptOutcome
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: .action,
            durationMs: durationMs,
            intent: intent,
            outcome: outcome
        )
    }

    func heistWaitReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistStepReceiptOutcome
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: .wait,
            durationMs: durationMs,
            intent: intent,
            outcome: outcome
        )
    }

    func heistSkippedReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: kind,
            durationMs: 0,
            outcome: .skipped(children: HeistReceiptChildren(children))
        )
    }

    func heistWarningReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        warning: HeistExecutionWarning
    ) -> HeistExecutionStepResult {
        .passed(
            path: path,
            receiptKind: .warning,
            durationMs: durationMs,
            intent: intent,
            evidence: warning
        )
    }

    func heistExplicitFailureReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        failure: HeistFailureDetail
    ) -> HeistExecutionStepResult {
        .failed(
            path: path,
            kind: .fail,
            durationMs: durationMs,
            intent: intent,
            failure: failure
        )
    }

    func heistInvocationReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistStepReceiptOutcome
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: .invoke,
            durationMs: durationMs,
            intent: intent,
            outcome: outcome
        )
    }

    func heistFailedReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        failure: HeistFailureDetail
    ) -> HeistExecutionStepResult {
        failedHeistStep(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: nil,
            failure: failure,
            children: []
        )
    }

    func heistFailedReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence,
        failure: HeistFailureDetail
    ) -> HeistExecutionStepResult {
        failedHeistStep(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            children: []
        )
    }

    func heistChildParentReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistStepEvidence,
        childFailureCategory: HeistFailureCategory,
        children: HeistReceiptChildren
    ) -> HeistExecutionStepResult {
        let outcome = childAwarePassedOutcome(
            evidence: evidence,
            children: children,
            childFailure: { childPath in
                childFailureDetail(category: childFailureCategory, childPath: childPath)
            }
        )
        return heistStepReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            outcome: outcome
        )
    }

    func heistLoopReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistStepReceiptOutcome
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            outcome: outcome
        )
    }

    func childAwarePassedOutcome(
        evidence: HeistStepEvidence,
        children: HeistReceiptChildren,
        childFailure: (String) -> HeistFailureDetail
    ) -> HeistStepReceiptOutcome {
        guard let abortedAtChildPath = children.abortedAtChildPath else {
            return .passed(evidence: evidence, children: children)
        }
        return .childAborted(
            evidence: evidence,
            failure: childFailure(abortedAtChildPath),
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    func childAwareFailedOutcome(
        evidence: HeistStepEvidence,
        failure: HeistFailureDetail,
        children: HeistReceiptChildren,
        childFailure: (String) -> HeistFailureDetail
    ) -> HeistStepReceiptOutcome {
        guard let abortedAtChildPath = children.abortedAtChildPath else {
            return .failed(evidence: evidence, failure: failure, children: children)
        }
        return .childAborted(
            evidence: evidence,
            failure: childFailure(abortedAtChildPath),
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func heistStepReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        outcome: HeistStepReceiptOutcome
    ) -> HeistExecutionStepResult {
        switch outcome {
        case .passed(let evidence, let children):
            return passedHeistStep(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                children: children.children
            )
        case .failed(let evidence, let failure, let children):
            return failedHeistStep(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure,
                children: children.children
            )
        case .childAborted(let evidence, let failure, let abortedAtChildPath, let children):
            return childAbortedHeistStep(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children.children
            )
        case .skipped(let children):
            return .skipped(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                children: children.children
            )
        }
    }

    private func passedHeistStep(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent?,
        evidence: HeistStepEvidence?,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        guard let evidence else {
            return .passed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                children: children
            )
        }
        switch evidence {
        case .action(let action):
            precondition(kind == .action, "Action receipt evidence can only be used with action steps")
            return .passed(path: path, receiptKind: .action, durationMs: durationMs, intent: intent, evidence: action, children: children)
        case .wait(let wait):
            precondition(kind == .wait, "Wait receipt evidence can only be used with wait steps")
            return .passed(path: path, receiptKind: .wait, durationMs: durationMs, intent: intent, evidence: wait, children: children)
        case .caseSelection(let selection):
            precondition(kind == .conditional, "Case-selection receipt evidence can only be used with conditional steps")
            return .passed(path: path, receiptKind: .conditional, durationMs: durationMs, intent: intent, evidence: selection, children: children)
        case .forEachString(let forEachString):
            return .passed(
                path: path,
                receiptKind: forEachStringReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: forEachString,
                children: children
            )
        case .forEachElement(let forEachElement):
            return .passed(
                path: path,
                receiptKind: forEachElementReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: forEachElement,
                children: children
            )
        case .repeatUntil(let repeatUntil):
            return .passed(
                path: path,
                receiptKind: repeatUntilReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: repeatUntil,
                children: children
            )
        case .invocation(let invocation):
            return .passed(
                path: path,
                receiptKind: invocationReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: invocation,
                children: children
            )
        case .warning(let warning):
            precondition(kind == .warn, "Warning receipt evidence can only be used with warn steps")
            return .passed(path: path, receiptKind: .warning, durationMs: durationMs, intent: intent, evidence: warning, children: children)
        }
    }

    private func failedHeistStep(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent?,
        evidence: HeistStepEvidence?,
        failure: HeistFailureDetail,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        guard let evidence else {
            return .failed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                failure: failure,
                children: children
            )
        }
        switch evidence {
        case .action(let action):
            precondition(kind == .action, "Action receipt evidence can only be used with action steps")
            return .failed(path: path, receiptKind: .action, durationMs: durationMs, intent: intent, evidence: action, failure: failure, children: children)
        case .wait(let wait):
            precondition(kind == .wait, "Wait receipt evidence can only be used with wait steps")
            return .failed(path: path, receiptKind: .wait, durationMs: durationMs, intent: intent, evidence: wait, failure: failure, children: children)
        case .caseSelection(let selection):
            precondition(kind == .conditional, "Case-selection receipt evidence can only be used with conditional steps")
            return .failed(
                path: path,
                receiptKind: .conditional,
                durationMs: durationMs,
                intent: intent,
                evidence: selection,
                failure: failure,
                children: children
            )
        case .forEachString(let forEachString):
            return .failed(
                path: path,
                receiptKind: forEachStringReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: forEachString,
                failure: failure,
                children: children
            )
        case .forEachElement(let forEachElement):
            return .failed(
                path: path,
                receiptKind: forEachElementReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: forEachElement,
                failure: failure,
                children: children
            )
        case .repeatUntil(let repeatUntil):
            return .failed(
                path: path,
                receiptKind: repeatUntilReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: repeatUntil,
                failure: failure,
                children: children
            )
        case .invocation(let invocation):
            return .failed(
                path: path,
                receiptKind: invocationReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: invocation,
                failure: failure,
                children: children
            )
        case .warning(let warning):
            precondition(kind == .warn, "Warning receipt evidence can only be used with warn steps")
            return .failed(path: path, receiptKind: .warning, durationMs: durationMs, intent: intent, evidence: warning, failure: failure, children: children)
        }
    }

    private func childAbortedHeistStep(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent?,
        evidence: HeistStepEvidence,
        failure: HeistFailureDetail,
        abortedAtChildPath: String,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        switch evidence {
        case .action(let action):
            precondition(kind == .action, "Action receipt evidence can only be used with action steps")
            return .childAborted(
                path: path,
                receiptKind: .action,
                durationMs: durationMs,
                intent: intent,
                evidence: action,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .wait(let wait):
            precondition(kind == .wait, "Wait receipt evidence can only be used with wait steps")
            return .childAborted(
                path: path,
                receiptKind: .wait,
                durationMs: durationMs,
                intent: intent,
                evidence: wait,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .caseSelection(let selection):
            precondition(kind == .conditional, "Case-selection receipt evidence can only be used with conditional steps")
            return .childAborted(
                path: path,
                receiptKind: .conditional,
                durationMs: durationMs,
                intent: intent,
                evidence: selection,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .forEachString(let forEachString):
            return .childAborted(
                path: path,
                receiptKind: forEachStringReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: forEachString,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .forEachElement(let forEachElement):
            return .childAborted(
                path: path,
                receiptKind: forEachElementReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: forEachElement,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .repeatUntil(let repeatUntil):
            return .childAborted(
                path: path,
                receiptKind: repeatUntilReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: repeatUntil,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .invocation(let invocation):
            return .childAborted(
                path: path,
                receiptKind: invocationReceiptKind(for: kind),
                durationMs: durationMs,
                intent: intent,
                evidence: invocation,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .warning(let warning):
            precondition(kind == .warn, "Warning receipt evidence can only be used with warn steps")
            return .childAborted(
                path: path,
                receiptKind: .warning,
                durationMs: durationMs,
                intent: intent,
                evidence: warning,
                failure: failure,
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        }
    }

    private func forEachStringReceiptKind(
        for kind: HeistExecutionStepKind
    ) -> HeistStepReceiptKind<HeistForEachStringEvidence> {
        switch kind {
        case .forEachString:
            return .forEachString
        case .forEachIteration:
            return .forEachStringIteration
        default:
            preconditionFailure("for_each_string receipt evidence can only be used with for_each_string steps")
        }
    }

    private func forEachElementReceiptKind(
        for kind: HeistExecutionStepKind
    ) -> HeistStepReceiptKind<HeistForEachElementEvidence> {
        switch kind {
        case .forEachElement:
            return .forEachElement
        case .forEachIteration:
            return .forEachElementIteration
        default:
            preconditionFailure("for_each_element receipt evidence can only be used with for_each_element steps")
        }
    }

    private func repeatUntilReceiptKind(
        for kind: HeistExecutionStepKind
    ) -> HeistStepReceiptKind<HeistRepeatUntilEvidence> {
        switch kind {
        case .repeatUntil:
            return .repeatUntil
        case .repeatUntilIteration:
            return .repeatUntilIteration
        default:
            preconditionFailure("repeat_until receipt evidence can only be used with repeat_until steps")
        }
    }

    private func invocationReceiptKind(
        for kind: HeistExecutionStepKind
    ) -> HeistStepReceiptKind<HeistInvocationEvidence> {
        switch kind {
        case .heist:
            return .heist
        case .invoke:
            return .invocation
        default:
            preconditionFailure("Invocation receipt evidence can only be used with heist or invoke steps")
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
