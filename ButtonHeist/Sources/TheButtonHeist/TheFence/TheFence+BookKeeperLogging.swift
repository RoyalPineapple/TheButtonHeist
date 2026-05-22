import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "bookkeeper")

private extension FenceResponse {
    struct HeistRecordingReceipt {
        let actionResult: ActionResult
        let expectation: ExpectationResult?

        var shouldRecord: Bool {
            actionResult.success && expectation?.met != false
        }
    }

    var heistRecordingReceipt: HeistRecordingReceipt? {
        guard case .action(let result, let expectation) = self else { return nil }
        return HeistRecordingReceipt(actionResult: result, expectation: expectation)
    }
}

extension TheFence {
    func logCommand(_ request: ParsedRequest) {
        do {
            try bookKeeper.logCommand(request)
        } catch {
            logger.warning(
                """
                Failed to log command \(request.command.rawValue, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    func logErrorResponse(requestId: String, error: Error, durationMs: Int) {
        do {
            try bookKeeper.logResponse(
                requestId: requestId,
                status: .error,
                durationMilliseconds: durationMs,
                error: error.localizedDescription
            )
        } catch let logError {
            logger.warning("Failed to log error response for \(requestId, privacy: .public): \(logError.localizedDescription, privacy: .public)")
        }
    }

    func logResponse(requestId: String, response: FenceResponse, durationMs: Int) {
        let responseStatus: ResponseStatus
        let errorMessage: String?
        switch response {
        case .error(let message, _):
            responseStatus = .error
            errorMessage = message
        case .screenshot, .recording, .recordingExpanded, .archiveResult:
            responseStatus = .ok
            errorMessage = nil
        case .ok, .help, .status, .pong, .devices, .interface, .action,
             .screenshotData, .recordingData, .batch, .sessionState,
             .targets, .sessionLog, .heistStarted, .heistStopped,
             .heistPlayback:
            responseStatus = .ok
            errorMessage = nil
        }
        do {
            try bookKeeper.logResponse(
                requestId: requestId,
                status: responseStatus,
                durationMilliseconds: durationMs,
                error: errorMessage
            )
        } catch {
            logger.warning("Failed to log response for \(requestId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordHeistEvidence(
        _ request: ParsedRequest,
        dispatchedResponse: FenceResponse,
        validatedResponse: FenceResponse,
        lookupCaptureRef: AccessibilityTrace.CaptureRef?
    ) {
        guard playback.isIdle else { return }
        guard let finalReceipt = validatedResponse.heistRecordingReceipt, finalReceipt.shouldRecord else { return }
        let targetCapture = dispatchedResponse.actionResult?.accessibilityTrace?.captures.first
            ?? lookupCaptureRef.flatMap { backgroundAccessibilityState.capture(ref: $0) }
            ?? finalReceipt.actionResult.accessibilityTrace?.captures.first
        bookKeeper.recordHeistEvidence(
            request,
            actionResult: finalReceipt.actionResult,
            expectation: finalReceipt.expectation,
            targetCapture: targetCapture
        )
    }
}
