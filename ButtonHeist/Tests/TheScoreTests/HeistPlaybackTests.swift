import XCTest
@testable import TheScore

final class HeistPlaybackTests: XCTestCase {

    // MARK: - Heist Playback Round-Trip

    func testScriptRoundTrip() throws {
        let script = HeistPlayback(
            recorded: Date(timeIntervalSince1970: 1_000_000),
            app: "com.buttonheist.testapp",
            steps: [
                HeistEvidence(command: "activate", target: ElementMatcher(label: "Login", traits: [.button])),
                HeistEvidence(command: "type_text", arguments: ["text": .string("user@example.com")]),
                HeistEvidence(command: "activate", target: ElementMatcher(label: "Submit", traits: [.button])),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(script)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HeistPlayback.self, from: data)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.app, "com.buttonheist.testapp")
        XCTAssertEqual(decoded.steps.count, 3)
        XCTAssertEqual(decoded.steps[0].command, "activate")
        XCTAssertEqual(decoded.steps[0].target?.label, "Login")
        XCTAssertEqual(decoded.steps[0].target?.traits, [.button])
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

    // MARK: - Heist Step Flat Encoding

    func testStepEncodesFlat() throws {
        let step = HeistEvidence(
            command: "swipe",
            target: ElementMatcher(label: "List", traits: [.adjustable]),
            arguments: ["direction": .string("up")]
        )

        let data = try JSONEncoder().encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["command"] as? String, "swipe")
        XCTAssertEqual(json?["label"] as? String, "List")
        XCTAssertEqual(json?["traits"] as? [String], ["adjustable"])
        XCTAssertEqual(json?["direction"] as? String, "up")
        // No nesting — target fields are top-level
        XCTAssertNil(json?["target"])
    }

