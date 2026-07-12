import XCTest
@testable import TheScore

/// Contract tests for the grouped source evidence behind `ActionResult`.
final class ActionResultEvidenceContractTests: XCTestCase {

    func testGroupedEvidenceStoresSettleDurationOnceAndProjectsItToBothPublicFields() {
        let result = ActionResult.success(
            method: .activate,
            timing: ActionPerformanceTiming(actionDispatchMs: 4, settleMs: 125)
        )

        XCTAssertEqual(result.evidence.settleTimeMs, 125)
        XCTAssertNil(result.evidence.timing?.settleMs)
        XCTAssertEqual(result.settleTimeMs, 125)
        XCTAssertEqual(result.timing?.settleMs, 125)
    }

    func testGroupedEvidenceUsesTraceAnnouncementAsTheSoleAnnouncementValue() {
        let trace = traceWithAnnouncement("Checkout")
        let result = ActionResult.success(
            method: .activate,
            accessibilityTrace: trace
        )

        XCTAssertEqual(result.evidence.announcement, "Checkout")
        XCTAssertEqual(result.announcement, "Checkout")
        XCTAssertEqual(result.capturedAnnouncement, trace.capturedAnnouncements.first)
    }

    func testActionResultRejectsContradictoryGroupedEvidenceAtDecodeBoundary() {
        let json = """
        {
          "outcome": {"kind": "success"},
          "method": "activate",
          "settleTimeMs": 125,
          "timing": {"settleMs": 126}
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ActionResult.self, from: Data(json.utf8)))
    }

    func testActionResultKeepsGroupedEvidenceFlattenedAtTheExistingJSONBoundary() throws {
        let result = ActionResult.success(
            method: .activate,
            message: "done",
            settled: true,
            settleTimeMs: 125,
            timing: ActionPerformanceTiming(actionDispatchMs: 4, settleMs: 125),
            announcement: "Checkout"
        )

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let timing = try XCTUnwrap(object["timing"] as? [String: Any])

        XCTAssertEqual(Set(object.keys), Set([
            "outcome",
            "method",
            "message",
            "announcement",
            "settled",
            "settleTimeMs",
            "timing",
        ]))
        XCTAssertNil(object["evidence"])
        XCTAssertEqual(object["settleTimeMs"] as? Int, 125)
        XCTAssertEqual(timing["settleMs"] as? Int, 125)
    }

    private func traceWithAnnouncement(_ text: String) -> AccessibilityTrace {
        let first = AccessibilityTrace.Capture(
            sequence: 1,
            interface: Interface(timestamp: Date(timeIntervalSince1970: 1), tree: [])
        )
        let second = AccessibilityTrace.Capture(
            sequence: 2,
            interface: Interface(timestamp: Date(timeIntervalSince1970: 2), tree: []),
            parentHash: first.hash,
            transition: AccessibilityTrace.Transition(
                accessibilityNotifications: [
                    AccessibilityNotificationEvidence(
                        sequence: 7,
                        kind: .announcement,
                        timestamp: Date(timeIntervalSince1970: 7),
                        notificationData: .string(text),
                        associatedElement: .none
                    ),
                ]
            )
        )
        return AccessibilityTrace(captures: [first, second])
    }
}
