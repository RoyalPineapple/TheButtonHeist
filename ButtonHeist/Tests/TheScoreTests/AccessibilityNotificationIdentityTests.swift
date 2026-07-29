import XCTest
import ThePlans
@testable import TheScore

final class AccessibilityNotificationIdentityTests: XCTestCase {
    func testNotificationIdentityIsItsCanonicalContent() throws {
        let semantics = elementSemantics(label: "Save")
        let notifications = [
            try XCTUnwrap(Observation.Notification(text: "Saved", element: nil)),
            try XCTUnwrap(Observation.Notification(text: nil, element: semantics)),
            try XCTUnwrap(Observation.Notification(text: "Saved", element: semantics)),
        ]

        XCTAssertNotEqual(notifications[0], notifications[1])
        XCTAssertNotEqual(notifications[1], notifications[2])
        XCTAssertNotEqual(notifications[0], notifications[2])
        XCTAssertEqual(
            try JSONDecoder().decode(
                [Observation.Notification].self,
                from: JSONEncoder().encode(notifications)
            ),
            notifications
        )
    }

    func testNotificationRequiresTextOrElementSemantics() {
        XCTAssertNil(Observation.Notification(text: nil, element: nil))

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                Observation.Notification.self,
                from: Data("{}".utf8)
            )
        )
    }

    func testNotificationRejectsUnknownFields() {
        let json = #"{"text":"Saved","sequence":1}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                Observation.Notification.self,
                from: Data(json.utf8)
            )
        ) { error in
            XCTAssertTrue("\(error)".contains("sequence"), "\(error)")
        }
    }

    func testServerMessageProjectsNotificationsAsItsDirectPayload() throws {
        let notifications = [
            try XCTUnwrap(Observation.Notification(text: "Saved", element: nil)),
            try XCTUnwrap(
                Observation.Notification(
                    text: nil,
                    element: elementSemantics(label: "Save")
                )
            ),
        ]

        let data = try JSONEncoder().encode(ServerMessage.notifications(notifications))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "notifications")
        XCTAssertEqual((object["payload"] as? [[String: Any]])?.count, 2)

        guard case .notifications(let decoded) = try JSONDecoder().decode(
            ServerMessage.self,
            from: data
        ) else {
            return XCTFail("Expected notifications response")
        }
        XCTAssertEqual(decoded, notifications)
    }

    private func elementSemantics(label: String) -> HeistElement.Semantics {
        HeistElement.Semantics(
            spokenDescription: label,
            assertable: HeistElement.Semantics.AssertableProperties(
                label: label,
                value: nil,
                identifier: nil,
                traits: [.button],
                actions: [.activate]
            ),
            respondsToUserInteraction: true
        )
    }
}
