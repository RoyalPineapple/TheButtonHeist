import XCTest
@testable import TheScore

final class HeistPlaybackTests: XCTestCase {

    // MARK: - Heist Playback Round-Trip

    func testScriptRoundTrip() throws {
        let script = HeistPlayback(
            recorded: Date(timeIntervalSince1970: 1_000_000),
            app: "com.buttonheist.testapp",
            steps: [
                HeistEvidence(command: "activate", target: semanticTarget(label: "Login", traits: [.button])),
                HeistEvidence(command: "type_text", arguments: ["text": .string("user@example.com")]),
                HeistEvidence(command: "activate", target: semanticTarget(label: "Submit", traits: [.button])),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(script)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HeistPlayback.self, from: data)

        XCTAssertEqual(decoded.version, HeistPlayback.currentVersion)
        XCTAssertEqual(decoded.app, "com.buttonheist.testapp")
        XCTAssertEqual(decoded.steps.count, 3)
        XCTAssertEqual(decoded.steps[0].command, "activate")
        XCTAssertEqual(decoded.steps[0].target?.matcher.label, "Login")
        XCTAssertEqual(decoded.steps[0].target?.matcher.traits, [.button])
        XCTAssertEqual(decoded.steps[1].command, "type_text")
        XCTAssertEqual(decoded.steps[1].arguments["text"], .string("user@example.com"))
        XCTAssertNil(decoded.steps[1].target)
    }

    func testDecodeRejectsUnsupportedVersionAtBoundary() throws {
        let json = """
        {
          "version": \(HeistPlayback.currentVersion + 1),
          "recorded": "2026-05-27T12:00:00Z",
          "app": "com.buttonheist.testapp",
          "steps": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(try decoder.decode(HeistPlayback.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("Unsupported heist file version"))
            XCTAssertTrue(context.debugDescription.contains("supports version \(HeistPlayback.currentVersion)"))
        }
    }

    func testDecodeRejectsUnknownTopLevelPlaybackField() throws {
        let json = """
        {
          "version": \(HeistPlayback.currentVersion),
          "recorded": "2026-05-27T12:00:00Z",
          "app": "com.buttonheist.testapp",
          "steps": [],
          "projection": {}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(try decoder.decode(HeistPlayback.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("Unknown heist playback field \"projection\""))
        }
    }

    // MARK: - Heist Step Target Encoding

    func testStepEncodesTargetObject() throws {
        let step = HeistEvidence(
            command: "swipe",
            target: semanticTarget(label: "List", traits: [.adjustable]),
            arguments: ["direction": .string("up")]
        )

        let data = try JSONEncoder().encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["command"] as? String, "swipe")
        let arguments = try XCTUnwrap(json?["arguments"] as? [String: Any])
        XCTAssertEqual(arguments["direction"] as? String, "up")
        let target = try XCTUnwrap(json?["target"] as? [String: Any])
        XCTAssertEqual(target["label"] as? String, "List")
        XCTAssertEqual(target["traits"] as? [String], ["adjustable"])
    }

    func testStepRoundTripsTarget() throws {
        let original = HeistEvidence(
            command: "activate",
            target: semanticTarget(label: "Submit", traits: [.button])
        )
        let data = try JSONEncoder().encode(original)
        let step = try JSONDecoder().decode(HeistEvidence.self, from: data)

        XCTAssertEqual(step.command, "activate")
        XCTAssertEqual(step.target?.matcher.label, "Submit")
        XCTAssertEqual(step.target?.matcher.traits, [.button])
        XCTAssertTrue(step.arguments.isEmpty)
    }

    func testPlaybackTargetRejectsHeistIdAsDurableIdentity() {
        let json = #"{"command":"activate","target":{"heistId":"button_save"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistEvidence.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("heistId"), "\(error)")
        }
    }

