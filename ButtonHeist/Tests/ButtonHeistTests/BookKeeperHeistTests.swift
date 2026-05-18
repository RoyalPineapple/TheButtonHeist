import XCTest
@testable import ButtonHeist

final class BookKeeperHeistTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = TempDirectoryFixture.make(prefix: "bookkeeper-heist-tests")
    }

    override func tearDown() {
        TempDirectoryFixture.remove(tempDirectory)
        super.tearDown()
    }

    // MARK: - Heist Recording Lifecycle

    @ButtonHeistActor
    func testNotRecordingByDefault() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testStartHeistRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        XCTAssertTrue(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testStartHeistWhileAlreadyRecordingThrows() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        XCTAssertThrowsError(try bookKeeper.startHeistRecording(app: "com.example.app"))
    }

    @ButtonHeistActor
    func testStartHeistWithoutSessionThrows() async {
        let bookKeeper = makeBookKeeper()
        XCTAssertThrowsError(try bookKeeper.startHeistRecording(app: "com.example.app"))
    }

    @ButtonHeistActor
    func testStopHeistWithoutRecordingThrows() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        XCTAssertThrowsError(try bookKeeper.stopHeistRecording())
    }

    @ButtonHeistActor
    func testStopHeistWithNoStepsThrows() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        XCTAssertThrowsError(try bookKeeper.stopHeistRecording())
    }

    @ButtonHeistActor
    func testStopHeistAcceptsEvidenceWrittenDirectlyToFile() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "direct-evidence")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try appendEvidenceLine(
            HeistEvidence(command: "activate", target: ElementMatcher(label: "Direct", traits: [.button])),
            to: bookKeeper
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].target?.label, "Direct")
    }

    @ButtonHeistActor
    func testStopHeistRejectsFileWithNoValidEvidence() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "invalid-evidence")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        guard case .active(let session) = bookKeeper.phase,
              case .recording(let recording) = session.heistRecording else {
            return XCTFail("Expected active heist recording")
        }
        recording.fileHandle.write(Data("not-json\n".utf8))

        XCTAssertThrowsError(try bookKeeper.stopHeistRecording()) { error in
            guard case BookKeeperError.noStepsRecorded = error else {
                return XCTFail("Expected noStepsRecorded, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRecordAndStopProducesHeist() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        let actionInterface = makeReceiptTestInterface([
            makeElement(heistId: "go", label: "Go", traits: [.button]),
        ])
        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "label": "Go", "traits": ["button"]],
            actionResult: ActionResult(
                success: true,
                method: .activate,
                accessibilityTrace: makeReceiptTestTrace(before: actionInterface, after: actionInterface),
                screenName: "Home",
                screenId: "home",
                settled: true,
                settleTimeMs: 12
            ),
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.version, HeistPlayback.currentVersion)
        XCTAssertEqual(script.app, "com.example.app")
        XCTAssertEqual(script.steps.count, 1)
        XCTAssertEqual(script.steps[0].command, "activate")
        XCTAssertEqual(script.steps[0].target?.label, "Go")
        let change = try XCTUnwrap(script.steps[0].recorded?.accessibilityTrace?.receipts.first)
        XCTAssertEqual(change.kind, .capture)
        XCTAssertEqual(change.interface.elements.first?.label, "Go")
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.kindRawValue, "noChange")
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.elementCount, 1)
        let playback = try TheFence.TypedHeistPlayback(wire: script)
        XCTAssertNil(playback.steps[0].dispatchBridgeArguments()["_recorded"])
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordHeistEvidenceDerivesMatcherFromTargetCaptureDuringScreenChange() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let preActionInterface = makeReceiptTestInterface(
            [
                makeElement(
                    heistId: "save",
                    label: "Save",
                    identifier: "primary.save",
                    traits: [.button]
                ),
                makeElement(heistId: "cancel", label: "Cancel", traits: [.button]),
            ],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let postActionInterface = makeReceiptTestInterface(
            [
                makeElement(
                    heistId: "save",
                    label: "Save",
                    identifier: "post-action.save",
                    traits: [.button]
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let preActionCapture = AccessibilityTrace.Capture(sequence: 1, interface: preActionInterface)
        let postActionCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: postActionInterface,
            parentHash: preActionCapture.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "test navigation")
        )

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "heistId": "save", "label": "Stale Save"],
            actionResult: ActionResult(
                success: true,
                method: .activate,
                accessibilityTrace: AccessibilityTrace(captures: [
                    preActionCapture,
                    postActionCapture,
                ])
            ),
            targetCapture: preActionCapture
        )

        let script = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(script.steps[0].target?.identifier, "primary.save")
        XCTAssertNil(script.steps[0].ordinal)
        XCTAssertEqual(script.steps[0].recorded?.heistId, "save")
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
    }

    @ButtonHeistActor
    func testRecordHeistEvidenceDoesNotInventMatcherWhenHeistIdMissingFromTargetCapture() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let preActionInterface = makeReceiptTestInterface(
            [makeElement(heistId: "cancel", label: "Cancel", traits: [.button])],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let postActionInterface = makeReceiptTestInterface(
            [
                makeElement(
                    heistId: "save",
                    label: "Save",
                    identifier: "post-action.save",
                    traits: [.button]
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let preActionCapture = AccessibilityTrace.Capture(sequence: 1, interface: preActionInterface)

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "heistId": "save"],
            actionResult: ActionResult(
                success: true,
                method: .activate,
                accessibilityTrace: AccessibilityTrace(captures: [
                    preActionCapture,
                    AccessibilityTrace.Capture(
                        sequence: 2,
                        interface: postActionInterface,
                        parentHash: preActionCapture.hash
                    ),
                ])
            ),
            targetCapture: preActionCapture
        )

        let script = try bookKeeper.stopHeistRecording()
        XCTAssertNil(script.steps[0].target)
        XCTAssertNil(script.steps[0].ordinal)
        XCTAssertNil(script.steps[0].recorded?.heistId)
    }

    @ButtonHeistActor
    func testCanStartNewHeistAfterStop() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .activate, args: ["command": "activate", "label": "Go"], targetCapture: nil)
        _ = try bookKeeper.stopHeistRecording()
        try bookKeeper.startHeistRecording(app: "com.example.second")
        XCTAssertTrue(bookKeeper.isRecordingHeist)
    }

    // MARK: - Recording Behavior

    @ButtonHeistActor
    func testExcludedCommandsAreNotRecorded() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let excluded: [TheFence.Command] = [
            .help, .status, .quit, .exit, .listDevices,
            .getInterface, .getScreen, .getSessionState,
            .connect, .listTargets, .startHeist, .stopHeist,
        ]
        for command in excluded {
            var args: [String: Any] = ["command": command.rawValue]
            if command == .stopHeist {
                args["output"] = "ignored.heist"
            }
            try recordHeistEvidence(bookKeeper, command: command, args: args, targetCapture: nil)
        }

        try recordHeistEvidence(bookKeeper, command: .activate, args: ["command": "activate", "label": "Go"], targetCapture: nil)
        let script = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(script.steps.count, 1)
        XCTAssertEqual(script.steps[0].command, "activate")
    }

    @ButtonHeistActor
    func testRecordingIgnoredWhenNotRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try recordHeistEvidence(bookKeeper, command: .activate, args: ["command": "activate", "label": "Go"], targetCapture: nil)
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordsMatcherFromArgs() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .activate,
            args: [
                "command": "activate",
                "label": "Submit",
                "traits": ["button"],
            ],
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].target?.label, "Submit")
        XCTAssertEqual(script.steps[0].target?.traits, [.button])
    }

    @ButtonHeistActor
    func testRecordsCommandArguments() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .typeText,
            args: [
                "command": "type_text",
                "text": "hello world",
                "timeout": 30,
            ],
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertNil(script.steps[0].target)
        XCTAssertEqual(script.steps[0].arguments["text"], .string("hello world"))
        XCTAssertNil(script.steps[0].arguments["timeout"])
    }

    @ButtonHeistActor
    func testRecordsTypedExpectationArguments() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(
            bookKeeper,
            command: .waitForChange,
            args: [
                "command": "wait_for_change",
                "timeout": 2,
                "expect": [
                    "type": "element_appeared",
                    "matcher": [
                        "label": "Submit",
                        "traits": ["button"],
                    ],
                    "required": true,
                ],
            ],
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].arguments["expect"], .object([
            "type": .string("element_appeared"),
            "matcher": .object([
                "label": .string("Submit"),
                "traits": .array([.string("button")]),
            ]),
        ]))
        XCTAssertEqual(script.steps[0].arguments["timeout"], .int(2))
        XCTAssertNil(script.steps[0].arguments["required"])
    }

    @ButtonHeistActor
    func testRecordingUsesFenceSchemaForArguments() async throws {
        let request: [String: Any] = [
            "command": "type_text",
            "text": "hello world",
            "metadata": Data([0x01, 0x02]),
        ]

        XCTAssertThrowsError(try parsedRequest(command: .typeText, args: request)) { error in
            let validation = error as? SchemaValidationError
            XCTAssertEqual(validation?.field, "metadata")
        }
    }

    @ButtonHeistActor
    func testHeistIdResolvedToMatcher() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let element = makeElement(heistId: "button_submit", label: "Submit", traits: [.button])
        let capture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeReceiptTestInterface([element], timestamp: Date(timeIntervalSince1970: 0))
        )
        try recordHeistEvidence(bookKeeper, command: .activate,
            args: [
                "command": "activate",
                "heistId": "button_submit",
            ],
            targetCapture: capture
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].target?.label, "Submit")
        XCTAssertNil(script.steps[0].target?.traits)
        XCTAssertEqual(script.steps[0].recorded?.heistId, "button_submit")
    }

    @ButtonHeistActor
    func testHeistIdWithNoMatcherPredicatesRecordsOrdinalFallback() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let first = makeElement(heistId: "anonymous_1")
        let second = makeElement(heistId: "anonymous_2")
        let capture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeReceiptTestInterface([first, second], timestamp: Date(timeIntervalSince1970: 0))
        )
        try recordHeistEvidence(bookKeeper, command: .activate,
            args: [
                "command": "activate",
                "heistId": "anonymous_2",
            ],
            actionResult: ActionResult(
                success: true,
                method: .activate,
                accessibilityTrace: AccessibilityTrace(capture: capture)
            ),
            targetCapture: capture
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertFalse(try XCTUnwrap(script.steps[0].target).hasPredicates)
        XCTAssertEqual(script.steps[0].ordinal, 1)
        XCTAssertEqual(script.steps[0].recorded?.heistId, "anonymous_2")
    }

    @ButtonHeistActor
    func testCoordinateOnlyFlagged() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .oneFingerTap,
            args: [
                "command": "one_finger_tap",
                "x": 100.0,
                "y": 200.0,
            ],
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertNil(script.steps[0].target)
        XCTAssertEqual(script.steps[0].recorded?.coordinateOnly, true)
    }

    @ButtonHeistActor
    func testBinaryDataIsRejectedByFenceSchema() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        let request: [String: Any] = [
            "command": "activate",
            "label": "Save",
            "pngData": "base64binarydata",
        ]

        XCTAssertThrowsError(try parsedRequest(command: .activate, args: request)) { error in
            let validation = error as? SchemaValidationError
            XCTAssertEqual(validation?.field, "pngData")
        }
    }

    // MARK: - Error Skipping

    @ButtonHeistActor
    func testErrorResponseSkipsRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "label": "Missing"],
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "missing",
                errorKind: .elementNotFound
            ),
            targetCapture: nil
        )
        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "label": "Go"],
            targetCapture: nil
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].target?.label, "Go")
    }

    @ButtonHeistActor
    func testFailedActionResultSkipsRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "label": "Missing"],
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "missing",
                errorKind: .elementNotFound
            ),
            targetCapture: nil
        )

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "label": "Go"],
            targetCapture: nil
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].target?.label, "Go")
    }

    @ButtonHeistActor
    func testSuccessfulActionResultIsRecorded() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: ["command": "activate", "label": "Go"],
            targetCapture: nil
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 1)
    }

    // MARK: - Heist File I/O

    @ButtonHeistActor
    func testWriteAndReadHeist() async throws {
        let script = HeistPlayback(
            recorded: Date(timeIntervalSince1970: 1_000_000),
            app: "com.example.app",
            steps: [
                HeistEvidence(command: "activate", target: ElementMatcher(label: "Go", traits: [.button])),
                HeistEvidence(command: "type_text", arguments: ["text": .string("test")]),
            ]
        )

        let filePath = tempDirectory.appendingPathComponent("test.heist")
        try TheBookKeeper.writeHeist(script, to: filePath)

        let loaded = try TheBookKeeper.readHeist(from: filePath)
        XCTAssertEqual(loaded.version, HeistPlayback.currentVersion)
        XCTAssertEqual(loaded.app, "com.example.app")
        XCTAssertEqual(loaded.steps.count, 2)
        XCTAssertEqual(loaded.steps[0].command, "activate")
        XCTAssertEqual(loaded.steps[0].target?.label, "Go")
        XCTAssertEqual(loaded.steps[1].arguments["text"], .string("test"))
    }

    // MARK: - Malformed evidence resilience

    @ButtonHeistActor
    func testStopHeistSkipsMalformedEvidenceLines() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "malformed-evidence")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        // Write a good step through the normal path
        try recordHeistEvidence(bookKeeper, command: .activate, args: ["command": "activate", "label": "Go"], targetCapture: nil)

        // Inject a malformed line through the BookKeeper's own file handle. A second
        // FileHandle would track its own offset, and the next recorded step would
        // overwrite the malformed bytes — then there'd be nothing for the skip path
        // to exercise.
        guard case .active(let session) = bookKeeper.phase,
              case .recording(let recording) = session.heistRecording else {
            return XCTFail("Expected active heist recording")
        }
        recording.fileHandle.write(Data("this-is-not-json\n".utf8))

        // Record another good step via the book-keeper handle
        try recordHeistEvidence(bookKeeper, command: .activate, args: ["command": "activate", "label": "Done"], targetCapture: nil)

        // Sanity-check that the malformed bytes survived to disk, so the skip path
        // is actually exercised when stopHeistRecording reads the file.
        let onDisk = try String(contentsOf: recording.filePath, encoding: .utf8)
        XCTAssertTrue(
            onDisk.contains("this-is-not-json"),
            "Malformed line must still be present when stopHeistRecording reads the file"
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 2, "Malformed line should be skipped, not fail the whole stop")
        XCTAssertEqual(heist.steps[0].target?.label, "Go")
        XCTAssertEqual(heist.steps[1].target?.label, "Done")
    }

    // MARK: - Close session with open heist recording

    @ButtonHeistActor
    func testCloseSessionWithActiveHeistClosesHandle() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "close-with-heist")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .activate, args: ["command": "activate", "label": "Go"], targetCapture: nil)

        // Locate the heist file before the phase advances
        guard case .active(let activeSession) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let heistPath = activeSession.directory.appendingPathComponent("heist.jsonl")

        // closeSession should not throw even though the heist is still "recording"
        try await bookKeeper.closeSession()

        // heist.jsonl must still exist on disk — its evidence is preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: heistPath.path))
        // Phase must advance past active — file handle is closed as part of closeSession
        if case .active = bookKeeper.phase {
            XCTFail("closeSession should transition out of active even with an open heist recording")
        }
    }

    // MARK: - Helpers

    @ButtonHeistActor
    private func makeBookKeeper() -> TheBookKeeper {
        TheBookKeeper(baseDirectory: tempDirectory)
    }

    private func makeElement(
        heistId: String,
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label ?? heistId,
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }
}

@ButtonHeistActor
private func recordHeistEvidence(
    _ bookKeeper: TheBookKeeper,
    command: TheFence.Command,
    args: [String: Any],
    actionResult: ActionResult? = nil,
    expectation: ExpectationResult? = nil,
    targetCapture: AccessibilityTrace.Capture?
) throws {
    let parsed = try parsedRequest(command: command, args: args)
    bookKeeper.recordHeistEvidence(
        parsed,
        actionResult: actionResult,
        expectation: expectation,
        targetCapture: targetCapture
    )
}

@ButtonHeistActor
private func parsedRequest(
    command: TheFence.Command,
    args: [String: Any]
) throws -> TheFence.ParsedRequest {
    var request = args
    request["command"] = command.rawValue
    request["requestId"] = "test"
    return try TheFence(configuration: .init()).parseRequest(command: command, request: request)
}

@ButtonHeistActor
private func appendEvidenceLine(_ evidence: HeistEvidence, to bookKeeper: TheBookKeeper) throws {
    guard case .active(let session) = bookKeeper.phase,
          case .recording(let recording) = session.heistRecording else {
        throw BookKeeperError.notRecordingHeist
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(evidence)
    data.append(contentsOf: [0x0A])
    recording.fileHandle.write(data)
}
