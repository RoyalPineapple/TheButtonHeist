#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheBrains {
    enum ScreenCaptureFailure: Equatable, Sendable {
        case inactiveRuntime
        case accessibilityTreeUnavailable
        case appWindowUnavailable
        case accessibilitySnapshotRenderingFailed
        case pngEncodingFailed
        case invalidScreenDimensions

        var message: String {
            switch self {
            case .inactiveRuntime:
                return TheBrains.runtimeInactiveMessage
            case .accessibilityTreeUnavailable:
                return "Could not access accessibility tree"
            case .appWindowUnavailable:
                return "Could not access app window"
            case .accessibilitySnapshotRenderingFailed:
                return "Failed to render accessibility snapshot"
            case .pngEncodingFailed:
                return "Failed to encode screen as PNG"
            case .invalidScreenDimensions:
                return "Captured screen dimensions are invalid"
            }
        }

        var actionFailureKind: ActionFailure.Kind {
            switch self {
            case .inactiveRuntime, .accessibilityTreeUnavailable:
                return .accessibilityTreeUnavailable
            case .appWindowUnavailable, .accessibilitySnapshotRenderingFailed, .pngEncodingFailed,
                 .invalidScreenDimensions:
                return .actionFailed
            }
        }
    }

    enum ScreenCaptureGatewaySuccess {
        case payload(ScreenPayload)
        case action(ScreenPayload, context: ActionExpectationContext)

        var payload: ScreenPayload {
            switch self {
            case .payload(let payload), .action(let payload, _): payload
            }
        }

        var actionExpectationContext: ActionExpectationContext? {
            guard case .action(_, let context) = self else { return nil }
            return context
        }
    }

    enum ScreenCaptureGatewayResult {
        case success(ScreenCaptureGatewaySuccess)
        case failure(ScreenCaptureFailure)
    }

    struct ScreenCaptureActionExecution {
        let result: ActionResult
        let actionExpectationContext: ActionExpectationContext?
    }

    func captureScreenPayload(mode: ScreenCaptureMode = .raw) async -> ScreenCaptureGatewayResult {
        await captureScreenPayload(mode: mode, boundaryRequest: .none)
    }

    private enum ScreenCaptureBoundaryRequest {
        case none
        case action
    }

    private enum CapturedScreenBoundary {
        case none
        case action(ActionExpectationContext)
    }

    private func captureScreenPayload(
        mode: ScreenCaptureMode,
        boundaryRequest: ScreenCaptureBoundaryRequest
    ) async -> ScreenCaptureGatewayResult {
        guard semanticObservationIsActive else {
            return .failure(.inactiveRuntime)
        }
        guard let observation = await interactionCoordinator.admittedVisibleBaseline(timeout: 1.0) else {
            return .failure(.accessibilityTreeUnavailable)
        }
        guard let sequence = observation.settledObservationSequence,
              let settledCapture = vault.semanticObservationStream.settledCapture(
                scope: .visible,
                at: sequence
              ) else {
            preconditionFailure("admitted screenshot baseline must retain its settled capture")
        }

        let notificationWindow: AccessibilityNotificationScopeLease?
        let capturedBoundary: CapturedScreenBoundary
        switch boundaryRequest {
        case .none:
            notificationWindow = nil
            capturedBoundary = .none
        case .action:
            let window = vault.accessibilityNotifications.beginActionWindow()
            notificationWindow = window
            capturedBoundary = .action(ActionExpectationContext(
                preActionCapture: settledCapture,
                observations: [],
                announcementCursor: window.cursor
            ))
        }
        defer { notificationWindow?.cancel() }

        guard let screenCapture = vault.captureScreen() else {
            return .failure(.appWindowUnavailable)
        }

        if mode == .accessibility {
            guard let payload = renderAccessibilitySnapshotPayload(
                image: screenCapture.image,
                bounds: screenCapture.bounds,
                interface: settledCapture.capture.interface
            ) else {
                return .failure(.accessibilitySnapshotRenderingFailed)
            }
            return .success(screenCaptureSuccess(
                payload: payload,
                capturedBoundary: capturedBoundary
            ))
        }

        guard let pngData = screenCapture.image.pngData() else {
            return .failure(.pngEncodingFailed)
        }

        guard let payload = ScreenPayload.admit(
            pngData: pngData.base64EncodedString(),
            width: screenCapture.bounds.width,
            height: screenCapture.bounds.height,
            interface: settledCapture.capture.interface
        ) else {
            return .failure(.invalidScreenDimensions)
        }
        return .success(screenCaptureSuccess(
            payload: payload,
            capturedBoundary: capturedBoundary
        ))
    }

    func executeTakeScreenshot(mode: ScreenCaptureMode = .raw) async -> ActionResult {
        await executeTakeScreenshot(mode: mode, boundaryRequest: .none).result
    }

    func executeTakeScreenshotWithExpectationContext(
        mode: ScreenCaptureMode = .raw
    ) async -> ScreenCaptureActionExecution {
        await executeTakeScreenshot(mode: mode, boundaryRequest: .action)
    }

    private func executeTakeScreenshot(
        mode: ScreenCaptureMode,
        boundaryRequest: ScreenCaptureBoundaryRequest
    ) async -> ScreenCaptureActionExecution {
        let timing = ActionTiming()
        switch await captureScreenPayload(mode: mode, boundaryRequest: boundaryRequest) {
        case .success(let success):
            return ScreenCaptureActionExecution(
                result: .success(
                    payload: .screenshot(success.payload),
                    message: "Captured screenshot \(Int(success.payload.width))x\(Int(success.payload.height))",
                    timing: timing.freeze()
                ),
                actionExpectationContext: success.actionExpectationContext
            )
        case .failure(let failure):
            return ScreenCaptureActionExecution(
                result: .failure(
                    payload: .screenshot(nil),
                    failureKind: failure.actionFailureKind,
                    message: failure.message,
                    timing: timing.freeze()
                ),
                actionExpectationContext: nil
            )
        }
    }

    private func screenCaptureSuccess(
        payload: ScreenPayload,
        capturedBoundary: CapturedScreenBoundary
    ) -> ScreenCaptureGatewaySuccess {
        switch capturedBoundary {
        case .none:
            .payload(payload)
        case .action(let context):
            .action(payload, context: context)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
