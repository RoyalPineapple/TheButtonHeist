import XCTest
@testable import TheScore

final class HeistPlaybackTests: XCTestCase {

    // MARK: - Heist Playback Round-Trip

    func testHeistRoundTrip() throws {
        let heist = HeistPlayback(
            app: "com.buttonheist.testapp",
            steps: [
                try HeistStep(command: "activate", target: semanticTarget(label: "Login", traits: [.button])),
                try HeistStep(command: "type_text", arguments: ["text": .string("user@example.com")]),
                try HeistStep(command: "activate", target: semanticTarget(label: "Submit", traits: [.button])),
            ]
        )

        let data = try JSONEncoder().encode(heist)
        let decoded = try JSONDecoder().decode(HeistPlayback.self, from: data)

        XCTAssertEqual(decoded.version, HeistPlayback.currentVersion)
        XCTAssertEqual(decoded.app, "com.buttonheist.testapp")
        XCTAssertEqual(decoded.steps.count, 3)
        XCTAssertEqual(decoded.steps[0].command, "activate")
        XCTAssertEqual(decoded.steps[0].target, semanticTarget(label: "Login", traits: [.button]))
        XCTAssertEqual(decoded.steps[1].command, "type_text")
        XCTAssertEqual(decoded.steps[1].arguments["text"], .string("user@example.com"))
        XCTAssertNil(decoded.steps[1].target)
    }

