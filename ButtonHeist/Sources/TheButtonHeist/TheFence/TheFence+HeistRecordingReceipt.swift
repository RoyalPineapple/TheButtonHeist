import TheScore

private extension FenceResponse {
    struct HeistRecordingReceipt {
        let actionResult: ActionResult
        let expectation: ExpectationResult?

        var shouldRecord: Bool {
            actionResult.success && expectation?.met != false
        }
    }

    var heistRecordingReceipt: HeistRecordingReceipt? {
        guard case .action(_, let result, let expectation) = self else { return nil }
        return HeistRecordingReceipt(actionResult: result, expectation: expectation)
    }
}

extension TheFence {
    func recordHeistStep(
        _ request: ParsedRequest,
        dispatchedResponse: FenceResponse,
        validatedResponse: FenceResponse,
        targetCapture: AccessibilityTrace.Capture?
    ) {
        guard playback.isIdle else { return }
        guard let finalReceipt = validatedResponse.heistRecordingReceipt, finalReceipt.shouldRecord else { return }
        heistStore.recordHeistStep(
            request,
            actionResult: finalReceipt.actionResult,
            expectation: finalReceipt.expectation,
            targetCapture: targetCapture
        )
    }
}
