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
    private var hostView: UIView!

    override func setUp() async throws {
        safecracker = TheSafecracker()
        safecracker.startKeyboardObservation()

        _ = await retireKeyboard {
            safecracker.resignFirstResponder()
        }

        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        self.window = window
        hostView = viewController.view
    }

    override func tearDown() async throws {
        _ = await retireKeyboard {
            window?.endEditing(true)
            return safecracker.resignFirstResponder()
        }
        safecracker.stopKeyboardObservation()
        safecracker = nil
        hostView = nil
        window?.isHidden = true
        window?.rootViewController = nil
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
        hostView.addSubview(button)
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
        hostView.addSubview(textField)

        await activateTextInput(textField)

        let result = await safecracker.typeText("hello")
        XCTAssertEqual(result, .dispatched, "typeText should succeed when keyboard is active")
        XCTAssertEqual(textField.text, "hello")

        await teardownKeyboard(textField: textField)
    }

    func testActiveTextInputRequiresFocusedEditableResponder() async throws {
        let textField = UITextField()
        textField.frame = CGRect(x: 50, y: 400, width: 200, height: 44)
        hostView.addSubview(textField)

        XCTAssertFalse(safecracker.hasActiveTextInput())

        await activateTextInput(textField)

        await teardownKeyboard(textField: textField)
    }

    // MARK: - Edit Actions

    func testResignFirstResponder() async {
        let textField = UITextField()
        textField.frame = CGRect(x: 50, y: 500, width: 200, height: 44)
        hostView.addSubview(textField)

        await activateTextInput(textField)
        XCTAssertTrue(textField.isFirstResponder)

        let result = await retireKeyboard {
            safecracker.resignFirstResponder()
        }
        XCTAssertTrue(result)
        XCTAssertFalse(textField.isFirstResponder)

        await teardownKeyboard(textField: textField)
    }

    // MARK: - Private Helpers

    private func activateTextInput(_ textField: UITextField) async {
        XCTAssertTrue(textField.becomeFirstResponder())
        XCTAssertTrue(textField.isFirstResponder)
        let didActivate = await safecracker.waitForActiveTextInput()
        XCTAssertTrue(didActivate)
    }

    private func retireKeyboard<Result>(
        perform action: () -> Result
    ) async -> Result {
        let hasActiveResponder = safecracker.hasActiveTextInput()
            || KeyboardWindowTestHelpers.hasFirstResponder(in: hostView)

        let result = action()
        if hasActiveResponder, KeyboardWindowTestHelpers.hasPassthroughWindow() {
            await KeyboardWindowTestHelpers.waitForKeyboardWindowsToRetire()
        }

        XCTAssertFalse(safecracker.hasActiveTextInput())
        XCTAssertFalse(KeyboardWindowTestHelpers.hasFirstResponder(in: hostView))
        return result
    }

    private func teardownKeyboard(textField: UITextField) async {
        _ = await retireKeyboard {
            textField.resignFirstResponder()
        }
        textField.removeFromSuperview()
    }

}

#endif // canImport(UIKit)
