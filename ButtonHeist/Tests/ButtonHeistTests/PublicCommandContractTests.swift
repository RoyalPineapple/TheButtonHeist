import XCTest
@testable import ButtonHeist
import TheScore

final class PublicCommandContractTests: XCTestCase {

    @ButtonHeistActor
    func testEveryPublicCommandParsesValidRequestFromFenceSpecs() async throws {
        let fence = TheFence(configuration: .init())

        for sample in allPublicCommandSamples() {
            assertRequestKeysAreFenceOwned(sample)

            let parsed = try fence.parseRequest(command: sample.command, request: sample.request)

            XCTAssertEqual(parsed.command, sample.command)
            if sample.expectsImmediateResponse {
                XCTAssertNotNil(parsed.immediateResponse)
            } else {
                XCTAssertNil(parsed.immediateResponse)
            }
        }
    }

    func testPublicCommandSamplesCoverEntireFenceCommandCatalog() {
        XCTAssertEqual(
            Set(allPublicCommandSamples().map(\.command)),
            Set(TheFence.Command.allCases),
            "Public command contract samples must cover every Fence command"
        )
    }

    func testPublicCommandNamesAreDescriptorOwned() {
        let descriptors = TheFence.Command.descriptors
        let canonicalNames = descriptors.map(\.canonicalName)

        XCTAssertEqual(descriptors.map(\.command), TheFence.Command.allCases)
        XCTAssertEqual(canonicalNames, descriptors.map { $0.command.rawValue })
        XCTAssertEqual(Set(canonicalNames).count, canonicalNames.count)

        for descriptor in descriptors {
            XCTAssertEqual(
                descriptor.command.canonicalName,
                descriptor.canonicalName,
                "\(descriptor.command.rawValue) should expose its public name through FenceCommandDescriptor"
            )
        }
    }

    @ButtonHeistActor
    func testEveryPublicCommandParsesThroughDescriptorPayloadKind() async throws {
        let fence = TheFence(configuration: .init())

        for sample in allPublicCommandSamples() {
            let parsed = try fence.parseRequest(command: sample.command, request: sample.request)
            XCTAssertEqual(
                payloadKind(of: parsed.payload),
                sample.command.descriptor.requestPayloadKind,
                "\(sample.command.rawValue) should parse through its descriptor-owned request payload kind"
            )
        }
    }

    func testCommandDescriptorPresentationMatchesRenderedToolContracts() {
        for command in TheFence.Command.allCases {
            let descriptor = command.descriptor
            XCTAssertEqual(
                descriptor.description,
                TheFence.Command.presentationDescription(for: descriptor.canonicalName),
                "\(command.rawValue) descriptor description should be projected from command presentation"
            )
        }

        for contract in TheFence.Command.mcpToolContracts {
            XCTAssertEqual(
                contract.description,
                TheFence.Command.presentationDescription(for: contract.name),
                "\(contract.name) MCP contract description should be projected from command presentation"
            )
        }
    }

