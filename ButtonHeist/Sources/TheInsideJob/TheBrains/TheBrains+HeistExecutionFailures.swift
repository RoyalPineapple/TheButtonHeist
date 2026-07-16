#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

extension TheBrains {

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
        if let failure = failureScreenshotDetail(for: result) {
            guard let evidence = HeistFailedActionEvidence(evidence) else { return nil }
            return .action(
                path: failedPath.failureAction(at: 0),
                durationMs: elapsedMilliseconds(since: start),
                command: command,
                completion: .failed(evidence: evidence, failure: failure)
            )
        }
        guard let evidence = HeistPassedActionEvidence(evidence) else { return nil }
        return .action(
            path: failedPath.failureAction(at: 0),
            durationMs: elapsedMilliseconds(since: start),
            command: command,
            completion: .passed(evidence: evidence)
        )
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
