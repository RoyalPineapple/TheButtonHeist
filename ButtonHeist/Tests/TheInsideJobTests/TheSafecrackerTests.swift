#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheSafecrackerTests: XCTestCase {

    private var safecracker: TheSafecracker!

    override func setUp() {
        super.setUp()
        safecracker = TheSafecracker()
    }

    override func tearDown() {
        safecracker.stopKeyboardTracking()
        safecracker = nil
        super.tearDown()
    }

    // MARK: - Keyboard Visibility (Notification-Based)

    func testKeyboardNotVisibleByDefault() {
        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    func testKeyboardVisibleAfterFrameNotification() {
        safecracker.startKeyboardTracking()

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

        XCTAssertTrue(safecracker.isKeyboardVisible())
    }

    func testKeyboardNotVisibleWhenFrameOffScreen() {
        safecracker.startKeyboardTracking()

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

        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    func testStopKeyboardTrackingIgnoresSubsequentNotifications() {
        safecracker.startKeyboardTracking()
        safecracker.stopKeyboardTracking()

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

        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    func testKeyboardVisibilityTogglesWithNotifications() {
        safecracker.startKeyboardTracking()

        let screenBounds = UIScreen.main.bounds
        let visibleFrame = CGRect(
            x: 0,
            y: screenBounds.height - 300,
            width: screenBounds.width,
            height: 300
        )
        let hiddenFrame = CGRect(
            x: 0,
            y: screenBounds.height,
            width: screenBounds.width,
            height: 300
        )

        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: visibleFrame]
        )
        XCTAssertTrue(safecracker.isKeyboardVisible())

        NotificationCenter.default.post(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: hiddenFrame]
        )
        XCTAssertFalse(safecracker.isKeyboardVisible())
    }
}
#endif