    func testExpectationArgumentShorthandsAreContractOwned() throws {
        XCTAssertEqual(
            ActionExpectation.shorthandWireTypeValues,
            ["screen_changed", "elements_changed"]
        )

        for shorthand in ActionExpectation.shorthandWireTypeValues {
            let value = try TheFence.parseExpectationArgument(shorthand)
            XCTAssertEqual(value, .object([FenceParameterKey.type.rawValue: .string(shorthand)]))
        }

        let jsonValue = try TheFence.parseExpectationArgument(#"{"type":"screen_changed"}"#)
        XCTAssertEqual(jsonValue, .object([FenceParameterKey.type.rawValue: .string("screen_changed")]))
    }

    @ButtonHeistActor
    func testEveryPublicCommandRejectsUnknownRequestKeysFromFenceSpecs() async {
        let fence = TheFence(configuration: .init())
        let invalidKey = "__legacy_public_contract_key"

        for sample in allPublicCommandSamples() {
            XCTAssertFalse(sample.command.parameters.map(\.key).contains(invalidKey))

            var request = sample.request
            request[invalidKey] = true

            XCTAssertThrowsError(try fence.parseRequest(command: sample.command, request: request)) { error in
                guard let schemaError = error as? SchemaValidationError else {
                    return XCTFail("Expected SchemaValidationError for \(sample.command.rawValue), got \(error)")
                }
                XCTAssertEqual(schemaError.field, invalidKey)
                XCTAssertEqual(schemaError.observed, "boolean true")
                XCTAssertEqual(schemaError.expected, "valid \(sample.command.rawValue) parameter")
            }
        }
    }

    @ButtonHeistActor
    func testRepresentativeRequiredParametersRejectMissingValuesFromFenceSpecs() async {
        let fence = TheFence(configuration: .init())
        let cases: [(command: TheFence.Command, field: String, expected: String)] = [
            (.typeText, "text", "string"),
            (.editAction, "action", "enum one of copy, paste, cut, select, selectAll, delete"),
            (.drag, "endX", "number"),
            (.runBatch, "steps", "array of objects"),
            (.stopHeist, "output", "string"),
            (.playHeist, "input", "string"),
        ]

        for testCase in cases {
            let requiredSpec = testCase.command.parameters.first { $0.key == testCase.field }
            XCTAssertEqual(requiredSpec?.required, true, "\(testCase.command.rawValue).\(testCase.field) should be Fence-owned required metadata")

            XCTAssertThrowsError(try fence.parseRequest(command: testCase.command, request: [
                "command": testCase.command.rawValue,
            ])) { error in
                guard let schemaError = error as? SchemaValidationError else {
                    return XCTFail("Expected SchemaValidationError for \(testCase.command.rawValue), got \(error)")
                }
                XCTAssertEqual(schemaError.field, testCase.field)
                XCTAssertEqual(schemaError.observed, "missing")
                XCTAssertEqual(schemaError.expected, testCase.expected)
            }
        }
    }

    private func allPublicCommandSamples() -> [PublicCommandSample] {
        return lifecycleCommandSamples()
            + observationCommandSamples()
            + gestureCommandSamples()
            + scrollAndActionCommandSamples()
            + textAndPasteboardCommandSamples()
            + recordingAndSessionCommandSamples()
            + heistCommandSamples()
    }

    private func payloadKind(of payload: TheFence.RequestPayload) -> FenceRequestPayloadKind {
        switch payload {
        case .none:
            return .none
        case .getInterface, .screen, .artifact:
            return .observation
        case .waitForChange:
            return .waitForChange
        case .gesture:
            return .gesture
        case .scroll, .accessibility, .rotor, .typeText, .editAction, .setPasteboard, .waitFor:
            return .elementAction
        case .startRecording, .connect, .runBatch, .archiveSession, .startHeist, .stopHeist, .playHeist:
            return .session
        }
    }

    private func lifecycleCommandSamples() -> [PublicCommandSample] {
        [
            .sample(.help),
            .sample(.status),
            .sample(.ping),
            .sample(.quit),
            .sample(.exit),
            .sample(.listDevices),
        ]
    }

    private func observationCommandSamples() -> [PublicCommandSample] {
        [
            .init(command: .getInterface, request: [
                "command": TheFence.Command.getInterface.rawValue,
                "detail": InterfaceDetail.full.rawValue,
                "subtree": [
                    "element": ["label": "Pay"],
                    "ordinal": 0,
                ],
            ]),
            .init(command: .getScreen, request: [
                "command": TheFence.Command.getScreen.rawValue,
                "output": "/tmp/buttonheist-screen.png",
                "includeInterface": true,
            ]),
            .sample(.waitForChange, request: [
                "expect": ["type": "screen_changed"],
            ]),
        ]
    }

    private func gestureCommandSamples() -> [PublicCommandSample] {
        [
            .sample(.oneFingerTap, request: [
                "x": 12.0,
                "y": 24.0,
            ]),
            .sample(.longPress, request: [
                "x": 12.0,
                "y": 24.0,
                "duration": 0.5,
            ]),
            .init(command: .activate, request: [
                "command": TheFence.Command.activate.rawValue,
                "label": "Pay",
                "traits": [HeistTrait.button.rawValue],
                "count": 2,
                "expect": ["type": "elements_changed"],
                "timeout": 1.5,
            ]),
            .init(command: .swipe, request: [
                "command": TheFence.Command.swipe.rawValue,
                "heistId": "receipt_list",
                "direction": SwipeDirection.up.rawValue,
                "duration": 0.2,
            ]),
            .sample(.drag, request: [
                "startX": 10.0,
                "startY": 20.0,
                "endX": 40.0,
                "endY": 80.0,
                "duration": 0.25,
            ]),
            .sample(.pinch, request: [
                "centerX": 120.0,
                "centerY": 180.0,
                "scale": 1.2,
            ]),
            .sample(.rotate, request: [
                "centerX": 120.0,
                "centerY": 180.0,
                "angle": 0.5,
            ]),
            .sample(.twoFingerTap, request: [
                "centerX": 120.0,
                "centerY": 180.0,
            ]),
            .sample(.drawPath, request: [
                "points": [
                    ["x": 0.0, "y": 0.0],
                    ["x": 20.0, "y": 20.0],
                ],
            ]),
            .sample(.drawBezier, request: [
                "startX": 0.0,
                "startY": 0.0,
                "segments": [
                    [
                        "cp1X": 5.0,
                        "cp1Y": 0.0,
                        "cp2X": 10.0,
                        "cp2Y": 20.0,
                        "endX": 20.0,
                        "endY": 20.0,
                    ],
                ],
            ]),
        ]
    }

    private func scrollAndActionCommandSamples() -> [PublicCommandSample] {
        [
            .sample(.scroll, request: [
                "label": "Receipt list",
                "direction": ScrollDirection.down.rawValue,
            ]),
            .sample(.scrollToVisible, request: [
                "label": "Receipt list",
            ]),
            .sample(.elementSearch, request: [
                "label": "Receipt list",
                "direction": ScrollSearchDirection.down.rawValue,
            ]),
            .sample(.scrollToEdge, request: [
                "label": "Receipt list",
                "edge": ScrollEdge.bottom.rawValue,
            ]),
            .sample(.increment, request: [
                "label": "Quantity",
            ]),
            .sample(.decrement, request: [
                "label": "Quantity",
            ]),
            .sample(.performCustomAction, request: [
                "label": "Card",
                "action": "Dismiss",
            ]),
            .sample(.rotor, request: [
                "label": "Body",
                "rotor": "Headings",
            ]),
        ]
    }

    private func textAndPasteboardCommandSamples() -> [PublicCommandSample] {
        [
            .init(command: .typeText, request: [
                "command": TheFence.Command.typeText.rawValue,
                "identifier": "note",
                "text": "hello",
                "timeout": 5.0,
            ]),
            .sample(.editAction, request: [
                "action": EditAction.copy.rawValue,
            ]),
            .sample(.setPasteboard, request: [
                "text": "hello",
            ]),
            .sample(.getPasteboard),
            .sample(.waitFor, request: [
                "label": "Pay",
                "timeout": 5.0,
            ]),
            .sample(.dismissKeyboard),
        ]
    }

    private func recordingAndSessionCommandSamples() -> [PublicCommandSample] {
        [
            .init(command: .startRecording, request: [
                "command": TheFence.Command.startRecording.rawValue,
                "fps": 8,
                "scale": 0.5,
                "max_duration": 10.0,
            ]),
            .sample(.stopRecording, request: [
                "output": "/tmp/buttonheist-recording.mp4",
            ]),
            .init(command: .runBatch, request: [
                "command": TheFence.Command.runBatch.rawValue,
                "steps": [
                    [
                        "command": TheFence.Command.activate.rawValue,
                        "label": "Pay",
                    ],
                ],
                "policy": TheFence.BatchPolicy.stopOnError.rawValue,
            ]),
            .sample(.getSessionState),
            .sample(.connect, request: [
                "device": "127.0.0.1:1455",
                "token": "token",
            ]),
            .sample(.listTargets),
            .sample(.getSessionLog),
            .sample(.archiveSession, request: [
                "delete_source": false,
            ]),
        ]
    }

    private func heistCommandSamples() -> [PublicCommandSample] {
        [
            .sample(.startHeist, request: [
                "app": "com.buttonheist.testapp",
                "identifier": "heist",
            ]),
            .sample(.stopHeist, request: [
                "output": "/tmp/replay.heist",
            ]),
            .init(command: .playHeist, request: [
                "command": TheFence.Command.playHeist.rawValue,
                "input": "/tmp/replay.heist",
            ]),
        ]
    }

    private func assertRequestKeysAreFenceOwned(
        _ sample: PublicCommandSample,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let metadataKeys: Set<String> = ["command", "requestId"]
        let allowedKeys = metadataKeys.union(sample.command.parameters.map(\.key))
        let requestKeys = Set(sample.request.keys)
        let extraKeys = requestKeys.subtracting(allowedKeys)

        XCTAssertTrue(
            extraKeys.isEmpty,
            "\(sample.command.rawValue) sample includes keys outside TheFence.Command.parameters: \(extraKeys.sorted())",
            file: file,
            line: line
        )
    }

    private struct PublicCommandSample {
        let command: TheFence.Command
        let request: [String: Any]
        var expectsImmediateResponse: Bool {
            switch command {
            case .help, .quit, .exit:
                return true
            default:
                return false
            }
        }

        static func sample(
            _ command: TheFence.Command,
            request: [String: Any] = [:]
        ) -> PublicCommandSample {
            var request = request
            request["command"] = command.rawValue
            return PublicCommandSample(command: command, request: request)
        }
    }
}
