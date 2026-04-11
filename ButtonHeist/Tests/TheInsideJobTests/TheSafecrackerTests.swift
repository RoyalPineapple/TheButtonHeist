#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheSafecrackerTests: XCTestCase {

    private var tripwire: TheTripwire!
    private var safecracker: TheSafecracker!

    override func setUp() async throws {
        tripwire = TheTripwire()
        safecracker = TheSafecracker()
        safecracker.startKeyboardObservation()
    }

    override func tearDown() async throws {
        safecracker.stopKeyboardObservation()
        tripwire.stopPulse()
        tripwire = nil
        safecracker = nil
    }

    // MARK: - Keyboard Visibility

    func testKeyboardNotVisibleByDefault() {
        XCTAssertFalse(safecracker.isKeyboardVisible())
    }

    func testKeyboardVisibleAfterFrameNotification() {
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

    func testKeyboardNotVisibleAfterObservationStopped() {
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

        safecracker.stopKeyboardObservation()

        // After stopping observation, the flag retains its last value
        // but new notifications should not update it.
        let newSafecracker = TheSafecracker()
        XCTAssertFalse(newSafecracker.isKeyboardVisible())
    }

    func testKeyboardVisibilityTogglesWithNotifications() {
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
