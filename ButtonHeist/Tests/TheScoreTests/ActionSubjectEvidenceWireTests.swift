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
            semantics: HeistElement.Semantics(
                spokenDescription: "Delete",
                assertable: HeistElement.Semantics.AssertableProperties(
                    label: "Delete",
                    value: nil,
                    identifier: "delete_button",
                    traits: [.button],
                    actions: [.activate]
                ),
                respondsToUserInteraction: true
            ),
            geometry: HeistElement.Geometry(
                screen: .onscreen(
                    frame: .available(ScreenRect(x: 10, y: 20, width: 100, height: 44)),
                    activationPoint: .unavailable
                ),
                view: HeistElement.Geometry.ViewSpace(
                    ownerPath: .root,
                    frame: ViewRect(x: 10, y: 20, width: 100, height: 44),
                    activationPoint: nil
                )
            )
        )
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: element,
            resolution: ActionSubjectResolution(
                origin: .known,
                adjustments: [.semanticReveal, .objectDeallocationRefresh]
            )
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
        let semantics = try encodedElement.object("semantics")
        let assertable = try semantics.object("assertable")
        XCTAssertEqual(try assertable.string("identifier"), "delete_button")
        _ = try encodedElement.object("geometry")
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
            "semantics": {
              "spokenDescription": "Delete",
              "assertable": {
                "label": "Delete",
                "traits": ["button"],
                "customContent": [],
                "rotors": [],
                "actions": ["activate"]
              },
              "respondsToUserInteraction": true
            },
            "geometry": {
              "screen": {"visibility": "offscreen"},
              "view": {"ownerPath": {"indices": []}}
            }
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
            "semantics": {
              "spokenDescription": "Delete",
              "assertable": {
                "label": "Delete",
                "traits": ["button"],
                "customContent": [],
                "rotors": [],
                "actions": ["activate"]
              },
              "respondsToUserInteraction": true
            },
            "geometry": {
              "screen": {"visibility": "offscreen"},
              "view": {"ownerPath": {"indices": []}}
            }
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
