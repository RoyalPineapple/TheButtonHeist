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

    enum HeistReceiptOutcome<Evidence> {
        case passed(evidence: Evidence, children: HeistReceiptCompletedChildren)
        case failed(evidence: Evidence, failure: HeistFailureDetail, children: HeistReceiptCompletedChildren)
        case childAborted(evidence: Evidence, failure: HeistFailureDetail, children: HeistReceiptChildAbort)
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
        switch outcome {
        case .passed(let evidence, let children):
            return .passed(
                path: path,
                kind: .wait,
                durationMs: durationMs,
                intent: intent,
                evidence: .wait(evidence),
                children: children.children
            )
        case .failed(let evidence, let failure, let children):
            return .failed(
                path: path,
                kind: .wait,
                durationMs: durationMs,
                intent: intent,
                evidence: .wait(evidence),
                failure: failure,
                children: children.children
            )
        case .childAborted(let evidence, let failure, let childAbort):
            return .childAborted(
                path: path,
                kind: .wait,
                durationMs: durationMs,
                intent: intent,
                evidence: .wait(evidence),
                failure: failure,
                abortedAtChildPath: childAbort.abortedAtChildPath,
                children: childAbort.children
            )
        }
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
        switch outcome {
        case .passed(let evidence, let children):
            return .passed(
                path: path,
                kind: .invoke,
                durationMs: durationMs,
                intent: intent,
                evidence: .invocation(evidence),
                children: children.children
            )
        case .failed(let evidence, let failure, let children):
            return .failed(
                path: path,
                kind: .invoke,
                durationMs: durationMs,
                intent: intent,
                evidence: .invocation(evidence),
                failure: failure,
                children: children.children
            )
        case .childAborted(let evidence, let failure, let childAbort):
            return .childAborted(
                path: path,
                kind: .invoke,
                durationMs: durationMs,
                intent: intent,
                evidence: .invocation(evidence),
                failure: failure,
                abortedAtChildPath: childAbort.abortedAtChildPath,
                children: childAbort.children
            )
        }
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
        switch children {
        case .completed(let completed):
            return .passed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                children: completed.children
            )
        case .childAborted(let childAbort):
            return .childAborted(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: childFailureDetail(category: childFailureCategory, childPath: childAbort.abortedAtChildPath),
                abortedAtChildPath: childAbort.abortedAtChildPath,
                children: childAbort.children
            )
        }
    }

    func heistLoopReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistReceiptOutcome<HeistStepEvidence>
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
        case .childAborted(let evidence, let failure, let childAbort):
            return .childAborted(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure,
                abortedAtChildPath: childAbort.abortedAtChildPath,
                children: childAbort.children
            )
        }
    }

    func heistLoopIterationReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        outcome: HeistReceiptOutcome<HeistStepEvidence>
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
        case .childAborted(let evidence, let failure, let childAbort):
            return .childAborted(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure,
                abortedAtChildPath: childAbort.abortedAtChildPath,
                children: childAbort.children
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