    func testStepDecodesFromFlatJson() throws {
        let json: [String: Any] = [
            "command": "activate",
            "label": "Submit",
            "traits": ["button"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let step = try JSONDecoder().decode(HeistEvidence.self, from: data)

        XCTAssertEqual(step.command, "activate")
        XCTAssertEqual(step.target?.label, "Submit")
        XCTAssertEqual(step.target?.traits, [.button])
        XCTAssertTrue(step.arguments.isEmpty)
    }

    func testStepWithNoTarget() throws {
        let json: [String: Any] = [
            "command": "type_text",
            "text": "hello",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let step = try JSONDecoder().decode(HeistEvidence.self, from: data)

        XCTAssertEqual(step.command, "type_text")
        XCTAssertNil(step.target)
        XCTAssertEqual(step.arguments["text"], .string("hello"))
    }

    func testStepRejectsTopLevelHeistId() throws {
        let json: [String: Any] = [
            "command": "activate",
            "heistId": "stale_button",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try JSONDecoder().decode(HeistEvidence.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("must not contain top-level heistId"))
        }
    }

    func testStepAllowsRecordedHeistIdMetadata() throws {
        let json: [String: Any] = [
            "command": "activate",
            "label": "Save",
            "_recorded": [
                "heistId": "recorded_save",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let step = try JSONDecoder().decode(HeistEvidence.self, from: data)

        XCTAssertEqual(step.target?.label, "Save")
        XCTAssertEqual(step.recorded?.heistId, "recorded_save")
        XCTAssertNil(step.arguments["heistId"])
    }

    func testStepRejectsEncodingTopLevelHeistIdArgument() throws {
        let step = HeistEvidence(
            command: "activate",
            arguments: ["heistId": .string("stale_button")]
        )

        XCTAssertThrowsError(try JSONEncoder().encode(step)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
        }
    }

    func testStepRejectsEncodingTargetMatcherHeistId() throws {
        let step = HeistEvidence(
            command: "activate",
            target: ElementMatcher(heistId: "stale_button")
        )

        XCTAssertThrowsError(try JSONEncoder().encode(step)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertTrue("\(error)".contains("must not contain heistId"))
        }
    }

    func testStepRejectsOrdinalOnlyTarget() throws {
        let json: [String: Any] = [
            "command": "activate",
            "ordinal": 0,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try JSONDecoder().decode(HeistEvidence.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("ordinal only disambiguates"))
        }
    }

    func testStepRejectsNegativeOrdinal() throws {
        let json: [String: Any] = [
            "command": "activate",
            "ordinal": -1,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

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
            target: ElementMatcher(label: "Save", traits: [.button]),
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
            target: ElementMatcher(label: "Continue", traits: [.button]),
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

    func testRecordedMetadataRejectsStoredDeltaProjection() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "accessibilityDelta": [
                "kind": "noChange",
                "elementCount": 999,
            ],
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(RecordedMetadata.self, from: data)) { error in
            XCTAssertTrue(
                "\(error)".contains("accessibilityDelta"),
                "Expected stale recorded metadata field in error, got \(error)"
            )
        }
    }

    func testCurrentVersionIsTwo() {
        XCTAssertEqual(HeistPlayback.currentVersion, 2)
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
            target: ElementMatcher(label: "Save", traits: [.button]),
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

        let expected = #"step(command="activate" matcher(label="Save" traits=[button]) "#
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
                    target: ElementMatcher(label: "Go", traits: [.button]),
                    recorded: RecordedMetadata(heistId: "button_go")
                ),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(script)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["version"] as? Int, 2)
        XCTAssertEqual(json?["app"] as? String, "com.example.app")

        let steps = json?["steps"] as? [[String: Any]]
        XCTAssertEqual(steps?.count, 1)

        let firstStep = steps?.first
        XCTAssertEqual(firstStep?["command"] as? String, "activate")
        XCTAssertEqual(firstStep?["label"] as? String, "Go")

        let recorded = firstStep?["_recorded"] as? [String: Any]
        XCTAssertEqual(recorded?["heistId"] as? String, "button_go")
    }

    func testRepositoryHeistFixturesUseCurrentCanonicalExpectationFormat() throws {
        let repoRoot = try repositoryRoot(startingAt: URL(fileURLWithPath: #filePath))
        let fixtureURL = repoRoot.appendingPathComponent("demos/heist-full-demo.heist")

        let data = try Data(contentsOf: fixtureURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["version"] as? Int, HeistPlayback.currentVersion)

        let steps = try XCTUnwrap(json["steps"] as? [[String: Any]])
        for (index, step) in steps.enumerated() {
            guard let expectation = step["expect"] else { continue }
            assertCanonicalExpectation(expectation, context: "steps[\(index)].expect")
        }
    }

    private func assertCanonicalExpectation(
        _ expectation: Any,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let object = expectation as? [String: Any] else {
            return XCTFail("\(context) must be an object", file: file, line: line)
        }

        guard let type = object["type"] as? String else {
            return XCTFail("\(context) must include a type discriminator", file: file, line: line)
        }

        switch type {
        case "screen_changed", "elements_changed", "element_updated":
            return
        case "element_appeared", "element_disappeared":
            XCTAssertNotNil(object["matcher"] as? [String: Any], "\(context) must include matcher", file: file, line: line)
        case "compound":
            guard let expectations = object["expectations"] as? [Any], !expectations.isEmpty else {
                return XCTFail("\(context) compound must include expectations", file: file, line: line)
            }
            for (index, nested) in expectations.enumerated() {
                assertCanonicalExpectation(nested, context: "\(context).expectations[\(index)]", file: file, line: line)
            }
        default:
            XCTFail("\(context) has unknown expectation type \(type)", file: file, line: line)
        }
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

    private func repositoryRoot(startingAt fileURL: URL) throws -> URL {
        var candidate = fileURL.deletingLastPathComponent()

        while candidate.path != candidate.deletingLastPathComponent().path {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Workspace.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw XCTSkip("Could not locate repository root from \(fileURL.path)")
    }
}