    func testDecodeRejectsUnsupportedVersionAtBoundary() {
        let json = """
        {
          "version": \(HeistPlayback.currentVersion + 1),
          "app": "com.buttonheist.testapp",
          "steps": []
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlayback.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("Unsupported heist file version"))
            XCTAssertTrue(context.debugDescription.contains("supports version \(HeistPlayback.currentVersion)"))
        }
    }

    func testDecodeRejectsUnknownTopLevelPlaybackField() {
        let json = """
        {
          "version": \(HeistPlayback.currentVersion),
          "app": "com.buttonheist.testapp",
          "steps": [],
          "unexpectedField": {}
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlayback.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("Unknown heist playback field \"unexpectedField\""))
        }
    }

    // MARK: - Heist Step Target Encoding

    func testStepEncodesTargetObject() throws {
        let step = try HeistStep(
            command: "swipe",
            target: semanticTarget(label: "List", traits: [.adjustable]),
            arguments: ["direction": .string("up")]
        )

        let data = try JSONEncoder().encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["command"] as? String, "swipe")
        XCTAssertNil(json?["_recorded"])
        let arguments = try XCTUnwrap(json?["arguments"] as? [String: Any])
        XCTAssertEqual(arguments["direction"] as? String, "up")
        let target = try XCTUnwrap(json?["target"] as? [String: Any])
        XCTAssertEqual(target["label"] as? String, "List")
        XCTAssertEqual(target["traits"] as? [String], ["adjustable"])
    }

    func testStepRoundTripsTarget() throws {
        let original = try HeistStep(
            command: "activate",
            target: semanticTarget(label: "Submit", traits: [.button])
        )
        let data = try JSONEncoder().encode(original)
        let step = try JSONDecoder().decode(HeistStep.self, from: data)

        XCTAssertEqual(step.command, "activate")
        XCTAssertEqual(step.target, semanticTarget(label: "Submit", traits: [.button]))
        XCTAssertTrue(step.arguments.isEmpty)
    }

    func testPlaybackTargetRejectsHeistIdAsDurableIdentity() {
        let json = #"{"command":"activate","target":{"heistId":"button_save"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("heistId"), "\(error)")
        }
    }

    func testPlaybackTargetRejectsEmptyMatcherOnDecode() {
        let json = #"{"command":"activate","target":{}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("requires heistId or matcher"), "\(error)")
        }
    }

    func testPlaybackTargetRejectsUnknownTargetField() {
        let json = #"{"command":"activate","target":{"label":"Save","unexpectedTargetField":"button_save"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedTargetField"), "\(error)")
        }
    }

    func testStepRejectsRecordingMetadata() {
        let json = #"{"command":"activate","target":{"label":"Save"},"_recorded":{"heistId":"button_save"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("_recorded"), "\(error)")
        }
    }

    func testStepWithNoTarget() throws {
        let original = try HeistStep(
            command: "type_text",
            arguments: ["text": .string("hello")]
        )
        let data = try JSONEncoder().encode(original)
        let step = try JSONDecoder().decode(HeistStep.self, from: data)

        XCTAssertEqual(step.command, "type_text")
        XCTAssertNil(step.target)
        XCTAssertEqual(step.arguments["text"], .string("hello"))
    }

    func testStepRejectsUnknownTopLevelField() {
        let json = #"{"command":"activate","unexpectedStepField":"button_save"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedStepField"), "\(error)")
        }
    }

    func testStepRejectsBoundaryFieldsInsideArguments() {
        let keys = ["command", "target", "expect", "requestId"]
        for key in keys {
            let json = #"{"command":"activate","arguments":{"\#(key)":"value"}}"#
            XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8)), key) { error in
                XCTAssertTrue("\(error)".contains("arguments.\(key)"), "\(error)")
            }
        }
    }

    func testStepRejectsNegativeOrdinal() throws {
        let step = try HeistStep(
            command: "activate",
            target: semanticTarget(label: "Save", ordinal: -1)
        )
        let data = try JSONEncoder().encode(step)

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("ordinal must be non-negative"))
        }
    }

    func testCurrentVersionIsSix() {
        XCTAssertEqual(HeistPlayback.currentVersion, 6)
    }

    // MARK: - Heist Value

    func testHeistValueRoundTrips() throws {
        let values: [HeistValue] = [
            .string("hello"),
            .int(42),
            .double(3.14),
            .bool(true),
            .array([.string("a"), .int(1)]),
            .object(["key": .string("val")]),
        ]

        for original in values {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(HeistValue.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }

    func testHeistValueDescriptionIsDeterministicAndQuoted() {
        let value = HeistValue.object([
            "text": .string(#"Save "Now""#),
            "count": .int(2),
            "flags": .array([.bool(true), .double(3.5)]),
        ])

        XCTAssertEqual(value.description, #"{"count"=2, "flags"=[true, 3.5], "text"="Save \"Now\""}"#)
    }

    func testHeistStepDescriptionComposesTargetAndArguments() throws {
        let step = try HeistStep(
            command: "activate",
            target: semanticTarget(label: "Save", traits: [.button]),
            arguments: [
                "count": .int(2),
                "text": .string("hello"),
            ]
        )

        let expected = #"step(command="activate" target(matcher(label="Save" traits=[button])) "#
            + #"args=arguments("count"=2 "text"="hello"))"#
        XCTAssertEqual(step.description, expected)
    }

    func testProgrammaticStepRejectsCaptureHandleTargetWithoutCrashing() {
        XCTAssertThrowsError(try HeistStep(command: "activate", target: .heistId("button_save"))) { error in
            XCTAssertEqual(error as? HeistStepError, .captureHandleTarget)
        }
    }

    func testProgrammaticStepRejectsEmptyMatcherTargetWithoutCrashing() {
        XCTAssertThrowsError(try HeistStep(command: "activate", target: .matcher(ElementMatcher()))) { error in
            XCTAssertEqual(error as? HeistStepError, .emptyMatcherTarget)
        }
    }

    func testProgrammaticStepRejectsBoundaryFieldsInsideArguments() {
        XCTAssertThrowsError(try HeistStep(command: "activate", arguments: ["expect": .string("screen_changed")])) { error in
            XCTAssertEqual(error as? HeistStepError, .reservedArgumentKey("expect"))
        }
    }

    // MARK: - Full Heist JSON Shape

    func testFullHeistJsonShape() throws {
        let heist = HeistPlayback(
            app: "com.example.app",
            steps: [
                try HeistStep(
                    command: "activate",
                    target: semanticTarget(label: "Go", traits: [.button])
                ),
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(heist)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["version"] as? Int, HeistPlayback.currentVersion)
        XCTAssertEqual(json?["app"] as? String, "com.example.app")
        XCTAssertNil(json?["recorded"])

        let steps = json?["steps"] as? [[String: Any]]
        XCTAssertEqual(steps?.count, 1)

        let firstStep = steps?.first
        XCTAssertEqual(firstStep?["command"] as? String, "activate")
        XCTAssertNil(firstStep?["_recorded"])
        let target = try XCTUnwrap(firstStep?["target"] as? [String: Any])
        XCTAssertEqual(target["label"] as? String, "Go")
    }

    private func semanticTarget(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait]? = nil,
        excludeTraits: [HeistTrait]? = nil,
        ordinal: Int? = nil
    ) -> ElementTarget {
        .matcher(
            ElementMatcher(
                label: label,
                identifier: identifier,
                value: value,
                traits: traits,
                excludeTraits: excludeTraits
            ),
            ordinal: ordinal
        )
    }
}
