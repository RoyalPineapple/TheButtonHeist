#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

extension TheBrains {
    internal func admittedReceipt(
        _ admission: HeistReceiptAdmission?,
        path: HeistExecutionPath,
        durationMs: Int,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let rejection: HeistReceiptAdmissionError
        switch admission {
        case .admitted(let receipt):
            return receipt
        case .rejected(let error):
            rejection = error
        case nil:
            rejection = .evidenceConstructionFailed
        }

        let failure = HeistFailureDetail(
            category: .internalInvariant,
            contract: "runtime values form an admitted receipt node",
            observed: rejection.description
        )
        let completion: HeistFailureCompletion
        switch HeistExecutedChildren(children) {
        case .passed(let children):
            completion = .failed(failure: failure, children: children)
        case .aborted(let children):
            completion = .childAborted(failure: failure, children: children)
        }
        return .failure(
            path: path,
            durationMs: durationMs,
            message: "receipt invariant failed",
            completion: completion
        )
    }

    internal func childFailureDetail(
        category: HeistFailureCategory,
        childPath: HeistExecutionPath
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: category,
            contract: "child execution completes without failure",
            observed: "child failed at \(childPath)",
            expected: "all executed child steps pass"
        )
    }

    internal func failureScreenshotStep(
        runtime: HeistExecutionRuntime,
        failedPath: HeistExecutionPath,
        mode: ScreenCaptureMode
    ) async -> HeistExecutionStepResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let result = mode == .raw
            ? await runtime.execute(.takeScreenshot, nil).result
            : await executeTakeScreenshot(mode: mode)
        guard result.method == .takeScreenshot else { return nil }
        let command = HeistActionCommand.takeScreenshot
        let evidence = HeistActionEvidence.dispatch(dispatchResult: result)
        let path = failedPath.failureAction(at: 0)
        let durationMs = elapsedMilliseconds(since: start)
        if let failure = failureScreenshotDetail(for: result) {
            guard let evidence = HeistFailedActionEvidence(evidence) else { return nil }
            return HeistExecutionStepResult.admitAction(
                path: path,
                durationMs: durationMs,
                command: command,
                completion: .failed(evidence: evidence, failure: failure)
            ).receipt
        }
        guard let evidence = HeistPassedActionEvidence(evidence) else { return nil }
        return HeistExecutionStepResult.admitAction(
            path: path,
            durationMs: durationMs,
            command: command,
            completion: .passed(evidence: evidence)
        ).receipt
    }

    private func failureScreenshotDetail(for result: ActionResult) -> HeistFailureDetail? {
        guard !result.outcome.isSuccess else { return nil }
        return HeistFailureDetail(
            category: .action,
            contract: "failure screenshot action captures visible screen",
            observed: result.message ?? "screenshot action failed",
            expected: HeistActionCommandType.takeScreenshot.rawValue
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
