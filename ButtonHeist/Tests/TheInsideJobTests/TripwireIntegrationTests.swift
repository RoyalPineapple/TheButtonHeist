#if canImport(UIKit)
// Integration tests for TheTripwire that depend on wall-clock timing (CADisplayLink).
// These require a live UIWindowScene test host and real time passing.
import ButtonHeistSupport
import XCTest
@testable import TheInsideJob

@MainActor
final class TripwireIntegrationTests: XCTestCase {

    private var tripwire: TheTripwire!

    override func setUp() async throws {
        tripwire = TheTripwire()
        tripwire.startPulse()
    }

    override func tearDown() async throws {
        tripwire.stopPulse()
        tripwire = nil
    }

    // MARK: - waitForAllClear (delegates to waitForSettle)

    func testWaitForAllClearSettlesWhenIdle() async {
        await assertAllClear("Idle UI should settle")
    }

    func testWaitForAllClearTimesOutDuringAnimation() async {
        let windows = tripwire.captureTraversableWindows()
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

    func testWaitForAllClearIgnoresOpacityOnlyAnimation() async {
        let windows = tripwire.captureTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testLayer = CALayer()
        testLayer.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        window.layer.addSublayer(testLayer)
        defer {
            testLayer.removeAllAnimations()
            testLayer.removeFromSuperlayer()
        }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.1
        animation.duration = 10.0
        animation.repeatCount = .infinity
        testLayer.add(animation, forKey: "testOpacityOnly")

        await assertAllClear("Opacity-only layer animation should not block geometry settle", timeout: 0.5)
    }

    func testWaitForAllClearSettlesAfterShortAnimation() async {
        let windows = tripwire.captureTraversableWindows()
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

        await assertAllClear("Should settle after short animation completes")

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

    func testWaitForAllClearGatesPendingLayout() async {
        let windows = tripwire.captureTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        window.addSubview(testView)
        testView.setNeedsLayout()

        await assertAllClear("Should settle after pending layout flushes")

        testView.removeFromSuperview()
    }

    // MARK: - waitForSettle

    func testWaitForSettleResolvesWhenIdle() async {
        await assertSettles("Idle UI should settle")
    }

    func testWaitForSettleTimesOutDuringAnimation() async {
        let windows = tripwire.captureTraversableWindows()
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
        await assertSettles("Idle UI should settle with custom quiet frames", requiredQuietFrames: 4)
    }

    func testMultipleConcurrentSettleWaiters() async {
        // Two waiters should both resolve when the UI is idle
        let tripwire = self.tripwire!
        async let settle1 = tripwire.waitForSettle(timeout: 2.0)
        async let settle2 = tripwire.waitForSettle(timeout: 2.0)

        let (result1, result2) = await (settle1, settle2)
        XCTAssertTrue(result1, "First waiter should settle; \(latestPulseDiagnostic())")
        XCTAssertTrue(result2, "Second waiter should settle; \(latestPulseDiagnostic())")
    }

    func testCancelledSettleWaiterIsRemoved() async throws {
        let tripwire = self.tripwire!
        let windows = tripwire.captureTraversableWindows()
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

        let settleTask = Task { @MainActor in
            await tripwire.waitForSettle(timeout: 10.0, requiredQuietFrames: 1_000)
        }

        for _ in 0..<20 {
            if tripwire.runningContext?.settleWaiters.isEmpty == false {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(tripwire.runningContext?.settleWaiters.count, 1)

        settleTask.cancel()
        let settled = await settleTask.value

        XCTAssertFalse(settled, "Cancelled waiter should resolve false")
        XCTAssertEqual(tripwire.runningContext?.settleWaiters.count, 0)

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

    // MARK: - Pulse produces readings

    func testPulseProducesReadingAfterStart() async throws {
        // waitForSettle only returns once the caller-owned pulse has produced
        // a reading — observable signal beats wall-clock sleep.
        // requiredQuietFrames: 1 asks for the first produced reading and keeps
        // the test resilient to host noise.
        let settled = await tripwire.waitForSettle(timeout: 1.0, requiredQuietFrames: 1)
        XCTAssertTrue(settled, "Pulse should settle within timeout; \(latestPulseDiagnostic())")
        let reading = try XCTUnwrap(tripwire.latestReading)
        XCTAssertGreaterThan(reading.tick, 0)
    }

    func testPulseReadingHasValidWindowCount() async throws {
        let settled = await tripwire.waitForSettle(timeout: 1.0, requiredQuietFrames: 1)
        XCTAssertTrue(settled, "Pulse should settle within timeout; \(latestPulseDiagnostic())")
        let reading = try XCTUnwrap(tripwire.latestReading, "No reading produced")
        XCTAssertGreaterThan(reading.windowCount, 0)
    }

    func testPulseReadingTracksVCIdentity() async throws {
        let settled = await tripwire.waitForSettle(timeout: 1.0, requiredQuietFrames: 1)
        XCTAssertTrue(settled, "Pulse should settle within timeout; \(latestPulseDiagnostic())")
        let reading = try XCTUnwrap(tripwire.latestReading, "No reading produced")
        // Test host should have a VC
        XCTAssertNotNil(reading.topmostVC)
    }

    // MARK: - Fingerprint divergence during animation

    func testFingerprintDivergesDuringAnimation() {
        let windows = tripwire.captureTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testLayer = CALayer()
        testLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        window.layer.addSublayer(testLayer)
        CATransaction.flush()

        let baseline = tripwire.scanLayers().fingerprint

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0
        animation.toValue = 1000
        animation.duration = 10.0
        testLayer.add(animation, forKey: "bigMove")

        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        let during = tripwire.scanLayers().fingerprint
        XCTAssertFalse(
            baseline.matches(during),
            "Fingerprint should differ while a large animation is in flight"
        )

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

    private func assertAllClear(
        _ message: String,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let settled = await tripwire.waitForAllClear(timeout: timeout)
        XCTAssertTrue(settled, "\(message); \(latestPulseDiagnostic())", file: file, line: line)
    }

    private func assertSettles(
        _ message: String,
        timeout: TimeInterval = 2.0,
        requiredQuietFrames: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let settled = await tripwire.waitForSettle(
            timeout: timeout,
            requiredQuietFrames: requiredQuietFrames
        )
        XCTAssertTrue(settled, "\(message); \(latestPulseDiagnostic())", file: file, line: line)
    }

    private func latestPulseDiagnostic() -> String {
        guard let reading = tripwire.latestReading else {
            return "pulseRunning=\(tripwire.isPulseRunning) latestReading=nil"
        }
        return [
            "pulseRunning=\(tripwire.isPulseRunning)",
            "tick=\(reading.tick)",
            "layoutPending=\(reading.layoutPending)",
            "hasRelevantAnimations=\(reading.hasRelevantAnimations)",
            "quietFrames=\(reading.quietFrames)",
            "windowCount=\(reading.windowCount)",
            "topmostVC=\(String(describing: reading.topmostVC))",
            "fingerprint=\(fingerprintDescription(reading.fingerprint))",
        ].joined(separator: " ")
    }

    private func fingerprintDescription(
        _ fingerprint: TheTripwire.PresentationFingerprint
    ) -> String {
        "layers=\(fingerprint.layerCount) minX=\(fingerprint.frameMinXSum) "
            + "minY=\(fingerprint.frameMinYSum) width=\(fingerprint.frameWidthSum) "
            + "height=\(fingerprint.frameHeightSum)"
    }

}

#endif // canImport(UIKit)
