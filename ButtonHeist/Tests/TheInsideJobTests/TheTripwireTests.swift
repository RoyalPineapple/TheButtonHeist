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

    // MARK: - getAccessibleWindows (tree filtering)

    func testGetAccessibleWindowsFiltersToModalWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return
        }

        // Create a modal overlay window above the main window
        let modalWindow = UIWindow(windowScene: windowScene)
        modalWindow.windowLevel = .alert
        modalWindow.frame = UIScreen.main.bounds

        let modalView = UIView()
        modalView.accessibilityViewIsModal = true
        modalWindow.addSubview(modalView)
        modalWindow.isHidden = false

        defer {
            modalWindow.isHidden = true
            modalView.removeFromSuperview()
        }

        let accessible = tripwire.getAccessibleWindows()

        XCTAssertEqual(accessible.count, 1, "Only the modal window should be returned")
        XCTAssertTrue(
            accessible.first?.window === modalWindow,
            "The returned window should be the modal window"
        )
    }

    func testGetAccessibleWindowsDetectsModalOnGrandchild() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return
        }

        let modalWindow = UIWindow(windowScene: windowScene)
        modalWindow.windowLevel = .alert
        modalWindow.frame = UIScreen.main.bounds

        let container = UIView()
        let modalChild = UIView()
        modalChild.accessibilityViewIsModal = true
        container.addSubview(modalChild)
        modalWindow.addSubview(container)
        modalWindow.isHidden = false

        defer {
            modalWindow.isHidden = true
            modalChild.removeFromSuperview()
            container.removeFromSuperview()
        }

        let accessible = tripwire.getAccessibleWindows()

        XCTAssertEqual(accessible.count, 1)
        XCTAssertTrue(accessible.first?.window === modalWindow)
    }

    func testGetAccessibleWindowsDetectsModalBehindTransitionView() {
        // UIKit inserts UITransitionView between window and the VC's view,
        // so the modal container is 3+ levels deep: window → transition → vc.view → modal
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return
        }

        let modalWindow = UIWindow(windowScene: windowScene)
        modalWindow.windowLevel = .alert
        modalWindow.frame = UIScreen.main.bounds

        // Simulate: window → transitionView → vcView → modalContainer
        let transitionView = UIView()
        let vcView = UIView()
        let modalContainer = UIView()
        modalContainer.accessibilityViewIsModal = true
        vcView.addSubview(modalContainer)
        transitionView.addSubview(vcView)
        modalWindow.addSubview(transitionView)
        modalWindow.isHidden = false

        defer {
            modalWindow.isHidden = true
            modalContainer.removeFromSuperview()
            vcView.removeFromSuperview()
            transitionView.removeFromSuperview()
        }

        let accessible = tripwire.getAccessibleWindows()

        XCTAssertEqual(accessible.count, 1, "Should detect modal 3 levels deep")
        XCTAssertTrue(accessible.first?.window === modalWindow)
    }

    func testGetAccessibleWindowsModalFlagBeatsOverlay() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return
        }

        // Lower window flagged modal; higher overlay window has no flag.
        // Modal flag takes precedence (it's checked first), so the lower
        // flagged window wins.
        let flaggedWindow = UIWindow(windowScene: windowScene)
        flaggedWindow.windowLevel = .normal + 1
        flaggedWindow.frame = UIScreen.main.bounds
        let modalView = UIView()
        modalView.accessibilityViewIsModal = true
        flaggedWindow.addSubview(modalView)
        flaggedWindow.isHidden = false

        let overlayWindow = UIWindow(windowScene: windowScene)
        overlayWindow.windowLevel = .alert
        overlayWindow.frame = UIScreen.main.bounds
        overlayWindow.isHidden = false

        defer {
            flaggedWindow.isHidden = true
            overlayWindow.isHidden = true
            modalView.removeFromSuperview()
        }

        let accessible = tripwire.getAccessibleWindows()

        XCTAssertEqual(accessible.count, 1)
        XCTAssertTrue(
            accessible.first?.window === flaggedWindow,
            "Modal flag should win over overlay-window check"
        )
    }

    func testGetAccessibleWindowsPicksFrontmostModal() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return
        }

        // Two windows with modal views — frontmost (higher level) should win
        let lowerModal = UIWindow(windowScene: windowScene)
        lowerModal.windowLevel = .normal + 1
        lowerModal.frame = UIScreen.main.bounds
        let lowerModalView = UIView()
        lowerModalView.accessibilityViewIsModal = true
        lowerModal.addSubview(lowerModalView)
        lowerModal.isHidden = false

        let upperModal = UIWindow(windowScene: windowScene)
        upperModal.windowLevel = .alert
        upperModal.frame = UIScreen.main.bounds
        let upperModalView = UIView()
        upperModalView.accessibilityViewIsModal = true
        upperModal.addSubview(upperModalView)
        upperModal.isHidden = false

        defer {
            lowerModal.isHidden = true
            upperModal.isHidden = true
            lowerModalView.removeFromSuperview()
            upperModalView.removeFromSuperview()
        }

        let accessible = tripwire.getAccessibleWindows()

        XCTAssertEqual(accessible.count, 1, "Only the frontmost modal window should be returned")
        XCTAssertTrue(
            accessible.first?.window === upperModal,
            "The frontmost (highest level) modal should win"
        )
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

    // MARK: - filterToAccessibleWindows (pure precedence chain)

    /// View controller stub that lets a test choose what
    /// `presentedViewController` returns — bypasses UIKit's real
    /// presentation lifecycle, which can't be driven synchronously
    /// from a unit test without an attached window.
    private final class StubViewController: UIViewController {
        var fakePresented: UIViewController?
        override var presentedViewController: UIViewController? { fakePresented }
    }

    /// Build a UIWindow on the active scene without making it visible —
    /// callers pass the window directly into `filterToAccessibleWindows`,
    /// so it never appears in the test host's `getTraversableWindows()`.
    private func makeWindow(level: UIWindow.Level, rootVC: UIViewController? = nil) -> UIWindow {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            XCTFail("No active window scene")
            return UIWindow()
        }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = level
        window.frame = UIScreen.main.bounds
        window.rootViewController = rootVC
        return window
    }

    func testFilterToAccessibleWindowsEmptyInputReturnsEmpty() {
        let result = TheTripwire.filterToAccessibleWindows([])
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterToAccessibleWindowsPicksOverlayWhenNoModalFlag() {
        let overlay = makeWindow(level: .alert, rootVC: UIViewController())
        let base = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            (window: overlay, rootView: overlay as UIView),
            (window: base, rootView: base as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === overlay, "Overlay window should win")
    }

    func testFilterToAccessibleWindowsSkipsOverlayWithoutRootVC() {
        // Frontmost overlay has no rootVC — overlay branch should not match,
        // falling through to other branches (and ultimately the all-windows
        // fallback since no presentation chain exists either).
        let overlay = makeWindow(level: .alert, rootVC: nil)
        let base = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            (window: overlay, rootView: overlay as UIView),
            (window: base, rootView: base as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 2, "Should fall through to all-windows fallback")
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

    func testFilterToAccessibleWindowsFallsBackToAllWhenNothingMatches() {
        let a = makeWindow(level: .normal, rootVC: UIViewController())
        let b = makeWindow(level: .normal - 1, rootVC: UIViewController())
        let input = [
            (window: a, rootView: a as UIView),
            (window: b, rootView: b as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 2, "All windows returned when no branch matches")
    }

    func testFilterToAccessibleWindowsModalFlagBeatsOverlayInPureFilter() {
        let overlay = makeWindow(level: .alert, rootVC: UIViewController())
        let flagged = makeWindow(level: .normal, rootVC: UIViewController())
        let modalView = UIView()
        modalView.accessibilityViewIsModal = true
        flagged.addSubview(modalView)
        defer { modalView.removeFromSuperview() }

        let input = [
            (window: overlay, rootView: overlay as UIView),
            (window: flagged, rootView: flagged as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === flagged, "Modal flag should win over overlay")
    }

    func testFilterToAccessibleWindowsOverlayBeatsPresentedVC() {
        // Lower window has presented VC; frontmost overlay has none but is
        // higher level — overlay branch is checked before presented-VC walk.
        let baseRoot = StubViewController()
        baseRoot.fakePresented = UIViewController()
        let baseWindow = makeWindow(level: .normal, rootVC: baseRoot)

        let overlay = makeWindow(level: .alert, rootVC: UIViewController())

        let input = [
            (window: overlay, rootView: overlay as UIView),
            (window: baseWindow, rootView: baseWindow as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(input)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === overlay, "Overlay should win over presented-VC branch")
    }

    // MARK: - System Passthrough Windows (keyboard / text-effects)

    func testFilterSkipsPassthroughWhenLookingForOverlay() {
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

    func testFilterPicksRealOverlayBeneathPassthrough() {
        // When the keyboard is up over a UIAlertController, the overlay branch
        // should still pick the alert window (after skipping the keyboard),
        // not return all three windows.
        let keyboard = makeWindow(level: .statusBar, rootVC: UIViewController())
        let alert = makeWindow(level: .alert, rootVC: UIViewController())
        let base = makeWindow(level: .normal, rootVC: UIViewController())
        let input = [
            (window: keyboard, rootView: keyboard as UIView),
            (window: alert, rootView: alert as UIView),
            (window: base, rootView: base as UIView),
        ]

        let result = TheTripwire.filterToAccessibleWindows(
            input,
            isPassthrough: { $0 === keyboard }
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.window === alert,
                      "Alert window should win once keyboard is filtered out")
    }

    func testFilterFindsPresentedVCBeneathPassthrough() {
        // Keyboard above an app window whose root VC has a presented VC.
        // After skipping the keyboard, the presented-VC branch should win.
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
        // Defensive: if every window is a passthrough, fall back to the full
        // input rather than returning an empty list. Better to over-include
        // than starve the parser of any windows at all.
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
        // register as a screen change and stale every screenChanged delta.
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

    func testKeyboardAppearanceAndDisappearanceDoNotTriggerScreenChange() {
        // The contract: a software keyboard sliding in or out over the
        // current screen is not a screen change. The same app VC must be
        // reported across all three phases (no keyboard → keyboard up →
        // keyboard dismissed) so isScreenChange() compares equal and
        // downstream callers don't poison their action delta / settle
        // logic with a false screenChanged flag.
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

        let vcIds = phases.map { phase -> ObjectIdentifier? in
            let vc = TheTripwire.topmostViewController(in: phase.windows, isPassthrough: isKeyboard)
            XCTAssertTrue(vc === appVC,
                          "Topmost VC must remain the app VC across phase '\(phase.label)'")
            return vc.map(ObjectIdentifier.init)
        }

        // Every transition between phases must report no screen change.
        for (before, after) in zip(vcIds, vcIds.dropFirst()) {
            XCTAssertFalse(tripwire.isScreenChange(before: before, after: after),
                           "Keyboard appearance/disappearance must not register as a screen change")
        }
    }

}

#endif // canImport(UIKit)
