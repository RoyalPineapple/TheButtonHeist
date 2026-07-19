import XCTest
import ThePlans
@testable import TheScore

final class ActionResultEvidenceContractTests: XCTestCase {

    func testPackageConstructionDerivesMethodFromSemanticPayload() {
        let result = ActionResult(
            outcome: .success,
            payload: .typeText("typed"),
            message: nil,
            observation: .none,
            subjectEvidence: nil,
            activationTrace: nil
        )

        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.payload, .typeText("typed"))
    }

    func testEverySemanticPayloadOwnsItsActionMethod() {
        let cases: [(ActionResult.Payload, ActionMethod)] = [
            (.activate, .activate),
            (.increment, .increment),
            (.decrement, .decrement),
            (.dismiss, .dismiss),
            (.magicTap, .magicTap),
            (.oneFingerTap, .oneFingerTap),
            (.longPress, .longPress),
            (.swipe, .swipe),
            (.drag, .drag),
            (.typeText("text"), .typeText),
            (.customAction, .customAction),
            (.editAction, .editAction),
            (.dismissKeyboard, .dismissKeyboard),
            (.setPasteboard("text"), .setPasteboard),
            (.getPasteboard("text"), .getPasteboard),
            (.screenshot(nil), .takeScreenshot),
            (.rotor(nil), .rotor),
            (.heist(nil), .heistPlan),
            (.scroll, .scroll),
            (.scrollToVisible, .scrollToVisible),
            (.scrollToEdge, .scrollToEdge),
            (.wait, .wait),
        ]

        for (payload, method) in cases {
            XCTAssertEqual(ActionResult.success(payload: payload).method, method)
        }
    }

    func testEveryOutcomeRoundTripsWithEveryObservationCase() throws {
        let trace = traceWithAnnouncement("Ready")
        let complete = traceEvidence(trace, completeness: .complete)
        let incomplete = traceEvidence(trace, completeness: .incomplete)
        let observations: [ActionResultObservationEvidence] = [
            .none,
            .announcement("Ready"),
            .trace(complete),
            .trace(incomplete),
            .settledTrace(incomplete, .settled(duration: 12)),
        ]

        for observation in observations {
            let results = [
                ActionResult.success(
                    payload: .wait,
                    observation: observation
                ),
                ActionResult.failure(
                    payload: .wait,
                    failureKind: .timeout,
                    observation: observation
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
            payload: .activate,
            message: "done",
            observation: .settledTrace(traceEvidence, .settled(duration: 125)),
            subjectEvidence: try weakActivationSubjectEvidence(),
            timing: ActionPerformanceTiming(actionDispatchMs: 4)
        )

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let evidence = try XCTUnwrap(object["evidence"] as? [String: Any])
        let observation = try XCTUnwrap(evidence["observation"] as? [String: Any])
        let encodedTraceEvidence = try XCTUnwrap(observation["traceEvidence"] as? [String: Any])
        let settlement = try XCTUnwrap(observation["settlement"] as? [String: Any])
        let timing = try XCTUnwrap(evidence["timing"] as? [String: Any])

        XCTAssertEqual(Set(object.keys), Set(["outcome", "method", "message", "evidence"]))
        XCTAssertEqual(Set(evidence.keys), Set(["observation", "subjectEvidence", "timing", "warning"]))
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
        XCTAssertEqual(decoded.timing?.actionDispatchMs, 4)
        XCTAssertEqual(decoded.warning?.code, "activation_weak_affordance_evidence")
    }

    func testFailureEvidenceRoundTripsWithExplicitAbsence() throws {
        let result = ActionResult.failure(
            payload: .wait,
            failureKind: .timeout,
            message: "timed out",
        )

        let decoded = try JSONDecoder().decode(ActionResult.self, from: JSONEncoder().encode(result))

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.outcome, .failure(.timeout))
        XCTAssertNil(decoded.accessibilityTrace)
        XCTAssertNil(decoded.announcement)
        XCTAssertNil(decoded.warning)
        XCTAssertNil(decoded.evidence.subjectEvidence)
        XCTAssertNil(decoded.evidence.timing)
    }

    func testStandaloneAnnouncementIsTheOnlyAnnouncementFact() throws {
        let result = ActionResult.success(
            payload: .wait,
            observation: .announcement("Ready")
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
            payload: .activate,
            observation: .trace(traceEvidence(trace, completeness: .incomplete))
        )

        XCTAssertEqual(result.announcement, "Checkout")
        XCTAssertEqual(result.capturedAnnouncement, trace.capturedAnnouncements.first)
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
          "outcome": {"kind": "failure", "failureKind": "actionFailed"},
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

    func testAnnouncementAdmissionRejectsEmptySourceAndJSONValues() throws {
        XCTAssertThrowsError(try ActionAnnouncementText(validating: "")) { error in
            XCTAssertEqual(String(describing: error), "action announcement must not be empty")
        }
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

    func testSettlementDurationAdmissionRejectsNegativeSourceAndJSONValues() {
        XCTAssertThrowsError(try ActionSettlementDuration(validatingMilliseconds: -1)) { error in
            XCTAssertEqual(
                String(describing: error),
                "action settlement duration must not be negative"
            )
        }
        XCTAssertThrowsError(try JSONDecoder().decode(
            ActionSettlementEvidence.self,
            from: Data(#"{"kind":"settled","durationMs":-1}"#.utf8)
        ))
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

    private func weakActivationSubjectEvidence() throws -> ActionSubjectEvidence {
        let target = try AccessibilityTarget
            .predicate(ElementPredicateTemplate(label: "Checkout"))
            .resolve(in: .empty)
        return ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: HeistElement(
                description: "Checkout",
                label: "Checkout",
                value: nil,
                identifier: nil,
                traits: [.staticText],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                actions: []
            ),
            resolution: ActionSubjectResolution(origin: .visible)
        )
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
