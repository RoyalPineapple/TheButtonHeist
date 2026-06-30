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
        evidence: HeistWaitEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        abortedAtChildPath: String? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let resolvedAbortedAtChildPath = abortedAtChildPath ?? children.firstFailedStep?.path
        if let failure = failure ?? resolvedAbortedAtChildPath.map({ childFailureDetail(category: .wait, childPath: $0) }) {
            return .failed(
                path: path,
                kind: .wait,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence.map(HeistStepEvidence.wait),
                failure: failure,
                abortedAtChildPath: resolvedAbortedAtChildPath,
                children: children
            )
        }

        return .passed(
            path: path,
            kind: .wait,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence.map(HeistStepEvidence.wait),
            children: children
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
        evidence: HeistInvocationEvidence,
        failure: HeistFailureDetail? = nil,
        abortedAtChildPath: String? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let resolvedAbortedAtChildPath = abortedAtChildPath ?? children.firstFailedStep?.path
        if let failure = failure ?? resolvedAbortedAtChildPath.map({ childFailureDetail(category: .invocation, childPath: $0) }) {
            return .failed(
                path: path,
                kind: .invoke,
                durationMs: durationMs,
                intent: intent,
                evidence: .invocation(evidence),
                failure: failure,
                abortedAtChildPath: resolvedAbortedAtChildPath,
                children: children
            )
        }

        return .passed(
            path: path,
            kind: .invoke,
            durationMs: durationMs,
            intent: intent,
            evidence: .invocation(evidence),
            children: children
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
        children: [HeistExecutionStepResult],
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let abortedAtChildPath = children.firstFailedStep?.path
        if let failure = failure ?? abortedAtChildPath.map({ childFailureDetail(category: childFailureCategory, childPath: $0) }) {
            return .failed(
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

        return .passed(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
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
        let resolvedAbortedAtChildPath = abortedAtChildPath ?? children.firstFailedStep?.path
        if let failure = failure ?? resolvedAbortedAtChildPath.map({ childFailureDetail(category: .loop, childPath: $0) }) {
            return .failed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: failure,
                abortedAtChildPath: resolvedAbortedAtChildPath,
                children: children
            )
        }

        return .passed(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
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
        if let abortedAtChildPath {
            return .failed(
                path: path,
                kind: kind,
                durationMs: durationMs,
                intent: intent,
                evidence: evidence,
                failure: childFailureDetail(category: .loop, childPath: abortedAtChildPath),
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        }

        return .passed(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            children: children
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