    func testPlaybackTargetRejectsUnknownTargetField() {
        let json = #"{"command":"activate","target":{"label":"Save","unexpectedTargetField":"button_save"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistEvidence.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedTargetField"), "\(error)")
        }
    }

    func testStepWithNoTarget() throws {
        let original = HeistEvidence(
            command: "type_text",
            arguments: ["text": .string("hello")]
        )
        let data = try JSONEncoder().encode(original)
        let step = try JSONDecoder().decode(HeistEvidence.self, from: data)

        XCTAssertEqual(step.command, "type_text")
        XCTAssertNil(step.target)
        XCTAssertEqual(step.arguments["text"], .string("hello"))
    }

    func testStepAllowsRecordedHeistIdMetadata() throws {
        let original = HeistEvidence(
            command: "activate",
            target: semanticTarget(label: "Save"),
            recorded: RecordedMetadata(heistId: "recorded_save")
        )
        let data = try JSONEncoder().encode(original)
        let step = try JSONDecoder().decode(HeistEvidence.self, from: data)

        XCTAssertEqual(step.target?.matcher.label, "Save")
        XCTAssertEqual(step.recorded?.heistId, "recorded_save")
        XCTAssertNil(step.arguments["heistId"])
    }

    func testStepRejectsUnknownTopLevelField() {
        let json = #"{"command":"activate","unexpectedStepField":"button_save"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(HeistEvidence.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedStepField"), "\(error)")
        }
    }

    func testStepRejectsNegativeOrdinal() throws {
        let step = HeistEvidence(
            command: "activate",
            target: semanticTarget(label: "Save", ordinal: -1)
        )
        let data = try JSONEncoder().encode(step)

        XCTAssertThrowsError(try JSONDecoder().decode(HeistEvidence.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("ordinal must be non-negative"))
        }
    }

    func testStepWithRecordedMetadata() throws {
        let step = HeistEvidence(
            command: "activate",
            target: semanticTarget(label: "Save", traits: [.button]),
            recorded: RecordedMetadata(
                heistId: "button_save",
                frame: RecordedFrame(x: 20, y: 680, width: 350, height: 44)
            )
        )

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(HeistEvidence.self, from: data)

        XCTAssertEqual(decoded.recorded?.heistId, "button_save")
        XCTAssertEqual(decoded.recorded?.frame?.x, 20)
        XCTAssertEqual(decoded.recorded?.frame?.width, 350)
        XCTAssertNil(decoded.recorded?.coordinateOnly)
    }

    func testStepWithRecordedAccessibilityTraceDerivesDeltaWithoutEncodingIt() throws {
        let before = makeTestInterface(
            elements: [makeElement(heistId: "before", label: "Before")],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let after = makeTestInterface(
            elements: [makeElement(heistId: "continue", label: "Continue")],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let step = HeistEvidence(
            command: "activate",
            target: semanticTarget(label: "Continue", traits: [.button]),
            recorded: RecordedMetadata(
                accessibilityTrace: AccessibilityTrace(first: before).appending(
                    after,
                    transition: .init(screenChangeReason: "explicitSignal")
                ),
                expectation: ExpectationResult(
                    met: true,
                    expectation: .screenChanged,
                    actual: "screenChanged"
                )
            )
        )

        let data = try JSONEncoder().encode(step)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let recorded = try XCTUnwrap(json["_recorded"] as? [String: Any])
        XCTAssertNil(recorded["accessibilityDelta"])

        let decoded = try JSONDecoder().decode(HeistEvidence.self, from: data)

        let change = try XCTUnwrap(decoded.recorded?.accessibilityTrace?.receipts.first)
        XCTAssertEqual(change.kind, AccessibilityTrace.ReceiptKind.capture)
        XCTAssertEqual(change.interface.elements.first?.label, "Before")
        XCTAssertEqual(decoded.recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
        XCTAssertEqual(decoded.recorded?.accessibilityDelta?.elementCount, 1)
        XCTAssertEqual(decoded.recorded?.expectation?.met, true)
    }

    func testCurrentVersionIsFour() {
        XCTAssertEqual(HeistPlayback.currentVersion, 4)
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

    // MARK: - RecordedMetadata

    func testRecordedMetadataRoundTrip() throws {
        let metadata = RecordedMetadata(
            heistId: "button_submit",
            frame: RecordedFrame(x: 10, y: 20, width: 100, height: 44),
            coordinateOnly: false
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(RecordedMetadata.self, from: data)

        XCTAssertEqual(decoded.heistId, "button_submit")
        XCTAssertEqual(decoded.frame?.x, 10)
        XCTAssertEqual(decoded.frame?.height, 44)
        XCTAssertEqual(decoded.coordinateOnly, false)
    }

    func testRecordedMetadataCoordinateOnly() throws {
        let metadata = RecordedMetadata(coordinateOnly: true)
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(RecordedMetadata.self, from: data)

        XCTAssertNil(decoded.heistId)
        XCTAssertNil(decoded.frame)
        XCTAssertEqual(decoded.coordinateOnly, true)
    }

    func testHeistEvidenceDescriptionComposesTargetArgumentsAndRecording() {
        let step = HeistEvidence(
            command: "activate",
            target: semanticTarget(label: "Save", traits: [.button]),
            arguments: [
                "count": .int(2),
                "text": .string("hello"),
            ],
            recorded: RecordedMetadata(
                heistId: "save_button",
                frame: RecordedFrame(x: 1, y: 2, width: 3, height: 4),
                coordinateOnly: false,
                expectation: ExpectationResult(met: true, expectation: .screenChanged, actual: "screenChanged")
            )
        )

        let expected = #"step(command="activate" semanticTarget(matcher(label="Save" traits=[button])) "#
            + #"args=arguments("count"=2 "text"="hello") "#
            + #"recorded(heistId="save_button" frame(1,2,3,4) coordinateOnly=false "#
            + #"expectation(met=true expected=screen_changed actual="screenChanged")))"#
        XCTAssertEqual(step.description, expected)
    }

    // MARK: - Full Heist JSON Shape

    func testFullScriptJsonShape() throws {
        let script = HeistPlayback(
            recorded: Date(timeIntervalSince1970: 1_000_000),
            app: "com.example.app",
            steps: [
                HeistEvidence(
                    command: "activate",
                    target: semanticTarget(label: "Go", traits: [.button]),
                    recorded: RecordedMetadata(heistId: "button_go")
                ),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(script)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["version"] as? Int, HeistPlayback.currentVersion)
        XCTAssertEqual(json?["app"] as? String, "com.example.app")

        let steps = json?["steps"] as? [[String: Any]]
        XCTAssertEqual(steps?.count, 1)

        let firstStep = steps?.first
        XCTAssertEqual(firstStep?["command"] as? String, "activate")
        let target = try XCTUnwrap(firstStep?["target"] as? [String: Any])
        XCTAssertEqual(target["label"] as? String, "Go")

        let recorded = firstStep?["_recorded"] as? [String: Any]
        XCTAssertEqual(recorded?["heistId"] as? String, "button_go")
    }

    private func makeElement(heistId: HeistId, label: String) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            traits: [.button],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
    }

    private func semanticTarget(
        sourceHeistId: HeistId? = nil,
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait]? = nil,
        excludeTraits: [HeistTrait]? = nil,
        ordinal: Int? = nil
    ) -> SemanticActionTarget {
        SemanticActionTarget(
            sourceHeistId: sourceHeistId,
            matcher: ElementMatcher(
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
