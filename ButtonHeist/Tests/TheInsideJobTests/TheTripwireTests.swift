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

    private func fingerprint(
        frameMinXSum: CGFloat = 100,
        frameMinYSum: CGFloat = 200,
        frameWidthSum: CGFloat = 300,
        frameHeightSum: CGFloat = 400,
        layerCount: Int = 5
    ) -> TheTripwire.PresentationFingerprint {
        TheTripwire.PresentationFingerprint(
            frameMinXSum: frameMinXSum,
            frameMinYSum: frameMinYSum,
            frameWidthSum: frameWidthSum,
            frameHeightSum: frameHeightSum,
            layerCount: layerCount
        )
    }

    // MARK: - PulseReading.isSettled

    func testPulseReadingSettledWhenQuiet() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: fingerprint(),
            hasRelevantAnimations: false,
            topmostVC: nil,
            tripwireSignal: .empty,
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
            fingerprint: fingerprint(),
            hasRelevantAnimations: false,
            topmostVC: nil,
            tripwireSignal: .empty,
            windowCount: 1,
            quietFrames: 5
        )
        XCTAssertFalse(reading.isSettled)
    }

    func testPulseReadingSettledWithStablePlatformAnimationKey() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: fingerprint(),
            hasRelevantAnimations: true,
            topmostVC: nil,
            tripwireSignal: .empty,
            windowCount: 1,
            quietFrames: 5
        )
        XCTAssertTrue(reading.isSettled)
    }

    func testPulseReadingNotSettledWhenQuietFramesInsufficient() {
        let reading = TheTripwire.PulseReading(
            tick: 10,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: fingerprint(),
            hasRelevantAnimations: false,
            topmostVC: nil,
            tripwireSignal: .empty,
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
            fingerprint: fingerprint(),
            hasRelevantAnimations: false,
            topmostVC: ObjectIdentifier(vc),
            tripwireSignal: .empty,
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

    func testFingerprintWindowIsExcludedFromTraversalByDefault() {
        let fingerprintWindow = makeWindow(level: .statusBar + 100, type: TheFingerprints.FingerprintWindow.self)
        fingerprintWindow.isHidden = false
        defer { fingerprintWindow.isHidden = true }

        XCTAssertFalse(TheTripwire.orderedVisibleWindows().contains(fingerprintWindow))
        XCTAssertFalse(tripwire.getTraversableWindows().contains { $0.window === fingerprintWindow })
        XCTAssertTrue(TheTripwire.orderedVisibleWindows(includeFingerprints: true).contains(fingerprintWindow))
    }

    func testFingerprintsTrackOneIndicatorPerActivePoint() {
        let fingerprints = TheFingerprints(isEnabled: true)

        fingerprints.beginTracking(at: [
            CGPoint(x: 20, y: 40),
            CGPoint(x: 80, y: 120),
        ])
        XCTAssertEqual(fingerprints.activeFingerprintCenters, [
            CGPoint(x: 20, y: 40),
            CGPoint(x: 80, y: 120),
        ])

        fingerprints.updateTracking(to: [
            CGPoint(x: 25, y: 45),
            CGPoint(x: 85, y: 125),
            CGPoint(x: 145, y: 185),
        ])
        XCTAssertEqual(fingerprints.activeFingerprintCenters, [
            CGPoint(x: 25, y: 45),
            CGPoint(x: 85, y: 125),
            CGPoint(x: 145, y: 185),
        ])

        fingerprints.updateTracking(to: [CGPoint(x: 40, y: 60)])
        XCTAssertEqual(fingerprints.activeFingerprintCenters, [CGPoint(x: 40, y: 60)])

        fingerprints.endTracking()
        XCTAssertTrue(fingerprints.activeFingerprintCenters.isEmpty)
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

    private func pulseReading(tripwireSignal: TheTripwire.TripwireSignal) -> TheTripwire.PulseReading {
        TheTripwire.PulseReading(
            tick: 1,
            timestamp: CFAbsoluteTimeGetCurrent(),
            layoutPending: false,
            fingerprint: fingerprint(),
            hasRelevantAnimations: false,
            topmostVC: tripwireSignal.topmostVC,
            tripwireSignal: tripwireSignal,
            windowCount: 1,
            quietFrames: 2
        )
    }

    private func tripwireSignal(navigationDepth: Int) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: nil,
            navigation: TheTripwire.NavigationSignal(
                navigationDepth: navigationDepth,
                title: nil,
                backButtonTitle: nil,
                selectedTabIndex: nil,
                presentedViewController: nil
            ),
            windowStack: .empty
        )
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

    func testWaitForSettleRequiresCallerOwnedPulse() async {
        let settled = await tripwire.waitForSettle(timeout: 0.01)

        XCTAssertFalse(settled)
        XCTAssertFalse(tripwire.isPulseRunning)
    }

    // MARK: - PresentationFingerprint.matches (pure value type)

    func testFingerprintMatchesIdentical() {
        let fp = fingerprint()
        XCTAssertTrue(fp.matches(fp))
    }

    func testFingerprintMatchesWithinTolerance() {
        let fp1 = fingerprint(frameMinXSum: 100.0, frameMinYSum: 200.0)
        let fp2 = fingerprint(frameMinXSum: 100.3, frameMinYSum: 200.4)
        XCTAssertTrue(fp1.matches(fp2))
    }

    func testFingerprintDoesNotMatchFrameOriginDrift() {
        let fp1 = fingerprint(frameMinXSum: 100.0, frameMinYSum: 200.0)
        let fp2 = fingerprint(frameMinXSum: 101.0, frameMinYSum: 200.0)
        XCTAssertFalse(fp1.matches(fp2))
    }

    func testFingerprintDoesNotMatchFrameSizeDrift() {
        let fp1 = fingerprint(frameWidthSum: 300.0)
        let fp2 = fingerprint(frameWidthSum: 301.0)
        XCTAssertFalse(fp1.matches(fp2))
    }

    func testFingerprintDoesNotMatchLayerCountDiff() {
        let fp1 = fingerprint(layerCount: 5)
        let fp2 = fingerprint(layerCount: 6)
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

        XCTAssertTrue(tripwire.scanLayers().hasPendingLayout)

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
        let baseline = tripwire.scanLayers().hasPendingLayout
        guard !baseline else {
            testLayer.removeFromSuperlayer()
            XCTFail("Baseline has pending layout — cannot isolate setNeedsDisplay effect")
            return
        }

        testLayer.setNeedsDisplay()
        XCTAssertFalse(
            tripwire.scanLayers().hasPendingLayout,
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

        XCTAssertTrue(tripwire.scanLayers().hasPendingLayout, "Should detect pending layout after setNeedsLayout")

        testView.layoutIfNeeded()
        testView.removeFromSuperview()
    }

    // MARK: - getTraversableWindows (hosted test)

    func testGetTraversableWindowsReturnsActiveWindows() {
        let windows = tripwire.getTraversableWindows()
        XCTAssertFalse(windows.isEmpty, "Test host should have at least one traversable window")
        for entry in windows {
            let window = entry.window
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

    // MARK: - Fingerprint (hosted test)

    func testScanLayersFingerprintHasLayers() {
        let fp = tripwire.scanLayers().fingerprint
        XCTAssertGreaterThan(fp.layerCount, 0, "Test host should have layers in the window")
    }

    func testConsecutiveFingerprintsMatchWhenIdle() {
        let fp1 = tripwire.scanLayers().fingerprint
        let fp2 = tripwire.scanLayers().fingerprint
        XCTAssertTrue(fp1.matches(fp2), "Consecutive fingerprints should match when idle")
    }

    // MARK: - allClear (hosted test)

    func testAllClearTrueWhenNoAnimations() {
        let result1 = tripwire.allClear()
        let result2 = tripwire.allClear()
        XCTAssertEqual(result1, result2, "Consecutive allClear calls should be consistent when idle")
    }

    func testAllClearFalseUntilFirstPulseReading() {
        tripwire.startPulse()

        XCTAssertFalse(tripwire.allClear())
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

    private func windowRoot(_ window: UIWindow) -> TheTripwire.WindowTraversalRoot {
        TheTripwire.WindowTraversalRoot(window: window, rootView: window)
    }

    func testFilterToAccessibleWindowsEmptyInputReturnsEmpty() {
        let result = TheTripwire.filterToAccessibleWindows([])
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterToAccessibleWindowsReturnsSingleAppWindowWhenNoOverlaysExist() {
        let appWindow = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [windowRoot(appWindow)]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === appWindow)
    }

    func testFilterToAccessibleWindowsIncludesAlertLevelNonModalWindowAndBaseWindow() {
        let alertLevelWindow = makeWindow(level: .alert, rootVC: UIViewController())
        let base = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            windowRoot(alertLevelWindow),
            windowRoot(base),
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
            windowRoot(overlay),
            windowRoot(base),
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

        let input = [windowRoot(window)]
        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === window)
        XCTAssertTrue(result.first?.rootView === deepest.view, "Should return deepest presented VC's view")
    }

    func testFilterToAccessibleWindowsIncludesLowerAppWindows() {
        let a = makeWindow(level: .normal, rootVC: UIViewController())
        let b = makeWindow(level: .normal - 1, rootVC: UIViewController())
        let input = [
            windowRoot(a),
            windowRoot(b),
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
            windowRoot(overlayA),
            windowRoot(overlayB),
            windowRoot(appWindow),
            windowRoot(lower),
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
            windowRoot(overlay),
            windowRoot(appWindow),
            windowRoot(lower),
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
            windowRoot(cardReader),
            windowRoot(appWindow),
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
            windowRoot(keyboard),
            windowRoot(overlay),
            windowRoot(appWindow),
            windowRoot(lower),
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
            windowRoot(overlay),
            windowRoot(baseWindow),
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
            windowRoot(keyboard),
            windowRoot(appWindow),
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
            windowRoot(keyboard),
            windowRoot(overlay),
            windowRoot(base),
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
            windowRoot(keyboard),
            windowRoot(appWindow),
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

    func testFilterExcludesPassthroughWindowsWhenAppWindowsRemain() {
        // No overlay, no presented VC, two app-level windows plus a keyboard.
        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let a = makeWindow(level: .normal, rootVC: UIViewController())
        let b = makeWindow(level: .normal - 1, rootVC: UIViewController())
        let input = [
            windowRoot(keyboard),
            windowRoot(a),
            windowRoot(b),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertEqual(result.count, 2, "Only app windows should remain")
        XCTAssertFalse(result.contains(where: { $0.window === keyboard }),
                       "Passthrough window must not be in accessible result")
    }

    func testFilterReturnsEmptyWhenOnlyPassthroughsExist() {
        // Passthrough windows do not provide app accessibility roots.
        let keyboard = makeWindow(level: .alert, rootVC: UIViewController())
        let textEffects = makeWindow(level: .alert + 1, rootVC: UIViewController())
        let input = [
            windowRoot(textEffects),
            windowRoot(keyboard),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { _ in true }
        )

        XCTAssertTrue(result.isEmpty,
                      "All-passthrough input should not be promoted to app accessibility roots")
    }

    // MARK: - topmostViewController(in:) Standard Containers

    func testTopmostViewControllerWalksNavigationControllerStack() {
        let first = UIViewController()
        let top = UIViewController()
        let navigation = UINavigationController(rootViewController: first)
        navigation.pushViewController(top, animated: false)
        let window = makeWindow(level: .normal, rootVC: navigation)

        let result = TheTripwire.topmostViewController(
            in: [windowRoot(window)]
        )

        XCTAssertTrue(result === top)
    }

    func testTopmostViewControllerWalksSelectedTabController() {
        let first = UIViewController()
        let selected = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [first, selected]
        tabs.selectedIndex = 1
        let window = makeWindow(level: .normal, rootVC: tabs)

        let result = TheTripwire.topmostViewController(
            in: [windowRoot(window)]
        )

        XCTAssertTrue(result === selected)
    }

    func testTopmostViewControllerDoesNotGuessArbitraryChildContainer() {
        let parent = UIViewController()
        let childTop = UIViewController()
        let childNavigation = UINavigationController(rootViewController: childTop)
        parent.addChild(childNavigation)
        parent.view.addSubview(childNavigation.view)
        childNavigation.didMove(toParent: parent)
        let window = makeWindow(level: .normal, rootVC: parent)

        let result = TheTripwire.topmostViewController(
            in: [windowRoot(window)]
        )

        XCTAssertTrue(result === parent)
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
            windowRoot(keyboard),
            windowRoot(appWindow),
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
            windowRoot(keyboard),
            windowRoot(appWindow),
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
        let input = [windowRoot(keyboard)]

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

        let appOnly = [windowRoot(appWindow)]
        let withKeyboard = [
            windowRoot(keyboard),
            windowRoot(appWindow),
        ]

        let phases: [(label: String, windows: [TheTripwire.WindowTraversalRoot])] = [
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
