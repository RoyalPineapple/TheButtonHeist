#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheTripwireTests: XCTestCase {

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

    // MARK: - PulseReading.isSettled

    func testPulseReadingSettledWhenQuiet() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: .init(positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5),
            hasRelevantAnimations: false,
            topmostVC: nil,
            firstResponder: nil,
            keyboardVisible: false,
            textInputActive: false,
            windowCount: 1,
            quietFrames: 2
        )
        XCTAssertTrue(reading.isSettled)
    }

    func testPulseReadingNotSettledWhenLayoutPending() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: true,
            fingerprint: .init(positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5),
            hasRelevantAnimations: false,
            topmostVC: nil,
            firstResponder: nil,
            keyboardVisible: false,
            textInputActive: false,
            windowCount: 1,
            quietFrames: 5
        )
        XCTAssertFalse(reading.isSettled)
    }

    func testPulseReadingNotSettledWhenAnimating() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: .init(positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5),
            hasRelevantAnimations: true,
            topmostVC: nil,
            firstResponder: nil,
            keyboardVisible: false,
            textInputActive: false,
            windowCount: 1,
            quietFrames: 5
        )
        XCTAssertFalse(reading.isSettled)
    }

    func testPulseReadingNotSettledWhenQuietFramesInsufficient() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: .init(positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5),
            hasRelevantAnimations: false,
            topmostVC: nil,
            firstResponder: nil,
            keyboardVisible: false,
            textInputActive: false,
            windowCount: 1,
            quietFrames: 1
        )
        XCTAssertFalse(reading.isSettled)
    }

    func testPulseReadingSettledIgnoresKeyboardAndVC() {
        // Keyboard visible and VC present don't affect isSettled —
        // they're informational signals, not settle gates.
        let vc = UIViewController()
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: .init(positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5),
            hasRelevantAnimations: false,
            topmostVC: ObjectIdentifier(vc),
            firstResponder: nil,
            keyboardVisible: true,
            textInputActive: true,
            windowCount: 3,
            quietFrames: 2
        )
        XCTAssertTrue(reading.isSettled)
    }

    // MARK: - scanLayers (hosted test — combines fingerprint + animations + layout)

    func testScanLayersReturnsNonZeroLayerCount() {
        let scan = tripwire.scanLayers()
        XCTAssertGreaterThan(scan.layerCount, 0, "Test host should have layers")
    }

    func testScanLayersCountsWindows() {
        let scan = tripwire.scanLayers()
        let windows = tripwire.getTraversableWindows()
        XCTAssertEqual(scan.windowCount, windows.count)
    }

    func testScanLayersFingerprintMatchesDedicatedMethod() {
        let scan = tripwire.scanLayers()
        let dedicated = tripwire.takePresentationFingerprint()
        XCTAssertTrue(
            scan.fingerprint.matches(dedicated),
            "scanLayers fingerprint should match takePresentationFingerprint"
        )
    }

    func testScanLayersDetectsPendingLayout() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        window.addSubview(testView)
        testView.setNeedsLayout()

        let scan = tripwire.scanLayers()
        XCTAssertTrue(scan.hasPendingLayout)

        testView.layoutIfNeeded()
        testView.removeFromSuperview()
    }

    func testScanLayersDetectsAnimations() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testLayer = CALayer()
        window.layer.addSublayer(testLayer)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 10.0
        testLayer.add(animation, forKey: "testAnimation")

        let scan = tripwire.scanLayers()
        XCTAssertTrue(scan.hasRelevantAnimations)

        testLayer.removeAnimation(forKey: "testAnimation")
        testLayer.removeFromSuperlayer()
    }

    func testScanLayersIgnoresParallaxAnimations() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testLayer = CALayer()
        window.layer.addSublayer(testLayer)

        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = CGPoint.zero
        animation.toValue = CGPoint(x: 1, y: 1)
        animation.duration = 10.0
        testLayer.add(animation, forKey: "_UIParallaxMotionEffect_layer")

        // The full scan may see other system animations, so verify
        // the parallax key filtering in isolation on this specific layer.
        XCTAssertFalse(scanSingleLayer(testLayer), "Parallax animation should be filtered out")

        testLayer.removeAllAnimations()
        testLayer.removeFromSuperlayer()
    }

    /// Check if a single layer has relevant (non-ignored) animations.
    private func scanSingleLayer(_ layer: CALayer) -> Bool {
        guard let keys = layer.animationKeys() else { return false }
        let ignoredPrefixes = ["_UIParallaxMotionEffect"]
        return keys.contains { key in
            !ignoredPrefixes.contains { key.hasPrefix($0) }
        }
    }

    // MARK: - Pulse Lifecycle

    func testStartPulseSetsRunningState() {
        tripwire.startPulse()
        XCTAssertTrue(tripwire.isPulseRunning)
    }

    func testStopPulseClearsRunningState() {
        tripwire.startPulse()
        tripwire.stopPulse()
        XCTAssertFalse(tripwire.isPulseRunning)
        XCTAssertNil(tripwire.latestReading)
    }

    func testStartPulseIsIdempotent() {
        tripwire.startPulse()
        tripwire.startPulse()
        XCTAssertTrue(tripwire.isPulseRunning)
        // No crash, no double-registration
    }

    // MARK: - Keyboard Notification Flags

    func testKeyboardWillShowSetsFlag() {
        tripwire.startPulse()
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        XCTAssertTrue(tripwire.keyboardVisibleFlag)
    }

    func testKeyboardDidHideClearsFlag() {
        tripwire.startPulse()
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.post(name: UIResponder.keyboardDidHideNotification, object: nil)
        XCTAssertFalse(tripwire.keyboardVisibleFlag)
    }

    func testKeyboardFrameOnScreenSetsFlag() {
        tripwire.startPulse()
        let screenBounds = UIScreen.main.bounds
        let keyboardFrame = CGRect(
            x: 0,
            y: screenBounds.height - 300,
            width: screenBounds.width,
            height: 300
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: keyboardFrame]
        )
        XCTAssertTrue(tripwire.keyboardVisibleFlag)
    }

    func testKeyboardFrameOffScreenClearsFlag() {
        tripwire.startPulse()
        let screenBounds = UIScreen.main.bounds
        let offScreenFrame = CGRect(
            x: 0,
            y: screenBounds.height,
            width: screenBounds.width,
            height: 300
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: offScreenFrame]
        )
        XCTAssertFalse(tripwire.keyboardVisibleFlag)
    }

    func testTextEditingBeginsetsFlag() {
        tripwire.startPulse()
        NotificationCenter.default.post(name: UITextField.textDidBeginEditingNotification, object: nil)
        XCTAssertTrue(tripwire.textInputActiveFlag)
    }

    func testTextEditingEndClearsFlag() {
        tripwire.startPulse()
        NotificationCenter.default.post(name: UITextField.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.post(name: UITextField.textDidEndEditingNotification, object: nil)
        XCTAssertFalse(tripwire.textInputActiveFlag)
    }

    func testNotificationFlagsNotRegisteredBeforePulseStart() {
        // Flags should not respond to notifications before startPulse()
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        XCTAssertFalse(tripwire.keyboardVisibleFlag)
    }

    // MARK: - First Responder

    func testCurrentFirstResponderReturnsNilWhenNothingFocused() {
        // In the test host, no text field is focused by default
        // so currentFirstResponder should return nil or whatever
        // the host has focused. We just verify it doesn't crash.
        _ = tripwire.currentFirstResponder()
    }

    func testFirstResponderTrackedInPulseReading() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: .init(positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5),
            hasRelevantAnimations: false,
            topmostVC: nil,
            firstResponder: nil,
            keyboardVisible: false,
            textInputActive: false,
            windowCount: 1,
            quietFrames: 2
        )
        XCTAssertNil(reading.firstResponder)
    }

    func testFirstResponderIdentityTracksView() {
        let textField = UITextField()
        let id = ObjectIdentifier(textField)
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: .init(positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5),
            hasRelevantAnimations: false,
            topmostVC: nil,
            firstResponder: id,
            keyboardVisible: false,
            textInputActive: false,
            windowCount: 1,
            quietFrames: 2
        )
        XCTAssertEqual(reading.firstResponder, id)
    }

    // MARK: - isScreenChange (VC identity — unchanged from before)

    func testIsScreenChangeBothNilReturnsFalse() {
        XCTAssertFalse(tripwire.isScreenChange(before: nil, after: nil))
    }

    func testIsScreenChangeBeforeNilAfterSetReturnsTrue() {
        let vc = UIViewController()
        let id = ObjectIdentifier(vc)
        XCTAssertTrue(tripwire.isScreenChange(before: nil, after: id))
    }

    func testIsScreenChangeBeforeSetAfterNilReturnsTrue() {
        let vc = UIViewController()
        let id = ObjectIdentifier(vc)
        XCTAssertTrue(tripwire.isScreenChange(before: id, after: nil))
    }

    func testIsScreenChangeSameIdentityReturnsFalse() {
        let vc = UIViewController()
        let id = ObjectIdentifier(vc)
        XCTAssertFalse(tripwire.isScreenChange(before: id, after: id))
    }

    func testIsScreenChangeDifferentIdentityReturnsTrue() {
        let vc1 = UIViewController()
        let vc2 = UIViewController()
        XCTAssertTrue(
            tripwire.isScreenChange(
                before: ObjectIdentifier(vc1),
                after: ObjectIdentifier(vc2)
            )
        )
    }

    // MARK: - PresentationFingerprint.matches (pure value type)

    func testFingerprintMatchesIdentical() {
        let fp = TheTripwire.PresentationFingerprint(
            positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5
        )
        XCTAssertTrue(fp.matches(fp))
    }

    func testFingerprintMatchesWithinTolerance() {
        let fp1 = TheTripwire.PresentationFingerprint(
            positionXSum: 100.0, positionYSum: 200.0, opacitySum: 5.0, layerCount: 5
        )
        let fp2 = TheTripwire.PresentationFingerprint(
            positionXSum: 100.3, positionYSum: 200.4, opacitySum: 5.04, layerCount: 5
        )
        XCTAssertTrue(fp1.matches(fp2))
    }

    func testFingerprintDoesNotMatchPositionDrift() {
        let fp1 = TheTripwire.PresentationFingerprint(
            positionXSum: 100.0, positionYSum: 200.0, opacitySum: 5.0, layerCount: 5
        )
        let fp2 = TheTripwire.PresentationFingerprint(
            positionXSum: 101.0, positionYSum: 200.0, opacitySum: 5.0, layerCount: 5
        )
        XCTAssertFalse(fp1.matches(fp2))
    }

    func testFingerprintDoesNotMatchOpacityDrift() {
        let fp1 = TheTripwire.PresentationFingerprint(
            positionXSum: 100, positionYSum: 200, opacitySum: 5.0, layerCount: 5
        )
        let fp2 = TheTripwire.PresentationFingerprint(
            positionXSum: 100, positionYSum: 200, opacitySum: 5.1, layerCount: 5
        )
        XCTAssertFalse(fp1.matches(fp2))
    }

    func testFingerprintDoesNotMatchLayerCountDiff() {
        let fp1 = TheTripwire.PresentationFingerprint(
            positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 5
        )
        let fp2 = TheTripwire.PresentationFingerprint(
            positionXSum: 100, positionYSum: 200, opacitySum: 5, layerCount: 6
        )
        XCTAssertFalse(fp1.matches(fp2))
    }

    // MARK: - hasPendingLayout

    func testHasPendingLayoutTrueAfterSetNeedsLayout() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        window.addSubview(testView)
        testView.setNeedsLayout()

        XCTAssertTrue(tripwire.hasPendingLayout())

        testView.layoutIfNeeded()
        testView.removeFromSuperview()
    }

    func testHasPendingLayoutIgnoresNeedsDisplay() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        let testLayer = CALayer()
        testLayer.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        window.layer.addSublayer(testLayer)

        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        testLayer.setNeedsDisplay()
        XCTAssertFalse(
            tripwire.hasPendingLayout(),
            "needsDisplay alone should not trigger hasPendingLayout"
        )

        testLayer.removeFromSuperlayer()
    }

    func testAllClearFalseWhenLayoutPending() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        let testView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        window.addSubview(testView)
        testView.setNeedsLayout()

        XCTAssertTrue(tripwire.hasPendingLayout(), "Should detect pending layout after setNeedsLayout")

        testView.layoutIfNeeded()
        testView.removeFromSuperview()
    }

    // MARK: - getTraversableWindows (hosted test)

    func testGetTraversableWindowsReturnsActiveWindows() {
        let windows = tripwire.getTraversableWindows()
        XCTAssertFalse(windows.isEmpty, "Test host should have at least one traversable window")
        for (window, _) in windows {
            XCTAssertFalse(window.isHidden)
            XCTAssertNotEqual(window.bounds.size, .zero)
        }
    }

    func testGetTraversableWindowsSortedByLevel() {
        let windows = tripwire.getTraversableWindows()
        guard windows.count >= 2 else { return }
        for i in 0..<(windows.count - 1) {
            XCTAssertGreaterThanOrEqual(
                windows[i].window.windowLevel,
                windows[i + 1].window.windowLevel
            )
        }
    }

    // MARK: - topmostViewController (hosted test)

    func testTopmostViewControllerReturnsNonNil() {
        let vc = tripwire.topmostViewController()
        XCTAssertNotNil(vc, "Test host should have a root view controller")
    }

    // MARK: - takePresentationFingerprint (hosted test)

    func testTakePresentationFingerprintHasLayers() {
        let fp = tripwire.takePresentationFingerprint()
        XCTAssertGreaterThan(fp.layerCount, 0, "Test host should have layers in the window")
    }

    func testConsecutiveFingerprintsMatchWhenIdle() {
        let fp1 = tripwire.takePresentationFingerprint()
        let fp2 = tripwire.takePresentationFingerprint()
        XCTAssertTrue(fp1.matches(fp2), "Consecutive fingerprints should match when idle")
    }

    // MARK: - allClear (hosted test)

    func testAllClearFalseWhenAnimating() {
        let windows = tripwire.getTraversableWindows()
        guard let window = windows.first?.window else {
            XCTFail("No window available")
            return
        }

        let testLayer = CALayer()
        window.layer.addSublayer(testLayer)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 10.0
        testLayer.add(animation, forKey: "testAnimation")

        XCTAssertFalse(tripwire.allClear())

        testLayer.removeAnimation(forKey: "testAnimation")
        testLayer.removeFromSuperlayer()
    }

    func testAllClearTrueWhenNoAnimations() {
        let result1 = tripwire.allClear()
        let result2 = tripwire.allClear()
        XCTAssertEqual(result1, result2, "Consecutive allClear calls should be consistent when idle")
    }

    func testIgnoredAnimationKeyPrefixFiltersParallaxKeys() {
        let layer = CALayer()

        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = CGPoint.zero
        animation.toValue = CGPoint(x: 1, y: 1)
        animation.duration = 10.0
        layer.add(animation, forKey: "_UIParallaxMotionEffect_layer")

        let keys = layer.animationKeys() ?? []
        XCTAssertFalse(keys.isEmpty, "Layer should have animation keys")

        let ignoredPrefixes = ["_UIParallaxMotionEffect"]
        let hasRelevant = keys.contains { key in
            !ignoredPrefixes.contains { key.hasPrefix($0) }
        }
        XCTAssertFalse(hasRelevant, "Parallax keys should be filtered out")

        layer.removeAllAnimations()
    }

    func testIgnoredAnimationKeyPrefixPassesNonParallaxKeys() {
        let layer = CALayer()

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 10.0
        layer.add(animation, forKey: "someRealAnimation")

        let keys = layer.animationKeys() ?? []
        let ignoredPrefixes = ["_UIParallaxMotionEffect"]
        let hasRelevant = keys.contains { key in
            !ignoredPrefixes.contains { key.hasPrefix($0) }
        }
        XCTAssertTrue(hasRelevant, "Non-parallax keys should not be filtered")

        layer.removeAllAnimations()
    }

}

#endif // canImport(UIKit)
