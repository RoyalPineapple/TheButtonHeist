#if canImport(UIKit)
import UIKit
import XCTest
@testable import TheInsideJob

@MainActor
final class AccessibilityNotificationObserverTests: XCTestCase {
    private enum WaitError: Error {
        case timedOut(UInt32)
    }

    override func tearDown() async throws {
        AccessibilityNotificationObserver.shared.uninstall()
        try await super.tearDown()
    }

    func testObserverReceivesPostedPayloadShapes() async throws {
        let bus = AccessibilityNotificationBus()

        AccessibilityNotificationObserver.shared.subscribe(bus)
        guard AccessibilityNotificationObserver.shared.isInstalled else {
            throw XCTSkip("_AXAddNotificationCallback is unavailable in this runtime")
        }
        bus.clearPendingEvents()

        UIAccessibility.post(
            notification: .announcement,
            argument: "BH announcement string payload"
        )
        let announcement = try await waitForNotification(code: 1008, in: bus)
        guard case .string(let value) = announcement.notificationData else {
            return XCTFail("Expected string notification data, got \(announcement.notificationData)")
        }
        XCTAssertEqual(value, "BH announcement string payload")

        let container = NSObject()
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityLabel = "BH layout element payload"
        UIAccessibility.post(notification: .layoutChanged, argument: element)
        let layoutChange = try await waitForNotification(code: 1001, in: bus)
        guard case .object(let objectIdentity) = layoutChange.notificationData else {
            return XCTFail("Expected element notification data, got \(layoutChange.notificationData)")
        }
        XCTAssertNil(objectIdentity.object)
        XCTAssertTrue(
            objectIdentity.summary?.contains("AXUIElementRef") == true,
            "Expected transformed AX element handle summary, got \(objectIdentity.summary ?? "nil")"
        )

        UIAccessibility.post(notification: .screenChanged, argument: nil)
        let screenChange = try await waitForNotification(code: 1000, in: bus)
        guard case .none = screenChange.notificationData else {
            return XCTFail("Expected nil screen-change notification data, got \(screenChange.notificationData)")
        }
    }

    private func waitForNotification(
        code: UInt32,
        in bus: AccessibilityNotificationBus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PendingAccessibilityNotificationEvent {
        for _ in 0..<100 {
            if let event = bus.drainPendingEvents().first(where: { $0.code == code }) {
                return event
            }
            await Task.yield()
            _ = await Task.cancellableSleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for accessibility notification \(code)", file: file, line: line)
        throw WaitError.timedOut(code)
    }
}

#endif
