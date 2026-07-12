import XCTest
@testable import TheScore

/// Wire-shape tests for the current auto-settle fields:
/// `ActionResult.settled` / `settleTimeMs` and
/// transient elements on the no-change delta payload.
final class AutoSettleFieldsTests: XCTestCase {

    // MARK: - ActionResult

    func testActionResultRoundTripsWithSettleFields() throws {
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(settlement: .settled(durationMs: 1234))
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.settled, true)
        XCTAssertEqual(decoded.settleTimeMs, 1234)
    }

    func testFailedActionResultRoundTripsWithSettleFields() throws {
        let result = ActionResult.failure(
            method: .wait,
            errorKind: .timeout,
            message: "timed out",
            evidence: ActionResultEvidence(settlement: .timedOut(durationMs: 750))
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertFalse(decoded.outcome.isSuccess)
        XCTAssertEqual(decoded.outcome.errorKind, .timeout)
        XCTAssertEqual(decoded.settled, false)
        XCTAssertEqual(decoded.settleTimeMs, 750)
    }

    func testSettleDurationHasOneCanonicalStoredValue() throws {
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(
                settlement: .settled(durationMs: 125),
                timing: ActionPerformanceTiming(actionDispatchMs: 4, settleMs: 125)
            )
        )

        let decoded = try JSONDecoder().decode(ActionResult.self, from: JSONEncoder().encode(result))

        XCTAssertEqual(decoded.settleTimeMs, 125)
        XCTAssertEqual(decoded.timing?.settleMs, 125)
        XCTAssertEqual(decoded.timing?.actionDispatchMs, 4)
    }

    func testDecodeRejectsContradictorySettleDurations() {
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

    func testActionResultDerivesAnnouncementFromTraceNotificationStringPayload() throws {
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
                        kind: .screenChanged,
                        timestamp: Date(timeIntervalSince1970: 7),
                        notificationData: .string("Checkout"),
                        associatedElement: .none
                    ),
                ]
            )
        )
        let trace = AccessibilityTrace(captures: [first, second])

        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(accessibilityTrace: trace)
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(result.announcement, "Checkout")
        XCTAssertEqual(decoded.announcement, "Checkout")
        XCTAssertEqual(result.capturedAnnouncement, trace.capturedAnnouncements.first)
        XCTAssertEqual(decoded.capturedAnnouncement, trace.capturedAnnouncements.first)
        XCTAssertEqual(trace.capturedAnnouncements.first?.kind, .screenChanged)
    }

    func testDecodeRejectsAnnouncementContradictingTraceEvidence() throws {
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
                        notificationData: .string("Checkout"),
                        associatedElement: .none
                    ),
                ]
            )
        )
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(
                accessibilityTrace: AccessibilityTrace(captures: [first, second])
            )
        )
        let encoded = try JSONEncoder().encode(result)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["announcement"] = "Cart"
        let contradictory = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionResult.self, from: contradictory))
    }

    // MARK: - Change-fact transient metadata

    func testAccessibilityTraceChangeFactRoundTripsWithTransient() throws {
        let element = HeistElement(
            description: "Loading",
            label: "Processing",
            value: nil,
            identifier: nil,
            traits: [.staticText],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 30,
            actions: []
        )
        let fact = AccessibilityTrace.ChangeFact.elementsChanged(.init(
            metadata: .init(transient: [element])
        ))
        let data = try JSONEncoder().encode(fact)
        let decoded = try JSONDecoder().decode(AccessibilityTrace.ChangeFact.self, from: data)
        guard case .elementsChanged(let payload) = decoded else {
            return XCTFail("Expected elementsChanged, got \(decoded)")
        }
        XCTAssertEqual(payload.metadata.transient.count, 1)
        XCTAssertEqual(payload.metadata.transient.first?.label, "Processing")
    }

}
