#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheBrains {
    enum ScreenCaptureGatewayResult {
        case success(ScreenPayload)
        case failure(String)
    }

    func captureScreenPayload() async -> ScreenCaptureGatewayResult {
        guard semanticObservationIsActive else {
            return .failure(Self.runtimeInactiveMessage)
        }
        guard let observation = await interactionObservation.observeVisibleState(timeout: 1.0) else {
            return .failure("Could not access accessibility tree")
        }

        guard let (image, bounds) = stash.captureScreen() else {
            return .failure("Could not access app window")
        }

        guard let pngData = image.pngData() else {
            return .failure("Failed to encode screen as PNG")
        }

        return .success(ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height,
            interface: observation.interface
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
