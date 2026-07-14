#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    struct HeistReceiptRequest {
        let path: String
        let kind: HeistExecutionStepKind
        let durationMs: Int
        let intent: HeistStepIntent?
        let evidence: HeistStepEvidence?
        let completion: Completion
        let children: [HeistExecutionStepResult]
        let childFailure: ((String) -> HeistFailureDetail)?

        init(
            path: String,
            kind: HeistExecutionStepKind,
            durationMs: Int,
            intent: HeistStepIntent? = nil,
            evidence: HeistStepEvidence? = nil,
            completion: Completion = .passed,
            children: [HeistExecutionStepResult] = [],
            childFailure: ((String) -> HeistFailureDetail)? = nil
        ) {
            self.path = path
            self.kind = kind
            self.durationMs = durationMs
            self.intent = intent
            self.evidence = evidence
            self.completion = completion
            self.children = children
            self.childFailure = childFailure
        }
    }

    nonisolated func heistReceipt(_ request: HeistReceiptRequest) -> HeistExecutionStepResult {
        if case .skipped = request.completion {
            return .skipped(
                path: request.path,
                kind: request.kind,
                durationMs: request.durationMs,
                intent: request.intent,
                children: request.children
            )
        }
        if let failedChild = request.children.firstFailedStep {
            guard let evidence = request.evidence, let childFailure = request.childFailure else {
                preconditionFailure("Child-aborted heist receipt requires evidence and child failure detail")
            }
            return .childAborted(
                path: request.path,
                kind: request.kind,
                durationMs: request.durationMs,
                intent: request.intent,
                evidence: evidence,
                failure: childFailure(failedChild.path),
                abortedAtChildPath: failedChild.path,
                children: request.children
            )
        }
        switch request.completion {
        case .passed:
            return .passed(
                path: request.path,
                kind: request.kind,
                durationMs: request.durationMs,
                intent: request.intent,
                evidence: request.evidence,
                children: request.children
            )
        case .failed(let failure):
            return .failed(
                path: request.path,
                kind: request.kind,
                durationMs: request.durationMs,
                intent: request.intent,
                evidence: request.evidence,
                failure: failure,
                children: request.children
            )
        case .skipped:
            preconditionFailure("Skipped receipt completion must return before failure arbitration")
        }
    }
}

extension TheBrains.HeistReceiptRequest {
    enum Completion {
        case passed
        case failed(HeistFailureDetail)
        case skipped
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
