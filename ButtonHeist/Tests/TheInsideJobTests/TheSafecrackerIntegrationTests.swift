#if canImport(UIKit)
// Integration tests for TheSafecracker's touch injection, text input, and gesture pipeline.
// Requires the BH Demo test host for a live UIWindow and UIApplication.sendEvent pipeline.
import XCTest
@testable import TheInsideJob

@MainActor
final class TheSafecrackerIntegrationTests: XCTestCase {

    private var safecracker: TheSafecracker!
    private var window: UIWindow!

    override func setUp() async throws {
        safecracker = TheSafecracker()
        safecracker.startKeyboardObservation()

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        window = scene?.windows.first
        XCTAssertNotNil(window, "Test host must provide a key window")
    }

    override func tearDown() async throws {
        safecracker.stopKeyboardObservation()
        safecracker = nil
        window = nil
    }

    // MARK: - Touch Injection

    func testSwipeFiresGestureMoveCallback() async {
        var movePoints: [[CGPoint]] = []
        safecracker.onGestureMove = { points in
            movePoints.append(points)
        }
        defer { safecracker.onGestureMove = nil }

        let start = CGPoint(x: 200, y: 400)
        let end = CGPoint(x: 200, y: 200)

        let result = await safecracker.swipe(from: start, to: end, duration: 0.1)
        XCTAssertTrue(result, "swipe() should return true")
        XCTAssertFalse(movePoints.isEmpty, "onGestureMove should have been called during swipe")
    }

    func testTapReturnsTrue() async {
        // Tap an arbitrary point — should succeed even with no target view
        let result = await safecracker.tap(at: CGPoint(x: 100, y: 100))
        XCTAssertTrue(result)
    }

    func testLongPressDoesNotCrash() async {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 50, y: 300, width: 200, height: 44)
        window.addSubview(button)
        defer { button.removeFromSuperview() }

        let screenPoint = button.convert(
            CGPoint(x: button.bounds.midX, y: button.bounds.midY),
            to: nil
        )

