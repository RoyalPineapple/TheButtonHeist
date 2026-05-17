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

    func testStepWithRecordedAccessibilityTrace() throws {
        let step = HeistEvidence(
            command: "activate",
            target: ElementMatcher(label: "Continue", traits: [.button]),
            recorded: RecordedMetadata(
                accessibilityTrace: AccessibilityTrace(interface: Interface(
                    timestamp: Date(timeIntervalSince1970: 0),
                    tree: [.element(makeElement(heistId: "continue", label: "Continue"))]
                )),
                accessibilityDelta: .screenChanged(.init(
                    elementCount: 1,
                    newInterface: Interface(
                        timestamp: Date(timeIntervalSince1970: 0),
                        tree: [.element(makeElement(heistId: "continue", label: "Continue"))]
                    )
                )),
                expectation: ExpectationResult(
                    met: true,
                    expectation: .screenChanged,
                    actual: "screenChanged"
                )
            )
        )

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(HeistEvidence.self, from: data)

        let change = try XCTUnwrap(decoded.recorded?.accessibilityTrace?.receipts.first)
        XCTAssertEqual(change.kind, .capture)
        XCTAssertEqual(change.interface.elements.first?.label, "Continue")
        XCTAssertEqual(decoded.recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
        XCTAssertEqual(decoded.recorded?.accessibilityDelta?.elementCount, 1)
        XCTAssertEqual(decoded.recorded?.expectation?.met, true)
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

    func testHeistValueFromAny() {
        XCTAssertEqual(HeistValue.from("hello"), .string("hello"))
        XCTAssertEqual(HeistValue.from(42 as Int), .int(42))
        XCTAssertEqual(HeistValue.from(3.14), .double(3.14))
        XCTAssertEqual(HeistValue.from(true), .bool(true))
        XCTAssertNil(HeistValue.from(Data()))
    }

    func testHeistValueFromArrayFailsOnUnconvertibleElement() {
        let mixedArray: [Any] = ["hello", 42, Data()]
        XCTAssertNil(HeistValue.from(mixedArray))
    }

    func testHeistValueFromDictFailsOnUnconvertibleValue() {
        let mixedDict: [String: Any] = ["name": "test", "data": Data()]
        XCTAssertNil(HeistValue.from(mixedDict))
    }

    func testHeistValueFromValidArraySucceeds() {
        let validArray: [Any] = ["hello", 42, true]
        let expected: HeistValue = .array([.string("hello"), .int(42), .bool(true)])
        XCTAssertEqual(HeistValue.from(validArray), expected)
    }

    func testHeistValueFromValidDictSucceeds() {
        let validDict: [String: Any] = ["name": "test", "count": 3]
        let result = HeistValue.from(validDict)
        XCTAssertNotNil(result)
        if case .object(let objectValue) = result {
            XCTAssertEqual(objectValue["name"], .string("test"))
            XCTAssertEqual(objectValue["count"], .int(3))
        } else {
            XCTFail("Expected .object case")
        }
    }

    func testHeistValueToAny() {
        XCTAssertEqual(HeistValue.string("hello").toAny() as? String, "hello")
        XCTAssertEqual(HeistValue.int(42).toAny() as? Int, 42)
        XCTAssertEqual(HeistValue.double(3.14).toAny() as? Double, 3.14)
        XCTAssertEqual(HeistValue.bool(true).toAny() as? Bool, true)
    }

    // MARK: - RecordedMetadata

    func testRecordedMetadataRoundTrip() throws {
        let metadata = RecordedMetadata(
            heistId: "button_submit",
            frame: RecordedFrame(x: 10, y: 20, width: 100, height: 44),
            coordinateOnly: false,
            unsupportedArguments: [
                RecordedUnsupportedInput(
                    name: "metadata",
                    valueType: "Data",
                    reason: "not JSON-compatible; omitted from replay arguments"
                ),
            ],
            caps: [
                RecordedInputCap(
                    name: "timeout",
                    requested: .double(60.5),
                    applied: .double(30.5),
                    maximum: .double(30.5),
                    reason: "timeout capped during recording"
                ),
            ]
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(RecordedMetadata.self, from: data)

        XCTAssertEqual(decoded.heistId, "button_submit")
        XCTAssertEqual(decoded.frame?.x, 10)
        XCTAssertEqual(decoded.frame?.height, 44)
        XCTAssertEqual(decoded.coordinateOnly, false)
        XCTAssertEqual(decoded.unsupportedArguments?.first?.name, "metadata")
        XCTAssertEqual(decoded.unsupportedArguments?.first?.valueType, "Data")
        XCTAssertEqual(decoded.caps?.first?.name, "timeout")
        XCTAssertEqual(decoded.caps?.first?.applied, .double(30.5))
    }

    func testRecordedMetadataCoordinateOnly() throws {
        let metadata = RecordedMetadata(coordinateOnly: true)
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(RecordedMetadata.self, from: data)

        XCTAssertNil(decoded.heistId)
        XCTAssertNil(decoded.frame)
        XCTAssertEqual(decoded.coordinateOnly, true)
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

    private func makeElement(heistId: String, label: String) -> HeistElement {
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
