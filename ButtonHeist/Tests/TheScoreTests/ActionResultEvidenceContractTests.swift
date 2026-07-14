import XCTest
@testable import TheScore

final class ActionResultEvidenceContractTests: XCTestCase {

    func testEveryOutcomeRoundTripsWithEveryObservationCase() throws {
        let trace = traceWithAnnouncement("Ready")
        let complete = traceEvidence(trace, completeness: .complete)
        let incomplete = traceEvidence(trace, completeness: .incomplete)
        let observations: [ActionResultObservationEvidence] = [
            .none,
            .announcement("Ready"),
            .trace(complete),
            .trace(incomplete),
            .settledTrace(incomplete, .settled(durationMs: 12)),
        ]

        for observation in observations {
            let results = [
                ActionResult.success(
                    method: .wait,
                    evidence: ActionResultSuccessEvidence(observation: observation)
                ),
                ActionResult.failure(
                    method: .wait,
                    errorKind: .timeout,
                    evidence: ActionResultFailureEvidence(observation: observation)
                ),
            ]
            for result in results {
                let decoded = try JSONDecoder().decode(ActionResult.self, from: JSONEncoder().encode(result))
                XCTAssertEqual(decoded, result)
            }
        }
    }

    func testSuccessEvidenceRoundTripsWithCanonicalShape() throws {
        let trace = traceWithAnnouncement("Checkout")
        let traceEvidence = traceEvidence(trace, completeness: .incomplete)
        let result = ActionResult.success(
            method: .activate,
            message: "done",
            evidence: ActionResultSuccessEvidence(
                observation: .settledTrace(traceEvidence, .settled(durationMs: 125)),
                timing: ActionPerformanceTiming(actionDispatchMs: 4),
                warning: .activationWeakAffordance(evidence: "label=Checkout")
            )
        )

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let evidence = try XCTUnwrap(object["evidence"] as? [String: Any])
        let observation = try XCTUnwrap(evidence["observation"] as? [String: Any])
        let encodedTraceEvidence = try XCTUnwrap(observation["traceEvidence"] as? [String: Any])
        let settlement = try XCTUnwrap(observation["settlement"] as? [String: Any])
        let timing = try XCTUnwrap(evidence["timing"] as? [String: Any])

        XCTAssertEqual(Set(object.keys), Set(["outcome", "method", "message", "evidence"]))
        XCTAssertEqual(Set(evidence.keys), Set(["observation", "timing", "warning"]))
        XCTAssertEqual(observation["kind"] as? String, "settledTrace")
        XCTAssertEqual(Set(observation.keys), Set(["kind", "traceEvidence", "settlement"]))
        XCTAssertEqual(Set(encodedTraceEvidence.keys), Set(["accessibilityTrace", "completeness"]))
        XCTAssertNotNil(encodedTraceEvidence["accessibilityTrace"])
        XCTAssertEqual(encodedTraceEvidence["completeness"] as? String, "incomplete")
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
        XCTAssertEqual(decoded.evidence, .failure(.timeout, .none))
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
            evidence: ActionResultSuccessEvidence(
                observation: .trace(traceEvidence(trace, completeness: .incomplete))
            )
        )

        XCTAssertEqual(result.announcement, "Checkout")
        XCTAssertEqual(result.capturedAnnouncement, trace.capturedAnnouncements.first)
    }

    func testWithTimingUpdatesSettlementOwnerWithoutStoringDuplicate() {
        let trace = traceWithAnnouncement("Checkout")
        let traceEvidence = traceEvidence(trace, completeness: .incomplete)
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .settledTrace(traceEvidence, .settled(durationMs: 5)),
                timing: ActionPerformanceTiming(actionDispatchMs: 1)
            )
        )

        let timed = result.withTiming(ActionPerformanceTiming(actionDispatchMs: 2, settleMs: 8))

        XCTAssertEqual(timed.evidence.settlement?.durationMs, 8)
        XCTAssertNil(timed.evidence.timing?.settleMs)
        XCTAssertEqual(timed.timing?.actionDispatchMs, 2)
        XCTAssertEqual(timed.timing?.settleMs, 8)
    }

    func testObservationDiscriminatorRejectsFieldsFromAnotherCase() {
        assertActionResultRejects("""
        {
          "outcome": {"kind": "success"},
          "method": "wait",
          "evidence": {
            "observation": {"kind": "none", "announcement": "Ready"}
          }
        }
        """)
    }

    func testFailureEvidenceRejectsSuccessOnlyWarning() {
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

    func testEvidenceDecodingRejectsSettlementTimingOutsideObservation() {
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

    func testEvidenceDecodingRejectsEmptyAnnouncement() throws {
        let json = """
        {
          "outcome": {"kind": "success"},
          "method": "wait",
          "evidence": {
            "observation": {"kind": "announcement", "announcement": ""}
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ActionResult.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
            }
        }
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

    private func traceEvidence(
        _ trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(trace: trace, completeness: completeness) else {
            preconditionFailure("test trace evidence requires a current capture")
        }
        return evidence
    }
}
