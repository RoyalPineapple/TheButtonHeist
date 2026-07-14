#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

extension TheBrains {

    internal func childFailureDetail(category: HeistFailureCategory, childPath: String) -> HeistFailureDetail {
        HeistFailureDetail(
            category: category,
            contract: "child execution completes without failure",
            observed: "child failed at \(childPath)",
            expected: "all executed child steps pass"
        )
    }

    internal func failureScreenshotStep(
        runtime: HeistExecutionRuntime,
        failedPath: String,
        mode: ScreenCaptureMode
    ) async -> HeistExecutionStepResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let result = mode == .raw
            ? await runtime.execute(.takeScreenshot, nil).result
            : await executeTakeScreenshot(mode: mode)
        guard result.method == .takeScreenshot else { return nil }
        let command = HeistActionCommand.takeScreenshot
        let evidence = HeistActionEvidence.dispatch(command: command, dispatchResult: result)
        return heistReceipt(.init(
            path: "\(failedPath).failure.actions[0]",
            kind: .action,
            durationMs: elapsedMilliseconds(since: start),
            intent: .action(command: command),
            evidence: .action(evidence),
            completion: failureScreenshotDetail(for: result)
                .map(HeistReceiptRequest.Completion.failed) ?? .passed
        ))
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
