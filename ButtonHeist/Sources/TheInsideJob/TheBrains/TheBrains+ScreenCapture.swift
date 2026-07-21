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

    enum ScreenCaptureGatewayResult {
        case success(ScreenPayload, context: ActionExpectationContext?)
        case failure(ScreenCaptureFailure)
    }

    func captureScreenPayload(
        mode: ScreenCaptureMode = .raw,
        capturesExpectationContext: Bool = false
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
        let actionExpectationContext: ActionExpectationContext?
        if capturesExpectationContext {
            let window = vault.accessibilityNotifications.beginActionWindow()
            notificationWindow = window
            actionExpectationContext = ActionExpectationContext(
                preActionCapture: settledCapture,
                throughObservationCursor: settledCapture.cursor,
                announcementCursor: window.cursor
            )
        } else {
            notificationWindow = nil
            actionExpectationContext = nil
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
            return .success(payload, context: actionExpectationContext)
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
        return .success(payload, context: actionExpectationContext)
    }

    func executeTakeScreenshot(
        mode: ScreenCaptureMode = .raw,
        capturesExpectationContext: Bool = false
    ) async -> RuntimeActionExecution {
        let timing = ActionTiming()
        switch await captureScreenPayload(
            mode: mode,
            capturesExpectationContext: capturesExpectationContext
        ) {
        case .success(let payload, let context):
            return RuntimeActionExecution(
                result: .success(
                    payload: .screenshot(payload),
                    message: "Captured screenshot \(Int(payload.width))x\(Int(payload.height))",
                    timing: timing.freeze()
                ),
                actionExpectationContext: context
            )
        case .failure(let failure):
            return RuntimeActionExecution(
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
}

#endif // DEBUG
#endif // canImport(UIKit)