        let result = await safecracker.longPress(at: screenPoint, duration: 0.1)
        XCTAssertTrue(result)
    }

    func testSwipeCompletesSuccessfully() async {
        let start = CGPoint(x: 200, y: 400)
        let end = CGPoint(x: 200, y: 200)

        let result = await safecracker.swipe(from: start, to: end, duration: 0.1)
        XCTAssertTrue(result)
    }

    func testDragCompletesSuccessfully() async {
        let start = CGPoint(x: 100, y: 300)
        let end = CGPoint(x: 300, y: 300)

        let result = await safecracker.drag(from: start, to: end, duration: 0.1)
        XCTAssertTrue(result)
    }

    // MARK: - N-Finger Primitives

    func testTouchLifecycleDoesNotCrash() {
        let downResult = safecracker.touchesDown(at: [CGPoint(x: 150, y: 300)])
        XCTAssertTrue(downResult, "touchesDown should succeed")

        let moveResult = safecracker.moveTouches(to: [CGPoint(x: 160, y: 310)])
        XCTAssertTrue(moveResult, "moveTouches should succeed")

        let upResult = safecracker.touchesUp()
        XCTAssertTrue(upResult, "touchesUp should succeed")
    }

    func testMultiTouchLifecycle() {
        let points = [CGPoint(x: 100, y: 300), CGPoint(x: 200, y: 300)]
        let downResult = safecracker.touchesDown(at: points)
        XCTAssertTrue(downResult)

        let movedPoints = [CGPoint(x: 80, y: 300), CGPoint(x: 220, y: 300)]
        let moveResult = safecracker.moveTouches(to: movedPoints)
        XCTAssertTrue(moveResult)

        let upResult = safecracker.touchesUp()
        XCTAssertTrue(upResult)
    }

    func testTouchesUpWithoutDownReturnsFalse() {
        let result = safecracker.touchesUp()
        XCTAssertFalse(result, "touchesUp with no active touches should return false")
    }

    // MARK: - Multi-Touch Gestures

    func testPinchCompletesSuccessfully() async {
        let center = CGPoint(x: 200, y: 400)
        let result = await safecracker.pinch(center: center, scale: 2.0, spread: 80, duration: 0.1)
        XCTAssertTrue(result)
    }

    func testRotateCompletesSuccessfully() async {
        let center = CGPoint(x: 200, y: 400)
        let result = await safecracker.rotate(center: center, angle: .pi / 4, radius: 80, duration: 0.1)
        XCTAssertTrue(result)
    }

    func testTwoFingerTapCompletesSuccessfully() async {
        let center = CGPoint(x: 200, y: 400)
        let result = await safecracker.twoFingerTap(at: center)
        XCTAssertTrue(result)
    }

    // MARK: - Text Input

    func testTypeTextIntoTextField() async throws {
        let textField = UITextField()
        textField.frame = CGRect(x: 50, y: 400, width: 200, height: 44)
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "TypeTest"
        window.addSubview(textField)
        defer {
            textField.resignFirstResponder()
            textField.removeFromSuperview()
        }

        textField.becomeFirstResponder()
        try await waitForKeyboardBridge()

        let result = await safecracker.typeText("hello")
        XCTAssertTrue(result, "typeText should succeed when keyboard is active")
        XCTAssertEqual(textField.text, "hello")
    }

    func testDeleteTextFromTextField() async throws {
        let textField = UITextField()
        textField.frame = CGRect(x: 50, y: 400, width: 200, height: 44)
        textField.text = "world"
        window.addSubview(textField)
        defer {
            textField.resignFirstResponder()
            textField.removeFromSuperview()
        }

        textField.becomeFirstResponder()
        try await waitForKeyboardBridge()

        // Select all text first, then delete
        let deleted = await safecracker.deleteText(count: 5)
        XCTAssertTrue(deleted, "deleteText should succeed")
        XCTAssertEqual(textField.text, "")
    }

    func testDeleteZeroCountReturnsTrue() async {
        // deleteText(count: 0) should return true immediately regardless of keyboard state
        let result = await safecracker.deleteText(count: 0)
        XCTAssertTrue(result)
    }

    // MARK: - Edit Actions

    func testResignFirstResponder() {
        let textField = UITextField()
        textField.frame = CGRect(x: 50, y: 500, width: 200, height: 44)
        window.addSubview(textField)
        defer { textField.removeFromSuperview() }

        textField.becomeFirstResponder()
        XCTAssertTrue(textField.isFirstResponder)

        let result = safecracker.resignFirstResponder()
        XCTAssertTrue(result)
        XCTAssertFalse(textField.isFirstResponder)
    }

    // MARK: - Duration Helpers

    func testClampDurationDefaults() {
        XCTAssertEqual(safecracker.clampDuration(nil), 0.5)
        XCTAssertEqual(safecracker.clampDuration(0.001), 0.01)
        XCTAssertEqual(safecracker.clampDuration(100.0), 60.0)
        XCTAssertEqual(safecracker.clampDuration(1.0), 1.0)
    }

    func testResolveDurationPrefersExplicit() {
        let duration = safecracker.resolveDuration(2.0, velocity: nil, points: [])
        XCTAssertEqual(duration, 2.0)
    }

    func testResolveDurationFallsBackToVelocity() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let duration = safecracker.resolveDuration(nil, velocity: 200, points: points)
        XCTAssertEqual(duration, 0.5, accuracy: 0.01)
    }

    // MARK: - Private Helpers

    private func waitForKeyboardBridge() async throws {
        for _ in 0..<20 {
            if KeyboardBridge.shared() != nil { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard KeyboardBridge.shared() != nil else {
            XCTFail("Keyboard bridge not available after 2s")
            return
        }
    }
}

#endif // canImport(UIKit)
