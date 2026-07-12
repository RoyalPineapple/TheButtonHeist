#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    struct HeistReceiptAbortedChildren: Equatable {
        let firstFailedPath: String
        let children: [HeistExecutionStepResult]
    }

    struct HeistReceiptChildren: Equatable {
        let children: [HeistExecutionStepResult]

        static let empty = HeistReceiptChildren([])

        init(_ children: [HeistExecutionStepResult]) {
            self.children = children
        }

        var aborted: HeistReceiptAbortedChildren? {
            children.firstFailedStep.map {
                HeistReceiptAbortedChildren(firstFailedPath: $0.path, children: children)
            }
        }

        var abortedAtChildPath: String? {
            children.firstFailedStep?.path
        }
    }

    func heistActionReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: .action,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure
        )
    }

    func heistWaitReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        children: HeistReceiptChildren = .empty,
        childFailure: ((String) -> HeistFailureDetail)? = nil
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: .wait,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            children: children,
            childFailure: childFailure
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
            durationMs: 0,
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
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        children: HeistReceiptChildren = .empty,
        childFailure: ((String) -> HeistFailureDetail)? = nil
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: .invoke,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            children: children,
            childFailure: childFailure
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
        return heistStepReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            children: children,
            childFailure: { childPath in
                self.childFailureDetail(category: childFailureCategory, childPath: childPath)
            }
        )
    }

    func heistLoopReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        children: HeistReceiptChildren = .empty,
        childFailure: ((String) -> HeistFailureDetail)? = nil
    ) -> HeistExecutionStepResult {
        heistStepReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            children: children,
            childFailure: childFailure
        )
    }

    private func heistStepReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        children: HeistReceiptChildren = .empty,
        childFailure: ((String) -> HeistFailureDetail)? = nil
    ) -> HeistExecutionStepResult {
        if let aborted = children.aborted {
            guard let evidence, let childFailure else {
                preconditionFailure("Child-aborted heist receipt requires evidence and child failure detail")
            }
            return .childAborted(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: childFailure(aborted.firstFailedPath),
                abortedAtChildPath: aborted.firstFailedPath,
                children: aborted.children
            )
        }
        if let failure {
            return .failed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure,
                children: children.children
            )
        }
        return .passed(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            children: children.children
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
