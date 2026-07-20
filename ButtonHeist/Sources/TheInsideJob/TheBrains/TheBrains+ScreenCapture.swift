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
        case success(ScreenPayload)
        case failure(ScreenCaptureFailure)
    }

    func captureScreenPayload(mode: ScreenCaptureMode = .raw) async -> ScreenCaptureGatewayResult {
        guard semanticObservationIsActive else {
            return .failure(.inactiveRuntime)
        }
        guard let observation = await interactionCoordinator.admittedVisibleBaseline(timeout: 1.0) else {
            return .failure(.accessibilityTreeUnavailable)
        }

        guard let screenCapture = vault.captureScreen() else {
            return .failure(.appWindowUnavailable)
        }

        if mode == .accessibility {
            guard let payload = renderAccessibilitySnapshotPayload(
                image: screenCapture.image,
                bounds: screenCapture.bounds,
                interface: observation.interface
            ) else {
                return .failure(.accessibilitySnapshotRenderingFailed)
            }
            return .success(payload)
        }

        guard let pngData = screenCapture.image.pngData() else {
            return .failure(.pngEncodingFailed)
        }

        guard let payload = ScreenPayload.admit(
            pngData: pngData.base64EncodedString(),
            width: screenCapture.bounds.width,
            height: screenCapture.bounds.height,
            interface: observation.interface
        ) else {
            return .failure(.invalidScreenDimensions)
        }
        return .success(payload)
    }

    func executeTakeScreenshot(mode: ScreenCaptureMode = .raw) async -> ActionResult {
        let timing = ActionTiming()
        switch await captureScreenPayload(mode: mode) {
        case .success(let payload):
            return .success(
                payload: .screenshot(payload),
                message: "Captured screenshot \(Int(payload.width))x\(Int(payload.height))",
                timing: timing.freeze()
            )
        case .failure(let failure):
            return .failure(
                payload: .screenshot(nil),
                failureKind: failure.actionFailureKind,
                message: failure.message,
                timing: timing.freeze()
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
