import XCTest
import ThePlans
import TheScore

final class HeistElementTests: XCTestCase {

    func testEncodingRoundTrip() throws {
        let element = makeElement(label: "RoundTrip")

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(element, decoded)
    }

    func testActivationPointEvidenceCasesRoundTrip() throws {
        let cases: [ActivationPointEvidence] = [
            .explicit(ScreenPoint(x: 12, y: 34)),
            .defaultCenter(ScreenPoint(x: 50, y: 22)),
            .unavailable,
        ]

        for evidence in cases {
            let data = try JSONEncoder().encode(evidence)
            XCTAssertEqual(try JSONDecoder().decode(ActivationPointEvidence.self, from: data), evidence)
        }
    }

    func testEncodingUsesOnlyCanonicalActivationPointEvidence() throws {
        let element = HeistElement(
            description: "Save",
            label: "Save",
            value: nil,
            identifier: nil,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            activationPointEvidence: .explicit(ScreenPoint(x: 51, y: 22)),
            actions: []
        )

        let data = try JSONEncoder().encode(element)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let evidence = try XCTUnwrap(json["activationPointEvidence"] as? [String: Any])

        XCTAssertNil(json["activationPointX"])
        XCTAssertNil(json["activationPointY"])
        XCTAssertEqual(evidence["source"] as? String, "explicit")
        XCTAssertNotNil(evidence["point"])
    }

    func testElementWithAllFields() throws {
        let element = HeistElement(
            description: "A complex button",
            label: "Submit Form",
            value: "Enabled",
            identifier: "submit_button_id",
            frameX: 50, frameY: 100, frameWidth: 200, frameHeight: 60,
            actions: [.activate, .custom("Delete"), .custom("Edit"), .custom("Share")]
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(decoded.description, "A complex button")
        XCTAssertEqual(decoded.label, "Submit Form")
        XCTAssertEqual(decoded.value, "Enabled")
        XCTAssertEqual(decoded.identifier, "submit_button_id")
        XCTAssertEqual(decoded.actions, [.activate, .custom("Delete"), .custom("Edit"), .custom("Share")])
    }

    func testElementWithNilOptionals() throws {
        let element = HeistElement(
            description: "Minimal",
            label: nil,
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(element, decoded)
        XCTAssertNil(decoded.label)
        XCTAssertNil(decoded.value)
        XCTAssertNil(decoded.identifier)
    }

    func testUnavailableFrameEvidenceRoundTripsWithoutFabricatedCoordinates() throws {
        let element = HeistElement(
            description: "Unavailable",
            label: "Unavailable",
            value: nil,
            identifier: nil,
            frameEvidence: .unavailable,
            actions: []
        )

        let data = try JSONEncoder().encode(element)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertNil(object["frameX"])
        XCTAssertNil(object["frameY"])
        XCTAssertNil(object["frameWidth"])
        XCTAssertNil(object["frameHeight"])
        XCTAssertEqual(decoded.frameEvidence, .unavailable)
        XCTAssertNil(decoded.activationPointX)
        XCTAssertNil(decoded.activationPointY)
    }

    func testDecodeRejectsPartialOrInvalidFrameEvidence() {
        let invalidFrames = [
            #""frameX":0,"frameY":0,"frameWidth":100"#,
            #""frameX":0,"frameY":0,"frameWidth":-1,"frameHeight":44"#,
            #""frameX":"NaN","frameY":0,"frameWidth":100,"frameHeight":44"#,
        ]
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )

        for frame in invalidFrames {
            let json = """
            {
              "description": "Invalid",
              "traits": [],
              \(frame),
              "activationPointEvidence": {"source": "unavailable"},
              "respondsToUserInteraction": true,
              "actions": []
            }
            """
            XCTAssertThrowsError(try decoder.decode(HeistElement.self, from: Data(json.utf8)))
        }
    }

    func testElementWithRotorsRoundTrips() throws {
        let element = HeistElement(
            description: "Validation Results",
            label: "Validation Results",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 320, frameHeight: 400,
            rotors: [HeistRotor(name: "Errors"), HeistRotor(name: "Warnings")],
            actions: []
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(decoded.rotors, element.rotors)
    }

    func testActionsCanonicalizeAtConstructionBoundary() {
        let element = HeistElement(
            description: "Actions",
            label: "Actions",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.custom("Share"), .activate, .custom("Delete"), .activate, .typeText, .decrement, .increment]
        )

        XCTAssertEqual(element.actions, [.activate, .typeText, .increment, .decrement, .custom("Delete"), .custom("Share")])
    }

    func testActionsCanonicalizeAtDecodeBoundaryAndEncodeDeterministically() throws {
        let json = """
        {
          "description": "Actions",
          "label": "Actions",
          "traits": [],
          "frameX": 0,
          "frameY": 0,
          "frameWidth": 100,
          "frameHeight": 44,
          "activationPointEvidence": {"source": "unavailable"},
          "respondsToUserInteraction": true,
          "actions": [
            {"custom": "Share"},
            "activate",
            "typeText",
            {"custom": "Delete"},
            "activate"
          ]
        }
        """
        let decoded = try JSONDecoder().decode(HeistElement.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(decoded)
        let encodedProjection = try JSONDecoder().decode(EncodedElementActionsProjection.self, from: encoded)

        XCTAssertEqual(decoded.actions, [.activate, .typeText, .custom("Delete"), .custom("Share")])
        XCTAssertEqual(encodedProjection.actions, [.activate, .typeText, .custom("Delete"), .custom("Share")])
    }

    func testDecodeRejectsLegacyActivationPointCoordinates() {
        let json = """
        {
          "description": "Save",
          "label": "Save",
          "traits": [],
          "frameX": 0,
          "frameY": 0,
          "frameWidth": 100,
          "frameHeight": 44,
          "activationPointX": 50,
          "activationPointY": 22,
          "respondsToUserInteraction": true,
          "actions": []
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistElement.self, from: Data(json.utf8)))
    }

    // MARK: - Helpers

    private func makeElement(label: String) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
    }

    private struct EncodedElementActionsProjection: Decodable {
        let actions: [ElementAction]
    }
}
