#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class AccessibilityNotificationIdentityTests: XCTestCase {
    func testPendingEventNormalizesUIKitCodeOnce() {
        let expectations: [(UInt32, AccessibilityNotificationKind)] = [
            (.min, .unknown(.min)),
            (1000, .screenChanged),
            (1001, .elementChanged(.layout)),
            (1005, .elementUpdate),
            (1008, .announcement),
            (4002, .unknown(4002)),
            (.max, .unknown(.max)),
        ]

        for (rawCode, expectedKind) in expectations {
            XCTAssertEqual(event(rawCode: rawCode).kind, expectedKind)
        }
    }

    func testUIKitAnnouncementEvidencePreservesNormalizedKindAndPayload() {
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            rawCode: 1008,
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .string("Updated"),
            associatedElement: .none,
            provenance: .scoped
        )

        XCTAssertEqual(event.kind, .announcement)
        guard case .string(let text) = event.notificationData else {
            return XCTFail("Expected UIKit announcement text")
        }
        XCTAssertEqual(text, "Updated")
    }

    func testOnlyElementNotificationsAdmitAssociatedElementContent() {
        XCTAssertFalse(AccessibilityNotificationKind.screenChanged.admitsAssociatedElement)
        XCTAssertTrue(
            AccessibilityNotificationKind.elementChanged(.layout).admitsAssociatedElement
        )
        XCTAssertTrue(
            AccessibilityNotificationKind.elementUpdate.admitsAssociatedElement
        )
        XCTAssertFalse(AccessibilityNotificationKind.announcement.admitsAssociatedElement)
        XCTAssertFalse(AccessibilityNotificationKind.unknown(4002).admitsAssociatedElement)
    }

    private func event(rawCode: UInt32) -> PendingAccessibilityNotificationEvent {
        PendingAccessibilityNotificationEvent(
            sequence: 1,
            rawCode: rawCode,
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .none,
            associatedElement: .none,
            provenance: .ambient
        )
    }
}
#endif
