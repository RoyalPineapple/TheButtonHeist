import ButtonHeistTestSupport
import XCTest
import ThePlans
import TheScore

final class ActionSubjectEvidenceWireTests: XCTestCase {
    func testActionResultSubjectEvidenceWireShape() throws {
        let target = try AccessibilityTarget
            .predicate(ElementPredicate(label: "Delete", traits: [.button]))
            .resolve(in: .empty)
        let element = HeistElement(
            description: "Delete",
            label: "Delete",
            value: nil,
            identifier: "delete_button",
            traits: [.button],
            frameX: 10,
            frameY: 20,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: element,
            resolution: ActionSubjectResolution(
                origin: .known,
                adjustments: [.semanticReveal, .objectDeallocationRefresh]
            ),
            settledObservationSequence: 12
        )
        let result = ActionResult.success(
            payload: .activate,
                observation: .none,
                subjectEvidence: evidence

        )

        let data = try JSONEncoder().encode(result)
        let json = try JSONProbe(data: data)
        let subjectEvidence = try json.object("evidence").object("subjectEvidence")
        XCTAssertEqual(try subjectEvidence.string("source"), "resolvedSemanticTarget")
        XCTAssertEqual(try subjectEvidence.string("phase"), "resolvedBeforeDispatch")
        XCTAssertEqual(try subjectEvidence.int("settledObservationSequence"), 12)
        let resolution = try subjectEvidence.object("resolution")
        XCTAssertEqual(try resolution.string("origin"), "known")
        XCTAssertEqual(
            try resolution.strings("adjustments"),
            ["semanticReveal", "objectDeallocationRefresh"]
        )
        let encodedTarget = try subjectEvidence.object("target")
        let checks = try encodedTarget.array("checks")
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(try checks[0].string("kind"), "label")
        let labelMatch = try checks[0].object("match")
        XCTAssertEqual(try labelMatch.string("mode"), "exact")
        XCTAssertEqual(try labelMatch.string("value"), "Delete")
        XCTAssertEqual(try checks[1].string("kind"), "traits")
        XCTAssertEqual(try checks[1].strings("values"), ["button"])
        let encodedElement = try subjectEvidence.object("element")
        XCTAssertEqual(try encodedElement.string("identifier"), "delete_button")
        XCTAssertNoThrow(try encodedElement.assertMissing("heistId"), "subject evidence must not expose runtime ids")

        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.subjectEvidence, evidence)
    }

    func testActionSubjectResolutionRoundTripsWithDeterministicAdjustmentOrdering() throws {
        let resolution = ActionSubjectResolution(
            origin: .discovered,
            adjustments: [
                .staleTargetRefresh,
                .activationPointPlacement,
                .semanticReveal,
                .objectDeallocationRefresh,
            ]
        )

        let data = try JSONEncoder().encode(resolution)
        let json = try JSONProbe(data: data)
        XCTAssertEqual(try json.string("origin"), "discovered")
        XCTAssertEqual(
            try json.strings("adjustments"),
            [
                "semanticReveal",
                "activationPointPlacement",
                "objectDeallocationRefresh",
                "staleTargetRefresh",
            ]
        )
        XCTAssertEqual(try JSONDecoder().decode(ActionSubjectResolution.self, from: data), resolution)
    }

    func testActionSubjectEvidenceRejectsMissingResolution() throws {
        let json = Data("""
        {
          "source": "resolvedSemanticTarget",
          "phase": "resolvedBeforeDispatch",
          "target": { "checks": [{ "kind": "label", "match": { "mode": "exact", "value": "Delete" } }] },
          "element": {
            "description": "Delete",
            "label": "Delete",
            "traits": ["button"],
            "frameX": 0,
            "frameY": 0,
            "frameWidth": 100,
            "frameHeight": 44,
            "activationPointEvidence": {"source": "unavailable"},
            "respondsToUserInteraction": true,
            "actions": ["activate"]
          }
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionSubjectEvidence.self, from: json)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("Expected missing resolution key, got \(error)")
            }
            XCTAssertEqual(key.stringValue, "resolution")
        }
    }

    func testActionSubjectResolutionRejectsUnknownAdjustment() throws {
        let json = Data("""
        {
          "origin": "visible",
          "adjustments": ["semanticReveal", "legacyRefresh"]
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionSubjectResolution.self, from: json))
    }

    func testActionSubjectEvidenceRejectsUnknownFields() throws {
        let json = Data("""
        {
          "source": "resolvedSemanticTarget",
          "phase": "resolvedBeforeDispatch",
          "target": { "checks": [{ "kind": "label", "match": { "mode": "exact", "value": "Delete" } }] },
          "element": {
            "description": "Delete",
            "label": "Delete",
            "traits": ["button"],
            "frameX": 0,
            "frameY": 0,
            "frameWidth": 100,
            "frameHeight": 44,
            "activationPointEvidence": {"source": "unavailable"},
            "respondsToUserInteraction": true,
            "actions": ["activate"]
          },
          "resolution": {"origin": "visible", "adjustments": []},
          "heistId": "old-runtime-id"
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionSubjectEvidence.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("Unknown ActionSubjectEvidence field"))
        }
    }
}
