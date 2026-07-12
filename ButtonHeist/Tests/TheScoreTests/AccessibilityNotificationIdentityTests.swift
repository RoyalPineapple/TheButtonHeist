import XCTest
@testable import TheScore

final class AccessibilityNotificationIdentityTests: XCTestCase {
    func testRawUIKitCodesNormalizeToSemanticIdentity() {
        XCTAssertEqual(AccessibilityNotificationKind(rawCode: 1000), .screenChanged)
        XCTAssertEqual(AccessibilityNotificationKind(rawCode: 1001), .elementChanged(.layout))
        XCTAssertEqual(AccessibilityNotificationKind(rawCode: 1005), .elementChanged(.value))
        XCTAssertEqual(AccessibilityNotificationKind(rawCode: 1008), .announcement)
        XCTAssertEqual(AccessibilityNotificationKind(rawCode: 4002), .unknown(4002))
    }

    func testNotificationIdentityUsesOneCanonicalTaggedJSONShape() throws {
        let expectations: [(AccessibilityNotificationKind, [String: Any])] = [
            (.screenChanged, ["type": "screenChanged"]),
            (.elementChanged(.layout), ["type": "elementChanged", "notification": "layout"]),
            (.elementChanged(.value), ["type": "elementChanged", "notification": "value"]),
            (.announcement, ["type": "announcement"]),
            (.unknown(4002), ["type": "unknown", "rawCode": 4002]),
        ]

        for (kind, expectedObject) in expectations {
            let data = try JSONEncoder().encode(kind)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

            XCTAssertEqual(object as NSDictionary, expectedObject as NSDictionary)
            XCTAssertEqual(try JSONDecoder().decode(AccessibilityNotificationKind.self, from: data), kind)
        }
    }

    func testNotificationIdentityRejectsFieldsFromOtherCases() {
        let json = #"{"type":"announcement","rawCode":1008}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityNotificationKind.self, from: Data(json.utf8))
        )
    }

    func testEvidenceRejectsLegacyScalarKindBags() {
        let legacyKinds = [
            #""kind": "screenChanged""#,
            #""kind": "unknown", "rawCode": 4002"#,
        ]

        for legacyKind in legacyKinds {
            let json = """
            {
              "sequence": 1,
              \(legacyKind),
              "timestamp": 0,
              "notificationData": {"type": "none"},
              "associatedElement": {"type": "none"}
            }
            """

            XCTAssertThrowsError(
                try JSONDecoder().decode(AccessibilityNotificationEvidence.self, from: Data(json.utf8))
            )
        }
    }

    func testCapturedAnnouncementRejectsLegacyKindAndRawCodeBag() {
        let json = """
        {
          "sequence": 1,
          "text": "Done",
          "timestamp": 0,
          "kind": "unknown",
          "rawCode": 4002,
          "associatedElement": {"type": "none"}
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(CapturedAnnouncement.self, from: Data(json.utf8))
        )
    }

    func testOnlyElementChangedNotificationsProduceElementChangeEvidence() {
        for kind in [AccessibilityNotificationKind.announcement, .unknown(4002)] {
            let (before, after) = captures(notifications: [evidence(kind)])

            XCTAssertTrue(AccessibilityTrace.ChangeFact.between(before, after).isEmpty)
        }

        for kind in [AccessibilityNotificationKind.elementChanged(.layout), .elementChanged(.value)] {
            let notification = evidence(kind)
            let (before, after) = captures(notifications: [notification])
            let facts = AccessibilityTrace.ChangeFact.between(before, after)

            guard facts.count == 1, case .elementsChanged(let elements) = facts[0] else {
                return XCTFail("Expected one notification-only element change fact")
            }
            XCTAssertEqual(elements.metadata.accessibilityNotifications, [notification])
        }
    }

    func testScreenBoundaryClassifiesNotificationsByOuterSemanticCategory() {
        let elementNotifications = [
            evidence(.elementChanged(.layout), sequence: 1),
            evidence(.elementChanged(.value), sequence: 2),
        ]
        let screenNotification = evidence(.screenChanged, sequence: 3)
        let notifications = elementNotifications + [
            screenNotification,
            evidence(.announcement, sequence: 4),
            evidence(.unknown(4002), sequence: 5),
        ]
        let (before, after) = captures(notifications: notifications)

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        guard facts.count == 3 else {
            return XCTFail("Expected departure, screen, and arrival facts")
        }
        XCTAssertEqual(facts[0].metadata.accessibilityNotifications, elementNotifications)
        XCTAssertEqual(facts[1].metadata.accessibilityNotifications, [screenNotification])
        XCTAssertEqual(facts[2].metadata.accessibilityNotifications, elementNotifications)
    }

    private func evidence(
        _ kind: AccessibilityNotificationKind,
        sequence: UInt64 = 1
    ) -> AccessibilityNotificationEvidence {
        AccessibilityNotificationEvidence(
            sequence: sequence,
            kind: kind,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            notificationData: .none,
            associatedElement: .none
        )
    }

    private func captures(
        notifications: [AccessibilityNotificationEvidence]
    ) -> (AccessibilityTrace.Capture, AccessibilityTrace.Capture) {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface)
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: notifications)
        )
        return (before, after)
    }
}
