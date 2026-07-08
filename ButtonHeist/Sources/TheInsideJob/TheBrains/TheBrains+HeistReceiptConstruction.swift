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
        .failed(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
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
        .failed(
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
            return .passed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                children: children.children
            )
        case .failed(let evidence, let failure, let children):
            return .failed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure,
                children: children.children
            )
        case .childAborted(let evidence, let failure, let abortedAtChildPath, let children):
            return .childAborted(
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

}

#endif // DEBUG
#endif // canImport(UIKit)
