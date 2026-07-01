#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    struct HeistReceiptCompletedChildren: Equatable {
        let children: [HeistExecutionStepResult]

        static let empty = HeistReceiptCompletedChildren([])

        fileprivate init(_ children: [HeistExecutionStepResult]) {
            self.children = children
        }
    }

    struct HeistReceiptChildAbort: Equatable {
        let abortedAtChildPath: String
        let children: [HeistExecutionStepResult]

        fileprivate init(abortedAtChildPath: String, children: [HeistExecutionStepResult]) {
            self.abortedAtChildPath = abortedAtChildPath
            self.children = children
        }
    }

    enum HeistReceiptChildren: Equatable {
        case completed(HeistReceiptCompletedChildren)
        case childAborted(HeistReceiptChildAbort)

        init(_ children: [HeistExecutionStepResult]) {
            guard let abortedAtChildPath = children.firstFailedStep?.path else {
                self = .completed(HeistReceiptCompletedChildren(children))
                return
            }
            self = .childAborted(HeistReceiptChildAbort(
                abortedAtChildPath: abortedAtChildPath,
                children: children
            ))
        }

        var children: [HeistExecutionStepResult] {
            switch self {
            case .completed(let completed):
                return completed.children
            case .childAborted(let childAbort):
                return childAbort.children
            }
        }

        var abortedAtChildPath: String? {
            switch self {
            case .completed:
                return nil
            case .childAborted(let childAbort):
                return childAbort.abortedAtChildPath
            }
        }
    }

    enum HeistReceiptCompletedOutcome {
        case passed
        case failed(HeistFailureDetail)

        init(failure: HeistFailureDetail?) {
            if let failure {
                self = .failed(failure)
            } else {
                self = .passed
            }
        }
    }

    enum HeistReceiptOutcome<Evidence> {
        case passed(evidence: Evidence, children: HeistReceiptCompletedChildren)
        case failed(evidence: Evidence, failure: HeistFailureDetail, children: HeistReceiptCompletedChildren)
        case childAborted(evidence: Evidence, failure: HeistFailureDetail, children: HeistReceiptChildAbort)

        init(
            evidence: Evidence,
            children: HeistReceiptChildren,
            completedOutcome: HeistReceiptCompletedOutcome = .passed,
            childFailure: (HeistReceiptChildAbort) -> HeistFailureDetail
        ) {
            switch children {
            case .completed(let completed):
                switch completedOutcome {
                case .passed:
                    self = .passed(evidence: evidence, children: completed)
                case .failed(let failure):
                    self = .failed(
                        evidence: evidence,
                        failure: failure,
                        children: completed
                    )
                }
            case .childAborted(let childAbort):
                self = .childAborted(
                    evidence: evidence,
                    failure: childFailure(childAbort),
                    children: childAbort
                )
            }
        }

        func stepResult(
            path: String,
            kind: HeistExecutionStepKind,
            durationMs: Int,
            intent: HeistStepIntent,
            evidence makeEvidence: (Evidence) -> HeistStepEvidence
        ) -> HeistExecutionStepResult {
            switch self {
            case .passed(let evidence, let children):
                return .passed(
                    path: path,
                    kind: kind,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: makeEvidence(evidence),
                    children: children.children
                )
            case .failed(let evidence, let failure, let children):
                return .failed(
                    path: path,
                    kind: kind,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: makeEvidence(evidence),
                    failure: failure,
                    children: children.children
                )
            case .childAborted(let evidence, let failure, let childAbort):
                return .childAborted(
                    path: path,
                    kind: kind,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: makeEvidence(evidence),
                    failure: failure,
                    abortedAtChildPath: childAbort.abortedAtChildPath,
                    children: childAbort.children
                )
            }
        }
    }

    func heistActionReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistActionEvidence,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        if let failure {
            return .failed(
                path: path,
                kind: .action,
                durationMs: durationMs,
                intent: intent,
                evidence: .action(evidence),
                failure: failure
            )
        }

        return .passed(
            path: path,
            kind: .action,
            durationMs: durationMs,
            intent: intent,
            evidence: .action(evidence)
        )
    }

    func heistWaitReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistReceiptOutcome<HeistWaitEvidence>
    ) -> HeistExecutionStepResult {
        return outcome.stepResult(
            path: path,
            kind: .wait,
            durationMs: durationMs,
            intent: intent,
            evidence: HeistStepEvidence.wait
        )
    }

    func heistSkippedReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        .skipped(
            path: path,
            kind: kind,
            children: children
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
            kind: .warn,
            durationMs: durationMs,
            intent: intent,
            evidence: .warning(warning)
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
        outcome: HeistReceiptOutcome<HeistInvocationEvidence>
    ) -> HeistExecutionStepResult {
        return outcome.stepResult(
            path: path,
            kind: .invoke,
            durationMs: durationMs,
            intent: intent,
            evidence: HeistStepEvidence.invocation
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
            failure: failure
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
            failure: failure
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
        let outcome = HeistReceiptOutcome(
            evidence: evidence,
            children: children,
            childFailure: { childAbort in
                childFailureDetail(category: childFailureCategory, childPath: childAbort.abortedAtChildPath)
            }
        )
        return outcome.stepResult(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: { $0 }
        )
    }

    func heistLoopReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistReceiptOutcome<HeistStepEvidence>
    ) -> HeistExecutionStepResult {
        return outcome.stepResult(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: { $0 }
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
