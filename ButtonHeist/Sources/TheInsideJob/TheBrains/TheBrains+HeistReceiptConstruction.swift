#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func heistActionReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistActionEvidence,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        heistReceipt(
            path: path,
            kind: .action,
            durationMs: durationMs,
            intent: intent,
            evidence: .action(evidence),
            failure: failure
        )
    }

    func heistWaitReceipt(
        path: String,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistWaitEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        abortedAtChildPath: String? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        heistReceipt(
            path: path,
            kind: .wait,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence.map(HeistStepEvidence.wait),
            failure: failure,
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    func heistSkippedReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        heistReceipt(
            path: path,
            kind: kind,
            status: .skipped,
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
        heistReceipt(
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
        heistReceipt(
            path: path,
            kind: .fail,
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
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail
    ) -> HeistExecutionStepResult {
        heistReceipt(
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
        children: [HeistExecutionStepResult],
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let abortedAtChildPath = children.firstFailedStep?.path
        return heistReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure ?? abortedAtChildPath.map {
                childFailureDetail(category: childFailureCategory, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    func heistLoopReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistStepEvidence,
        failure: HeistFailureDetail? = nil,
        abortedAtChildPath: String? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        heistReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    func heistLoopIterationReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistStepEvidence,
        abortedAtChildPath: String?,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        heistReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .loop, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func heistReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        status requestedStatus: HeistExecutionStepStatus? = nil,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        abortedAtChildPath: String? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let resolvedAbortedAtChildPath = abortedAtChildPath ?? children.firstFailedStep?.path
        let status = requestedStatus ?? (failure != nil || resolvedAbortedAtChildPath != nil ? .failed : .passed)
        return HeistExecutionStepResult(
            path: path,
            kind: kind,
            status: status,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: failure,
            abortedAtChildPath: resolvedAbortedAtChildPath,
            children: children
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
