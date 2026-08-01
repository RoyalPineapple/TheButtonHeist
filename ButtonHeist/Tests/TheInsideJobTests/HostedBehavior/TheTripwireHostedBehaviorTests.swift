#if canImport(UIKit)
import XCTest
import UIKit

@testable import TheInsideJob

@MainActor
final class TheTripwireHostedBehaviorTests: XCTestCase {

    private var tripwire: TheTripwire!

    override func setUp() async throws {
        tripwire = TheTripwire()
    }

    override func tearDown() async throws {
        tripwire.stopPulse()
        tripwire = nil
    }

    func testTraversableWindowsAreVisibleSizedAndFrontToBack() {
        let windows = tripwire.captureTraversableWindows().map(\.window)

        XCTAssertFalse(windows.isEmpty, "Test host should have a traversable window")
        XCTAssertTrue(windows.allSatisfy { !$0.isHidden && $0.bounds.size != .zero })
        for pair in zip(windows, windows.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.windowLevel, pair.1.windowLevel)
        }
    }

    func testFingerprintWindowParticipationIsExplicit() throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        )
        let fingerprintWindow = TheFingerprints.FingerprintWindow(windowScene: scene)
        fingerprintWindow.windowLevel = .statusBar + 100
        fingerprintWindow.frame = UIScreen.main.bounds
        fingerprintWindow.isHidden = false
        defer { fingerprintWindow.isHidden = true }

        XCTAssertFalse(TheTripwire.orderedVisibleWindows().contains(fingerprintWindow))
        XCTAssertFalse(tripwire.captureTraversableWindows().contains { $0.window === fingerprintWindow })
        XCTAssertTrue(TheTripwire.orderedVisibleWindows(includeFingerprints: true).contains(fingerprintWindow))
    }

    func testHostedControllerIsResolvableWhenIdle() {
        XCTAssertNotNil(tripwire.topmostViewController())
    }

}

#endif // canImport(UIKit)
