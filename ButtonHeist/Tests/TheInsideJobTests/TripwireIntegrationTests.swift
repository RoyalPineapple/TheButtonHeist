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
        tripwire.stopPulse()
        tripwire = nil
        super.tearDown()
    }

    // MARK: - waitForAllClear (delegates to waitForSettle)

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

    func testWaitForAllClearGatesPendingLayout() async {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        window.addSubview(testView)
        testView.setNeedsLayout()

        let settled = await tripwire.waitForAllClear(timeout: 2.0)
        XCTAssertTrue(settled, "Should settle after pending layout flushes")

        testView.removeFromSuperview()
    }

    // MARK: - waitForSettle

    func testWaitForSettleResolvesWhenIdle() async {
        let settled = await tripwire.waitForSettle(timeout: 2.0)
        XCTAssertTrue(settled)
    }

    func testWaitForSettleTimesOutDuringAnimation() async {
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

        let settled = await tripwire.waitForSettle(timeout: 0.5)
        XCTAssertFalse(settled, "Should time out while animation is running")

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

    func testWaitForSettleCustomQuietFrames() async {
        // Requesting more quiet frames should still settle when idle
        let settled = await tripwire.waitForSettle(timeout: 2.0, requiredQuietFrames: 4)
        XCTAssertTrue(settled)
    }

    func testMultipleConcurrentSettleWaiters() async {
        // Two waiters should both resolve when the UI is idle
        async let settle1 = tripwire.waitForSettle(timeout: 2.0)
        async let settle2 = tripwire.waitForSettle(timeout: 2.0)

        let (result1, result2) = await (settle1, settle2)
        XCTAssertTrue(result1)
        XCTAssertTrue(result2)
    }

    // MARK: - Pulse produces readings

    func testPulseProducesReadingAfterStart() async {
        tripwire.startPulse()
        // Give the pulse a few ticks to produce a reading
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(tripwire.latestReading)
        XCTAssertGreaterThan(tripwire.latestReading?.tick ?? 0, 0)
    }

    func testPulseReadingHasValidWindowCount() async {
        tripwire.startPulse()
        // Window count is sampled every 5th tick (~500ms at 10Hz).
        // Wait long enough for at least one slow-cadence sample.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard let reading = tripwire.latestReading else {
            XCTFail("No reading produced")
            return
        }
        XCTAssertGreaterThan(reading.windowCount, 0)
    }

    func testPulseReadingTracksVCIdentity() async {
        tripwire.startPulse()
        // Wait enough ticks for VC to be sampled (every 3rd tick at ~10Hz)
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let reading = tripwire.latestReading else {
            XCTFail("No reading produced")
            return
        }
        // Test host should have a VC
        XCTAssertNotNil(reading.topmostVC)
    }

    // MARK: - Settle transition callback

    func testSettleTransitionCallbackFires() async {
        let expectation = XCTestExpectation(description: "settled callback")
        tripwire.onTransition = { transition in
            if case .settled = transition {
                expectation.fulfill()
            }
        }

        tripwire.startPulse()
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - Fingerprint divergence during animation

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
