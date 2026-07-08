#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    struct HeistReceiptAbortedChildren: Equatable {
        let firstFailedPath: String
        let children: [HeistExecutionStepResult]
    }

    private enum HeistReceiptChildrenState: Equatable {
        case completed([HeistExecutionStepResult])
        case aborted(HeistReceiptAbortedChildren)
    }

    struct HeistReceiptChildren: Equatable {
        private let state: HeistReceiptChildrenState

        static let empty = HeistReceiptChildren([])

        init(_ children: [HeistExecutionStepResult]) {
            if let firstFailedPath = children.firstFailedStep?.path {
                state = .aborted(HeistReceiptAbortedChildren(firstFailedPath: firstFailedPath, children: children))
            } else {
                state = .completed(children)
            }
        }

        var children: [HeistExecutionStepResult] {
            switch state {
            case .completed(let children):
                return children
            case .aborted(let aborted):
                return aborted.children
            }
        }

        var aborted: HeistReceiptAbortedChildren? {
            switch state {
            case .completed:
                return nil
            case .aborted(let aborted):
                return aborted
            }
        }

        var abortedAtChildPath: String? {
            aborted?.firstFailedPath
        }
    }

    enum HeistStepReceiptOutcome {
        case passed(evidence: HeistStepEvidence? = nil, children: HeistReceiptChildren = .empty)
        case failed(evidence: HeistStepEvidence? = nil, failure: HeistFailureDetail, children: HeistReceiptChildren = .empty)
        case childAborted(evidence: HeistStepEvidence, failure: HeistFailureDetail, abortedChildren: HeistReceiptAbortedChildren)
        case skipped(children: HeistReceiptChildren = .empty)
    }

    private struct HeistStepReceiptFolder {
        let path: String
        let kind: HeistExecutionStepKind
        let durationMs: Int
        let intent: HeistStepIntent?

        func fold(_ outcome: HeistStepReceiptOutcome) -> HeistExecutionStepResult {
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
            case .childAborted(let evidence, let failure, let abortedChildren):
                return .childAborted(
                    path: path,
                    kind: kind,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: evidence,
                    failure: failure,
                    abortedAtChildPath: abortedChildren.firstFailedPath,
                    children: abortedChildren.children
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
        guard let abortedChildren = children.aborted else {
            return .passed(evidence: evidence, children: children)
        }
        return .childAborted(
            evidence: evidence,
            failure: childFailure(abortedChildren.firstFailedPath),
            abortedChildren: abortedChildren
        )
    }

    func childAwareFailedOutcome(
        evidence: HeistStepEvidence,
        failure: HeistFailureDetail,
        children: HeistReceiptChildren,
        childFailure: (String) -> HeistFailureDetail
    ) -> HeistStepReceiptOutcome {
        guard let abortedChildren = children.aborted else {
            return .failed(evidence: evidence, failure: failure, children: children)
        }
        return .childAborted(
            evidence: evidence,
            failure: childFailure(abortedChildren.firstFailedPath),
            abortedChildren: abortedChildren
        )
    }

    private func heistStepReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        outcome: HeistStepReceiptOutcome
    ) -> HeistExecutionStepResult {
        HeistStepReceiptFolder(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent
        ).fold(outcome)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
