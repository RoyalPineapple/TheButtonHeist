#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheBrains {
    enum ScreenCaptureFailure: Equatable, Sendable {
        case inactiveRuntime
        case accessibilityTreeUnavailable
        case appWindowUnavailable
        case pngEncodingFailed

        var message: String {
            switch self {
            case .inactiveRuntime:
                return TheBrains.runtimeInactiveMessage
            case .accessibilityTreeUnavailable:
                return "Could not access accessibility tree"
            case .appWindowUnavailable:
                return "Could not access app window"
            case .pngEncodingFailed:
                return "Failed to encode screen as PNG"
            }
        }
    }

    enum ScreenCaptureGatewayResult {
        case success(ScreenPayload)
        case failure(ScreenCaptureFailure)
    }

    func captureScreenPayload() async -> ScreenCaptureGatewayResult {
        guard semanticObservationIsActive else {
            return .failure(.inactiveRuntime)
        }
        guard let observation = await interactionObservation.observeVisibleState(timeout: 1.0) else {
            return .failure(.accessibilityTreeUnavailable)
        }

        guard let screenCapture = stash.captureScreen() else {
            return .failure(.appWindowUnavailable)
        }

        guard let pngData = screenCapture.image.pngData() else {
            return .failure(.pngEncodingFailed)
        }

        return .success(ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: screenCapture.bounds.width,
            height: screenCapture.bounds.height,
            interface: observation.interface
        ))
    }

    func executeTakeScreenshot() async -> ActionResult {
        let start = CFAbsoluteTimeGetCurrent()
        var builder = ActionResultBuilder()
        switch await captureScreenPayload() {
        case .success(let payload):
            builder.message = "Captured screenshot \(Int(payload.width))x\(Int(payload.height))"
            builder.timing = ActionPerformanceTiming(totalMs: elapsedMilliseconds(since: start))
            return builder.success(payload: .screenshot(payload))
        case .failure(let failure):
            builder.message = failure.message
            builder.timing = ActionPerformanceTiming(totalMs: elapsedMilliseconds(since: start))
            return builder.failure(method: .takeScreenshot, errorKind: .general)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
