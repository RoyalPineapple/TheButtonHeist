#if canImport(UIKit)
import UIKit
import XCTest

@MainActor
func requireForegroundWindowScene() throws -> UIWindowScene {
    try XCTUnwrap(
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
        "Expected a foreground-active UIWindowScene in the hosted test app"
    )
}
#endif
