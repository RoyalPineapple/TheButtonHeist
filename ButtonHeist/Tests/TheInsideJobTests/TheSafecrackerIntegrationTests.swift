#if canImport(UIKit)
// Integration tests for TheSafecracker's touch injection, text input, and gesture pipeline.
// Requires the BH Demo test host for a live UIWindow and UIApplication.sendEvent pipeline.
import XCTest
@testable import TheInsideJob
import ThePlans
import TheScore

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

    func testTapReturnsTrue() async {
        // Tap an arbitrary point — should succeed even with no target view
        let result = await safecracker.tap(at: CGPoint(x: 100, y: 100))
        XCTAssertTrue(result)
    }

    func testLongPressDoesNotCrash() async throws {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 50, y: 300, width: 200, height: 44)
        window.addSubview(button)
        defer { button.removeFromSuperview() }

        let screenPoint = button.convert(
            CGPoint(x: button.bounds.midX, y: button.bounds.midY),
            to: nil
        )

        let result = await safecracker.longPress(
            at: screenPoint,
            duration: GestureDuration(seconds: 0.1)
        )
        XCTAssertTrue(result)
    }

    func testSwipeCompletesSuccessfully() async throws {
        let start = CGPoint(x: 200, y: 400)
        let end = CGPoint(x: 200, y: 200)

        let result = await safecracker.swipe(
            from: start,
            to: end,
            duration: GestureDuration(seconds: 0.1)
        )
        XCTAssertTrue(result)
    }

    func testDragCompletesSuccessfully() async throws {
        let start = CGPoint(x: 100, y: 300)
        let end = CGPoint(x: 300, y: 300)

        let result = await safecracker.drag(
            from: start,
            to: end,
            duration: GestureDuration(seconds: 0.1)
        )
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

        textField.becomeFirstResponder()
        try await waitForActiveTextInput()

        let result = await safecracker.typeText("hello")
        XCTAssertEqual(result, .dispatched, "typeText should succeed when keyboard is active")
        XCTAssertEqual(textField.text, "hello")

        await teardownKeyboard(textField: textField)
    }

    func testActiveTextInputRequiresFocusedEditableResponder() async throws {
        let textField = UITextField()
        textField.frame = CGRect(x: 50, y: 400, width: 200, height: 44)
        window.addSubview(textField)

        XCTAssertFalse(safecracker.hasActiveTextInput())

        textField.becomeFirstResponder()
        try await waitForActiveTextInput()
        XCTAssertTrue(safecracker.hasActiveTextInput())

        await teardownKeyboard(textField: textField)
    }

    // MARK: - Edit Actions

    func testResignFirstResponder() async {
        let textField = UITextField()
        textField.frame = CGRect(x: 50, y: 500, width: 200, height: 44)
        window.addSubview(textField)

        textField.becomeFirstResponder()
        XCTAssertTrue(textField.isFirstResponder)

        let result = safecracker.resignFirstResponder()
        XCTAssertTrue(result)
        XCTAssertFalse(textField.isFirstResponder)

        await teardownKeyboard(textField: textField)
    }

    // MARK: - Private Helpers

    private func waitForActiveTextInput() async throws {
        for _ in 0..<20 {
            if safecracker.hasActiveTextInput() { return }
            // Polls UIKit's private keyboard delegate state — no public signal to await on.
            // swiftlint:disable:next agent_test_task_sleep
            try await Task.sleep(for: .milliseconds(100))
        }
        guard safecracker.hasActiveTextInput() else {
            XCTFail("Active text input not available after 2s")
            return
        }
    }

    /// Resign first responder, remove the text field, and wait for the
    /// keyboard window to retire from the foreground scene. The keyboard's
    /// `UIRemoteKeyboardWindow` and `UITextEffectsWindow` are owned by iOS
    /// and persist beyond `resignFirstResponder()` — without an explicit
    /// wait they leak across tests and pollute the next setUp's window list.
    private func teardownKeyboard(textField: UITextField) async {
        textField.resignFirstResponder()
        textField.removeFromSuperview()
        await KeyboardWindowTestHelpers.waitForKeyboardWindowsToRetire()
    }
}

#endif // canImport(UIKit)
