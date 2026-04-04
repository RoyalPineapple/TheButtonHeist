#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Wait For Idle Handler

    func handleWaitForIdle(_ target: WaitForIdleTarget, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        let before = bagman.captureBeforeState()
        let timeout = min(target.timeout ?? 5.0, 60.0)
        let settled = await tripwire.waitForAllClear(timeout: timeout)

        let actionResult = await bagman.actionResultWithDelta(
            success: true,
            method: .waitForIdle,
            message: settled ? "UI idle" : "Timed out after \(timeout)s, UI may still be animating",
            before: before
        )
        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
