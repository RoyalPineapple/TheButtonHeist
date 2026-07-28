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

}
