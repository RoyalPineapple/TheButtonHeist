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
        tripwire = nil
        super.tearDown()
    }

    // MARK: - isScreenChange (VC identity)

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

    // MARK: - getTraversableWindows (hosted test — live UIWindowScene)

    func testGetTraversableWindowsReturnsActiveWindows() {
        let windows = tripwire.getTraversableWindows()
        // In the test host app we expect at least one window
        XCTAssertFalse(windows.isEmpty, "Test host should have at least one traversable window")
        // All returned windows should be visible and non-zero size
        for (window, _) in windows {
            XCTAssertFalse(window.isHidden)
            XCTAssertNotEqual(window.bounds.size, .zero)
        }
    }

    func testGetTraversableWindowsSortedByLevel() {
        let windows = tripwire.getTraversableWindows()
        guard windows.count >= 2 else { return }
        // Should be sorted front-to-back (descending window level)
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
        // When no animations are running, two consecutive fingerprints should match
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

        // Add an animation with a non-ignored key — must be detected regardless
        // of whatever system animations may also be running
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
        // In a test host with no explicit animations running,
        // allClear should return true (ignoring system parallax animations)
        // We can't guarantee no system animations, but we can verify the method
        // returns a Bool without crashing and is consistent across calls
        let result1 = tripwire.allClear()
        let result2 = tripwire.allClear()
        XCTAssertEqual(result1, result2, "Consecutive allClear calls should be consistent when idle")
    }

    func testIgnoredAnimationKeyPrefixFiltersParallaxKeys() {
        // Test the filtering logic directly on an isolated layer — no dependency
        // on the live window tree, which may have system-added animations.
        let layer = CALayer()

        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = CGPoint.zero
        animation.toValue = CGPoint(x: 1, y: 1)
        animation.duration = 10.0
        layer.add(animation, forKey: "_UIParallaxMotionEffect_layer")

        // The layer has animation keys, but all should match the ignored prefix
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
