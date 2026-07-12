import XCTest
@testable import TheScore

final class ActionResultEvidenceContractTests: XCTestCase {

    func testSuccessEvidenceRoundTripsWithCanonicalShape() throws {
        let trace = traceWithAnnouncement("Checkout")
        let result = ActionResult.success(
            method: .activate,
            message: "done",
            evidence: ActionResultSuccessEvidence(
                observation: .settledTrace(trace, .settled(durationMs: 125)),
                timing: ActionPerformanceTiming(actionDispatchMs: 4),
                warning: .activationWeakAffordance(evidence: "label=Checkout")
            )
        )

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let evidence = try XCTUnwrap(object["evidence"] as? [String: Any])
        let observation = try XCTUnwrap(evidence["observation"] as? [String: Any])
        let settlement = try XCTUnwrap(observation["settlement"] as? [String: Any])
        let timing = try XCTUnwrap(evidence["timing"] as? [String: Any])

        XCTAssertEqual(Set(object.keys), Set(["outcome", "method", "message", "evidence"]))
        XCTAssertEqual(Set(evidence.keys), Set(["observation", "timing", "warning"]))
        XCTAssertEqual(observation["kind"] as? String, "settledTrace")
        XCTAssertNotNil(observation["accessibilityTrace"])
        XCTAssertNil(observation["announcement"])
        XCTAssertEqual(settlement["kind"] as? String, "settled")
        XCTAssertEqual(settlement["durationMs"] as? Int, 125)
        XCTAssertEqual(timing["actionDispatchMs"] as? Int, 4)
        XCTAssertNil(timing["settleMs"])

        let decoded = try JSONDecoder().decode(ActionResult.self, from: encoded)
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.announcement, "Checkout")
        XCTAssertEqual(decoded.settleTimeMs, 125)
        XCTAssertEqual(decoded.timing?.settleMs, 125)
        XCTAssertEqual(decoded.warning, .activationWeakAffordance(evidence: "label=Checkout"))
    }

    func testFailureEvidenceRoundTripsWithExplicitAbsence() throws {
        let result = ActionResult.failure(
            method: .wait,
            errorKind: .timeout,
            message: "timed out",
            evidence: .none
        )

        let decoded = try JSONDecoder().decode(ActionResult.self, from: JSONEncoder().encode(result))

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.outcome, .failure(.timeout))
        XCTAssertNil(decoded.accessibilityTrace)
        XCTAssertNil(decoded.announcement)
        XCTAssertNil(decoded.warning)
        XCTAssertEqual(decoded.evidence, .failure(.none))
    }

    func testStandaloneAnnouncementIsTheOnlyAnnouncementFact() throws {
        let result = ActionResult.success(
            method: .wait,
            evidence: ActionResultSuccessEvidence(observation: .announcement("Ready"))
        )

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let evidence = try XCTUnwrap(object["evidence"] as? [String: Any])
        let observation = try XCTUnwrap(evidence["observation"] as? [String: Any])

        XCTAssertEqual(observation["kind"] as? String, "announcement")
        XCTAssertEqual(observation["announcement"] as? String, "Ready")
        XCTAssertNil(object["announcement"])
        XCTAssertNil(evidence["announcement"])
        XCTAssertEqual(result.announcement, "Ready")
        XCTAssertNil(result.accessibilityTrace)
    }

    func testTraceOwnsCapturedAnnouncement() {
        let trace = traceWithAnnouncement("Checkout")
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(observation: .trace(trace))
        )

        XCTAssertEqual(result.announcement, "Checkout")
        XCTAssertEqual(result.capturedAnnouncement, trace.capturedAnnouncements.first)
    }

    func testWithTimingUpdatesSettlementOwnerWithoutStoringDuplicate() {
        let trace = traceWithAnnouncement("Checkout")
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .settledTrace(trace, .settled(durationMs: 5)),
                timing: ActionPerformanceTiming(actionDispatchMs: 1)
            )
        )

        let timed = result.withTiming(ActionPerformanceTiming(actionDispatchMs: 2, settleMs: 8))

        XCTAssertEqual(timed.evidence.settlement?.durationMs, 8)
        XCTAssertNil(timed.evidence.timing?.settleMs)
        XCTAssertEqual(timed.timing?.actionDispatchMs, 2)
        XCTAssertEqual(timed.timing?.settleMs, 8)
    }

    func testDecodingRejectsMissingAndEmptyEvidence() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "activate"
        }
        """)
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "activate",
          "evidence": {}
        }
        """)
    }

    func testDecodingRejectsLegacyEvidenceBags() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "activate",
          "evidence": {"announcement": "Checkout"}
        }
        """)
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "activate",
          "evidence": {
            "settlement": {"kind": "settled", "durationMs": 5},
            "timing": {"settleMs": 5}
          }
        }
        """)
    }

    func testDecodingRejectsImplicitSettledTrace() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "wait",
          "evidence": {
            "observation": {
              "kind": "trace",
              "accessibilityTrace": {"captures": []},
              "settlement": {"kind": "settled", "durationMs": 5}
            }
          }
        }
        """)
    }

    func testDecodingRejectsSiblingWarning() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "activate",
          "evidence": {"observation": {"kind": "none"}},
          "warning": {"code": "activation_weak_affordance_evidence"}
        }
        """)
    }

    func testDecodingRejectsFailureEvidenceWithSuccessOnlyWarning() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "failure", "errorKind": "actionFailed"},
          "method": "activate",
          "evidence": {
            "observation": {"kind": "none"},
            "warning": {"code": "activation_weak_affordance_evidence"}
          }
        }
        """)
    }

    func testDecodingRejectsWarningForIncompatibleMethod() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "syntheticTap",
          "evidence": {
            "observation": {"kind": "none"},
            "warning": {"code": "activation_weak_affordance_evidence"}
          }
        }
        """)
    }

    func testDecodingRejectsDuplicateSettlementTiming() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "wait",
          "evidence": {
            "observation": {"kind": "none"},
            "timing": {"settleMs": 5}
          }
        }
        """)
    }

    func testDecodingRejectsMalformedAnnouncementObservation() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "wait",
          "evidence": {
            "observation": {"kind": "announcement", "announcement": ""}
          }
        }
        """)
    }

    private func assertActionResultRejects(
        _ json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try JSONDecoder().decode(ActionResult.self, from: Data(json.utf8)),
            file: file,
            line: line
        )
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
