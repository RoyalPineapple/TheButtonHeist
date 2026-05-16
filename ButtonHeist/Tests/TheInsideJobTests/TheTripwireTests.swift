#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheTripwireTests: XCTestCase {

    private var tripwire: TheTripwire!

    override func setUp() async throws {
        tripwire = TheTripwire()
    }

    override func tearDown() async throws {
        tripwire.stopPulse()
        tripwire = nil
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

        let testLayer = CALayer()
        testLayer.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        window.layer.addSublayer(testLayer)

        // Drain all pending layout from adding the sublayer
        for _ in 0..<3 {
            window.layoutIfNeeded()
            CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }

        // Verify baseline is clean before testing setNeedsDisplay
        let baseline = tripwire.hasPendingLayout()
        guard !baseline else {
            testLayer.removeFromSuperlayer()
            XCTFail("Baseline has pending layout — cannot isolate setNeedsDisplay effect")
            return
        }

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

    // MARK: - filterToAccessibleWindows (pure window band)

    /// View controller stub that lets a test choose what
    /// `presentedViewController` returns — bypasses UIKit's real
    /// presentation lifecycle, which can't be driven synchronously
    /// from a unit test without an attached window.
    private final class StubViewController: UIViewController {
        var fakePresented: UIViewController?
        override var presentedViewController: UIViewController? { fakePresented }
    }

    private final class AlwaysKeyWindow: UIWindow {
        override var isKeyWindow: Bool { true }
    }

    /// Build a UIWindow on the active scene without making it visible —
    /// callers pass the window directly into `filterToAccessibleWindows`,
    /// so it never appears in the test host's `getTraversableWindows()`.
    private func makeWindow(level: UIWindow.Level, rootVC: UIViewController? = nil) -> UIWindow {
        makeWindow(level: level, rootVC: rootVC, type: UIWindow.self)
    }

    private func makeWindow<Window: UIWindow>(
        level: UIWindow.Level,
        rootVC: UIViewController? = nil,
        type: Window.Type
    ) -> Window {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return Window()
        }
        let window = Window(windowScene: scene)
        window.windowLevel = level
        window.frame = UIScreen.main.bounds
        window.rootViewController = rootVC
        return window
    }

    func testFilterToAccessibleWindowsEmptyInputReturnsEmpty() {
        let result = TheTripwire.filterToAccessibleWindows([])
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterToAccessibleWindowsReturnsSingleAppWindowWhenNoOverlaysExist() {
        let appWindow = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [(window: appWindow, rootView: appWindow as UIView)]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === appWindow)
    }

    func testFilterToAccessibleWindowsIncludesAlertLevelNonModalWindowAndBaseWindow() {
        let alertLevelWindow = makeWindow(level: .alert, rootVC: UIViewController())
        let base = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            (window: alertLevelWindow, rootView: alertLevelWindow as UIView),
            (window: base, rootView: base as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].window === alertLevelWindow)
        XCTAssertTrue(result[1].window === base)
    }

    func testFilterToAccessibleWindowsIncludesElevatedWindowWithoutRootVC() {
        let overlay = makeWindow(level: .alert, rootVC: nil)
        let base = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            (window: overlay, rootView: overlay as UIView),
            (window: base, rootView: base as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].window === overlay)
        XCTAssertTrue(result[1].window === base)
    }

    func testFilterToAccessibleWindowsPicksDeepestPresentedView() {
        let root = StubViewController()
        let mid = StubViewController()
        let deepest = StubViewController()
        root.fakePresented = mid
        mid.fakePresented = deepest

        let window = makeWindow(level: .normal, rootVC: root)

        let input = [(window: window, rootView: window as UIView)]
        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === window)
        XCTAssertTrue(result.first?.rootView === deepest.view, "Should return deepest presented VC's view")
    }

    func testFilterToAccessibleWindowsIncludesLowerAppWindows() {
        let a = makeWindow(level: .normal, rootVC: UIViewController())
        let b = makeWindow(level: .normal - 1, rootVC: UIViewController())
        let input = [
            (window: a, rootView: a as UIView),
            (window: b, rootView: b as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 2, "All app windows should be returned")
    }

    func testFilterToAccessibleWindowsKeepsMultipleOverlaysAndLowerWindows() {
        let overlayA = makeWindow(level: UIWindow.Level(rawValue: 2000), rootVC: UIViewController())
        let overlayB = makeWindow(level: UIWindow.Level(rawValue: 1999), rootVC: UIViewController())
        let appWindow = makeWindow(level: .normal, rootVC: UIViewController())
        let lower = makeWindow(level: .normal - 1, rootVC: UIViewController())

        let input = [
            (window: overlayA, rootView: overlayA as UIView),
            (window: overlayB, rootView: overlayB as UIView),
            (window: appWindow, rootView: appWindow as UIView),
            (window: lower, rootView: lower as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result[0].window === overlayA)
        XCTAssertTrue(result[1].window === overlayB)
        XCTAssertTrue(result[2].window === appWindow)
        XCTAssertTrue(result[3].window === lower)
    }

    func testFilterToAccessibleWindowsKeepsOverlayAppWindowAndLowerWindows() {
        let overlay = makeWindow(level: .alert, rootVC: UIViewController())
        let appWindow = makeWindow(level: .normal, rootVC: UIViewController())
        let lower = makeWindow(level: .normal - 1, rootVC: UIViewController())

        let input = [
            (window: overlay, rootView: overlay as UIView),
            (window: appWindow, rootView: appWindow as UIView),
            (window: lower, rootView: lower as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].window === overlay)
        XCTAssertTrue(result[1].window === appWindow)
        XCTAssertTrue(result[2].window === lower)
    }

    func testFilterToAccessibleWindowsDoesNotStopAtElevatedKeyWindow() {
        let cardReader = makeWindow(
            level: UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1),
            rootVC: UIViewController(),
            type: AlwaysKeyWindow.self
        )
        cardReader.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let appWindow = makeWindow(level: .normal, rootVC: UIViewController())

        let input = [
            (window: cardReader as UIWindow, rootView: cardReader as UIView),
            (window: appWindow, rootView: appWindow as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertTrue(cardReader.isKeyWindow)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].window === cardReader)
        XCTAssertTrue(result[1].window === appWindow)
    }

    func testFilterToAccessibleWindowsDropsPassthroughAndKeepsAppWindows() {
        let keyboard = makeWindow(level: .statusBar, rootVC: UIViewController())
        let overlay = makeWindow(level: .alert, rootVC: UIViewController())
        let appWindow = makeWindow(level: .normal, rootVC: UIViewController())
        let lower = makeWindow(level: .normal - 1, rootVC: UIViewController())

        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: overlay, rootView: overlay as UIView),
            (window: appWindow, rootView: appWindow as UIView),
            (window: lower, rootView: lower as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertFalse(result.contains(where: { $0.window === keyboard }))
        XCTAssertTrue(result[0].window === overlay)
        XCTAssertTrue(result[1].window === appWindow)
        XCTAssertTrue(result[2].window === lower)
    }

    func testFilterToAccessibleWindowsIncludesOverlayAndPresentedBaseWindow() {
        let baseRoot = StubViewController()
        let presented = UIViewController()
        baseRoot.fakePresented = presented
        let baseWindow = makeWindow(level: .normal, rootVC: baseRoot)

        let overlay = makeWindow(level: .alert, rootVC: UIViewController())

        let input = [
            (window: overlay, rootView: overlay as UIView),
            (window: baseWindow, rootView: baseWindow as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].window === overlay)
        XCTAssertTrue(result[1].window === baseWindow)
        XCTAssertTrue(result[1].rootView === presented.view)
    }

    // MARK: - System Passthrough Windows (keyboard / text-effects)

    func testFilterDropsPassthroughAndKeepsAppWindow() {
        // Frontmost window is a system passthrough (keyboard) above .normal —
        // it must NOT be treated as the overlay. The base app window beneath
        // should remain accessible so the focused text field and surrounding
        // content stay in the tree while the keyboard is up.
        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let appWindow = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: appWindow, rootView: appWindow as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertEqual(result.count, 1, "Should fall through to app window")
        XCTAssertTrue(result.first?.window === appWindow,
                      "App window should be returned, not the passthrough keyboard")
    }

    func testFilterIncludesNonModalOverlayBeneathPassthrough() {
        // A passthrough keyboard is still excluded, but an elevated non-modal
        // app window beneath it remains additive with the base app window.
        let keyboard = makeWindow(level: .statusBar, rootVC: UIViewController())
        let overlay = makeWindow(level: .alert, rootVC: UIViewController())
        let base = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: overlay, rootView: overlay as UIView),
            (window: base, rootView: base as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains(where: { $0.window === keyboard }))
        XCTAssertTrue(result[0].window === overlay)
        XCTAssertTrue(result[1].window === base)
    }

    func testFilterFindsPresentedVCBeneathPassthrough() {
        // Keyboard above an app window whose root VC has a presented VC.
        // After skipping the keyboard, the app window should be parsed from
        // its deepest presented VC.
        let root = StubViewController()
        let presented = StubViewController()
        root.fakePresented = presented

        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let appWindow = makeWindow(level: .normal, rootVC: root)
        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: appWindow, rootView: appWindow as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === appWindow)
        XCTAssertTrue(result.first?.rootView === presented.view,
                      "Should return deepest presented VC's view, not the keyboard")
    }

    func testFilterFallbackExcludesPassthroughWindows() {
        // No overlay, no presented VC, two app-level windows plus a keyboard.
        // The fallback should return the two app windows and drop the keyboard.
        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let a = makeWindow(level: .normal, rootVC: UIViewController())
        let b = makeWindow(level: .normal - 1, rootVC: UIViewController())
        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: a, rootView: a as UIView),
            (window: b, rootView: b as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertEqual(result.count, 2, "Fallback should return only app windows")
        XCTAssertFalse(result.contains(where: { $0.window === keyboard }),
                       "Passthrough window must not be in fallback result")
    }

    func testFilterReturnsAllWhenOnlyPassthroughsExist() {
        // When every window is a passthrough, the canonical behaviour is to
        // return the full input rather than an empty list — better to
        // over-include than starve the parser of any windows at all.
        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let textEffects = makeWindow(level: .alert + 1, rootVC: UIViewController())
        let input = [
            (window: textEffects, rootView: textEffects as UIView),
            (window: keyboard, rootView: keyboard as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { _ in true }
        )

        XCTAssertEqual(result.count, 2,
                       "All-passthrough input should fall back to original list, not empty")
    }

    // MARK: - topmostViewController(in:) Passthrough

    func testTopmostViewControllerSkipsPassthroughWindow() {
        // Frontmost window is a system passthrough — its rootVC must not be
        // chosen as the topmost VC, otherwise a keyboard appearance would
        // trigger unnecessary parse work.
        let keyboardVC = UIViewController()
        let appVC = UIViewController()
        let keyboard = makeWindow(level: .alert, rootVC: keyboardVC)
        let appWindow = makeWindow(level: .normal, rootVC: appVC)
        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: appWindow, rootView: appWindow as UIView),
        ]

        let result = TheTripwire.topmostViewController(
            in: input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertTrue(result === appVC,
                      "Should return the app window's rootVC, not the keyboard's")
    }

    func testTopmostViewControllerWalksPresentedChainBeneathPassthrough() {
        // After skipping the keyboard, the deepest presented VC of the next
        // app window should be returned — the same recursion as without a
        // passthrough in front.
        let root = StubViewController()
        let presented = StubViewController()
        root.fakePresented = presented

        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let appWindow = makeWindow(level: .normal, rootVC: root)
        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: appWindow, rootView: appWindow as UIView),
        ]

        let result = TheTripwire.topmostViewController(
            in: input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertTrue(result === presented,
                      "Should walk the presentation chain past the passthrough")
    }

    func testTopmostViewControllerReturnsNilWhenOnlyPassthroughExists() {
        // No app windows at all — return nil rather than picking the keyboard.
        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let input = [(window: keyboard, rootView: keyboard as UIView)]

        let result = TheTripwire.topmostViewController(
            in: input,
            isPassthrough: { _ in true }
        )

        XCTAssertNil(result, "Only passthrough windows present — no topmost VC")
    }

    func testKeyboardAppearanceAndDisappearanceKeepSameTopmostViewController() {
        // A software keyboard sliding in or out over the current screen
        // should not hide the app's topmost controller from the Tripwire
        // signal.
        let appVC = UIViewController()
        let appWindow = makeWindow(level: .normal, rootVC: appVC)
        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let isKeyboard: (UIWindow) -> Bool = { $0 === keyboard }

        let appOnly = [(window: appWindow, rootView: appWindow as UIView)]
        let withKeyboard = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: appWindow, rootView: appWindow as UIView),
        ]

        let phases: [(label: String, windows: [(window: UIWindow, rootView: UIView)])] = [
            ("before keyboard", appOnly),
            ("keyboard up", withKeyboard),
            ("keyboard dismissed", appOnly),
        ]

        for phase in phases {
            let vc = TheTripwire.topmostViewController(in: phase.windows, isPassthrough: isKeyboard)
            XCTAssertTrue(vc === appVC,
                          "Topmost VC must remain the app VC across phase '\(phase.label)'")
        }
    }

}

#endif // canImport(UIKit)
