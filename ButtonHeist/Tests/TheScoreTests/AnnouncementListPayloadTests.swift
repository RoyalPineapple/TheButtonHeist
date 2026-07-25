import XCTest
@testable import TheScore

final class AnnouncementListPayloadTests: XCTestCase {
    func testCaptureStateUsesOneCanonicalTaggedJSONShape() throws {
        let expectations: [(AccessibilityNotificationCaptureState, [String: Any])] = [
            (.capturing(armed: true), ["type": "capturing", "armed": true]),
            (.capturing(armed: false), ["type": "capturing", "armed": false]),
            (.installationUnavailable, ["type": "installationUnavailable"]),
            (.unsubscribed, ["type": "unsubscribed"]),
        ]

        for (state, expectedObject) in expectations {
            let data = try JSONEncoder().encode(state)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

            XCTAssertEqual(object as NSDictionary, expectedObject as NSDictionary)
            XCTAssertEqual(
                try JSONDecoder().decode(AccessibilityNotificationCaptureState.self, from: data),
                state
            )
        }
    }

    func testCaptureStateRejectsFieldsFromOtherCases() {
        let json = #"{"type":"unsubscribed","armed":true}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityNotificationCaptureState.self, from: Data(json.utf8))
        )
    }

    func testCaptureStateRejectsUnknownFields() {
        let json = #"{"type":"capturing","armed":true,"installed":true}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityNotificationCaptureState.self, from: Data(json.utf8))
        )
    }

    func testEmptyAnnouncementWindowStillReportsCaptureState() throws {
        for state in [
            AccessibilityNotificationCaptureState.capturing(armed: true),
            .capturing(armed: false),
            .installationUnavailable,
            .unsubscribed,
        ] {
            let payload = AnnouncementListPayload(
                announcements: [],
                notifications: [],
                captureState: state
            )

            let decoded = try roundTrip(payload)

            XCTAssertTrue(decoded.announcements.isEmpty)
            XCTAssertTrue(decoded.notifications.isEmpty)
            XCTAssertEqual(decoded.captureState, state)
        }
    }

    func testNonStringNotificationsSurviveTheWireWhereSpokenTextCannot() throws {
        let layoutChanged = evidence(sequence: 1, kind: .elementChanged(.layout), notificationData: .none)
        let screenChanged = evidence(
            sequence: 2,
            kind: .screenChanged,
            notificationData: .unresolvedObject(
                AccessibilityNotificationObjectPayload(className: "UIView", summary: nil)
            )
        )
        let spoken = evidence(sequence: 3, kind: .announcement, notificationData: .string("Saved"))
        let payload = AnnouncementListPayload(
            announcements: [spoken].compactMap(\.capturedAnnouncement),
            notifications: [layoutChanged, screenChanged, spoken],
            captureState: .capturing(armed: true)
        )

        let decoded = try roundTrip(payload)

        XCTAssertEqual(decoded.announcements.map(\.text), ["Saved"])
        XCTAssertEqual(decoded.notifications, [layoutChanged, screenChanged, spoken])
        XCTAssertEqual(decoded.captureState, .capturing(armed: true))
    }

    func testPayloadRejectsUnknownFields() {
        let json = """
        {
          "announcements": [],
          "notifications": [],
          "captureState": {"type": "unsubscribed"},
          "installed": false
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(AnnouncementListPayload.self, from: Data(json.utf8))
        )
    }

    private func roundTrip(_ payload: AnnouncementListPayload) throws -> AnnouncementListPayload {
        try JSONDecoder().decode(
            AnnouncementListPayload.self,
            from: try JSONEncoder().encode(payload)
        )
    }

    private func evidence(
        sequence: UInt64,
        kind: AccessibilityNotificationKind,
        notificationData: AccessibilityNotificationPayload
    ) -> AccessibilityNotificationEvidence {
        AccessibilityNotificationEvidence(
            sequence: sequence,
            kind: kind,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            notificationData: notificationData,
            associatedElement: .none
        )
    }
}
