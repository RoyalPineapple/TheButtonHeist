#if canImport(UIKit)
// Integration tests for TheTripwire that depend on wall-clock timing (CADisplayLink).
// These require a live UIWindowScene test host and real time passing.
import XCTest
@testable import TheInsideJob

@MainActor
final class TripwireIntegrationTests: XCTestCase {

    private var tripwire: TheTripwire!

    override func setUp() {
        super.setUp()
        tripwire = TheTripwire()
    }

    override func tearDown() {
        tripwire = nil
        super.tearDown()
    }

    func testWaitForAllClearSettlesWhenIdle() async {
        let settled = await tripwire.waitForAllClear(timeout: 2.0)
        XCTAssertTrue(settled)
    }

    func testWaitForAllClearTimesOutDuringAnimation() async {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testLayer = CALayer()
        window.layer.addSublayer(testLayer)

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0
        animation.toValue = 500
        animation.duration = 10.0
        animation.repeatCount = .infinity
        testLayer.add(animation, forKey: "testMovement")

        let settled = await tripwire.waitForAllClear(timeout: 0.5)
        XCTAssertFalse(settled, "Should time out while animation is running")

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

    func testWaitForAllClearSettlesAfterShortAnimation() async {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testLayer = CALayer()
        window.layer.addSublayer(testLayer)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.5
        animation.duration = 0.15
        animation.isRemovedOnCompletion = true
        testLayer.add(animation, forKey: "briefFade")

        let settled = await tripwire.waitForAllClear(timeout: 2.0)
        XCTAssertTrue(settled, "Should settle after short animation completes")

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

    func testFingerprintDivergesDuringAnimation() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let baseline = tripwire.takePresentationFingerprint()

        let testLayer = CALayer()
        testLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        window.layer.addSublayer(testLayer)

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0
        animation.toValue = 1000
        animation.duration = 10.0
        testLayer.add(animation, forKey: "bigMove")

        // Force a run loop tick so the presentation layer updates
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        let during = tripwire.takePresentationFingerprint()
        XCTAssertFalse(
            baseline.matches(during),
            "Fingerprint should differ while a large animation is in flight"
        )

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

}

#endif // canImport(UIKit)
