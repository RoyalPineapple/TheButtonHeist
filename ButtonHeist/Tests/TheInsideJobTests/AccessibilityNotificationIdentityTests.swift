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
            (1005, .elementChanged(.value)),
            (1008, .announcement),
            (4002, .unknown(4002)),
            (.max, .unknown(.max)),
        ]

        for (rawCode, expectedKind) in expectations {
            XCTAssertEqual(event(rawCode: rawCode).kind, expectedKind)
        }
    }

    func testCapturedAnnouncementPreservesNormalizedIdentity() throws {
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            rawCode: 1005,
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .string("Updated"),
            associatedElement: .none,
            provenance: .scoped
        )

        let announcement = try XCTUnwrap(event.capturedAnnouncement)

        XCTAssertEqual(announcement.kind, .elementChanged(.value))
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
