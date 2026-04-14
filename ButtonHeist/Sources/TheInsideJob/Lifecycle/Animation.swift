#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    func handleWaitForIdle(_ target: WaitForIdleTarget, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        let result = await brains.executeWaitForIdle(timeout: min(target.timeout ?? 5.0, 60.0))
        sendMessage(.actionResult(result), requestId: requestId, respond: respond)
        brains.recordSentState()
    }

    func handleWaitForChange(_ target: WaitForChangeTarget, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        let result = await brains.executeWaitForChange(
            timeout: target.resolvedTimeout, expectation: target.expect
        )
        sendMessage(.actionResult(result), requestId: requestId, respond: respond)
        brains.recordSentState()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
