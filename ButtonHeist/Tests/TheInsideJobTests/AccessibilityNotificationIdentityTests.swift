#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class AccessibilityNotificationIdentityTests: XCTestCase {
    func testPendingEventNormalizesUIKitCodeOnce() {
        let expectations: [(UInt32, AccessibilityNotificationKind)] = [
            (1000, .screenChanged),
            (1001, .elementChanged(.layout)),
            (1005, .elementChanged(.value)),
            (1008, .announcement),
            (4002, .unknown(4002)),
        ]

        for (rawCode, expectedKind) in expectations {
            XCTAssertEqual(event(rawCode: rawCode).kind, expectedKind)
        }
    }

    func testPendingEventClassificationSwitchesOnOuterSemanticCategory() {
        XCTAssertTrue(event(rawCode: 1000).startsObservationGeneration)
        XCTAssertFalse(event(rawCode: 1001).startsObservationGeneration)
        XCTAssertFalse(event(rawCode: 1005).startsObservationGeneration)
        XCTAssertFalse(event(rawCode: 1008).startsObservationGeneration)
        XCTAssertFalse(event(rawCode: 4002).startsObservationGeneration)
    }

    func testCapturedAnnouncementPreservesNormalizedIdentity() throws {
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            rawCode: 1005,
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .string("Updated"),
            associatedElement: .none
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
            associatedElement: .none
        )
    }
}
#endif
