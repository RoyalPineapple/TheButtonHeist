import ButtonHeistTestSupport
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
            activationTrace: nil,
            timing: nil
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
        let complete = observationEvidenceWithAnnouncement("Ready", coverage: .complete)
        let incomplete = observationEvidenceWithAnnouncement("Ready", coverage: .incomplete(.historyUnavailable))
        let observations: [ActionResultObservationEvidence] = [
            .none,
            .observed(complete),
            .observed(incomplete),
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
        let observationEvidence = observationEvidenceWithAnnouncement(
            "Checkout",
            coverage: .incomplete(.historyUnavailable)
        )
        let result = ActionResult.activationSuccess(
            message: "done",
            observation: .observed(observationEvidence),
            subjectEvidence: try weakActivationSubjectEvidence(),
            activationTrace: ActivationTrace(.activationPointFallback(
                axActivateReturned: false,
                tapActivationPoint: ScreenPoint(x: 50, y: 50),
                tapActivationSucceeded: true
            ), implementsAccessibilityActivation: false),
            timing: ActionPerformanceTiming(actionDispatchMs: 4)
        )

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let evidence = try XCTUnwrap(object["evidence"] as? [String: Any])
        let observation = try XCTUnwrap(evidence["observation"] as? [String: Any])
        let encodedObservationEvidence = try XCTUnwrap(
            observation["observationEvidence"] as? [String: Any]
        )
        let timing = try XCTUnwrap(evidence["timing"] as? [String: Any])

        XCTAssertEqual(Set(object.keys), Set(["outcome", "method", "message", "evidence"]))
        XCTAssertEqual(
            Set(evidence.keys),
            Set(["observation", "subjectEvidence", "activationTrace", "timing", "warning"])
        )
        XCTAssertEqual(observation["kind"] as? String, "observed")
        XCTAssertEqual(Set(observation.keys), Set(["kind", "observationEvidence"]))
        XCTAssertEqual(
            Set(encodedObservationEvidence.keys),
            Set(["baseline", "current", "events", "coverage"])
        )
        let coverage = try XCTUnwrap(encodedObservationEvidence["coverage"] as? [String: Any])
        let incomplete = try XCTUnwrap(coverage["incomplete"] as? [String: Any])
        let gap = try XCTUnwrap(incomplete["_0"] as? [String: Any])
        XCTAssertNotNil(gap["historyUnavailable"] as? [String: Any])
        XCTAssertEqual(timing["actionDispatchMs"] as? Int, 4)

        let decoded = try JSONDecoder().decode(ActionResult.self, from: encoded)
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.announcement, "Checkout")
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
        XCTAssertNil(decoded.observationEvidence)
        XCTAssertNil(decoded.announcement)
        XCTAssertNil(decoded.warning)
        XCTAssertNil(decoded.evidence.subjectEvidence)
        XCTAssertNil(decoded.evidence.timing)
    }

    func testScreenActionHandlerIsSuccessEvidence() throws {
        let result = ActionResult(
            outcome: .success,
            payload: .dismiss,
            message: nil,
            observation: .none,
            subjectEvidence: nil,
            activationTrace: nil,
            screenActionHandler: "UINavigationController",
            timing: nil
        )

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let evidence = try XCTUnwrap(object["evidence"] as? [String: Any])

        XCTAssertNil(object["message"])
        XCTAssertEqual(evidence["screenActionHandler"] as? String, "UINavigationController")

        let decoded = try JSONDecoder().decode(ActionResult.self, from: encoded)
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.screenActionHandler, "UINavigationController")
    }

    func testObservationEvidenceOwnsCapturedNotificationText() {
        let observationEvidence = observationEvidenceWithAnnouncement(
            "Checkout",
            coverage: .incomplete(.historyUnavailable)
        )
        let result = ActionResult.success(
            payload: .activate,
            observation: .observed(observationEvidence)
        )

        XCTAssertEqual(result.announcement, "Checkout")
        XCTAssertEqual(result.observationEvidence, observationEvidence)
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

    func testElapsedMillisecondsAdmissionRejectsNegativeSourceAndJSONValues() {
        XCTAssertThrowsError(try ElapsedMilliseconds(validatingMilliseconds: -1)) { error in
            XCTAssertEqual(
                String(describing: error),
                "elapsed milliseconds must not be negative"
            )
        }
    }

    func testActionPerformanceTimingRejectsEveryNegativeWireField() {
        for key in [
            "targetResolutionMs",
            "actionDispatchMs",
            "interactionMs",
            "totalMs",
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(
                ActionPerformanceTiming.self,
                from: Data(#"{"\#(key)":-1}"#.utf8)
            ))
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

    private func observationEvidenceWithAnnouncement(
        _ text: String,
        coverage: Observation.Coverage
    ) -> Observation.Evidence {
        let baseline = makeTestObservationSnapshot(
            elements: [],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let current = makeTestObservationSnapshot(
            elements: [],
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let notification = Observation.Notification(text: text, element: nil)
        return makeTestObservationEvidence(
            baseline: baseline,
            current: current,
            events: notification.map { [.notification($0)] } ?? [],
            coverage: coverage
        )
    }

    private func weakActivationSubjectEvidence() throws -> ActionSubjectEvidence {
        let target = try AccessibilityTarget
            .predicate(ElementPredicate(label: "Checkout"))
            .resolve(in: .empty)
        return ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: makeTestHeistElement(
                description: "Checkout",
                label: "Checkout",
                traits: [.staticText],
                actions: []
            ),
            resolution: ActionSubjectResolution(origin: .visible)
        )
    }
}
