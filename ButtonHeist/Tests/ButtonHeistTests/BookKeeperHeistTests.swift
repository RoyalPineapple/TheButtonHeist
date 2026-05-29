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
            HeistEvidence(command: "activate", target: semanticTarget(label: "Direct", traits: [.button])),
            to: bookKeeper
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].target?.matcher.label, "Direct")
    }

    @ButtonHeistActor
    func testStopHeistRejectsMalformedEvidenceFile() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "invalid-evidence")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        guard case .active(let session) = bookKeeper.phase,
              case .recording(let recording) = session.heistRecording else {
            return XCTFail("Expected active heist recording")
        }
        recording.fileHandle.write(Data("not-json\n".utf8))

        XCTAssertThrowsError(try bookKeeper.stopHeistRecording()) { error in
            guard case BookKeeperError.heistRecording(.evidenceReadFailed(let path, let reason)) = error else {
                return XCTFail("Expected heistRecording(.evidenceReadFailed), got \(error)")
            }
            XCTAssertEqual(path, recording.filePath.path)
            XCTAssertTrue(reason.contains("line 1 is malformed"))
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
            args: activateArgumentValues(label: "Go", traits: ["button"]),
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
        XCTAssertEqual(script.steps[0].target?.matcher.label, "Go")
        let change = try XCTUnwrap(script.steps[0].recorded?.accessibilityTrace?.receipts.first)
        XCTAssertEqual(change.kind, .capture)
        XCTAssertEqual(change.interface.elements.first?.label, "Go")
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.kindRawValue, "noChange")
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.elementCount, 1)
        let playback = try TheFence.TypedHeistPlayback(wire: script)
        XCTAssertNil(try playback.steps[0].normalizedPlaybackOperation().argumentValue("_recorded"))
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordHeistEvidenceStoresSameScreenTraceAsSegmentPatch() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "same-screen-trace")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let beforeInterface = makeReceiptTestInterface([
            makeElement(heistId: "cart_total", label: "Total", value: "$0.00", traits: [.staticText]),
        ])
        let afterInterface = makeReceiptTestInterface([
            makeElement(heistId: "cart_total", label: "Total", value: "$12.00", traits: [.staticText]),
        ])
        let trace = makeReceiptTestTrace(before: beforeInterface, after: afterInterface)

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: activateArgumentValues(label: "Chicken Tikka"),
            actionResult: ActionResult(success: true, method: .activate, accessibilityTrace: trace),
            targetCapture: nil
        )

        let script = try bookKeeper.stopHeistRecording()
        let recordedTrace = try XCTUnwrap(script.steps[0].recorded?.accessibilityTrace)
        XCTAssertEqual(recordedTrace.captures.map(\.interface), [beforeInterface, afterInterface])
        XCTAssertEqual(recordedTrace.screenSegmentsProjection.count, 1)
        XCTAssertEqual(recordedTrace.screenSegmentsProjection[0].transitions.count, 1)
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.kindRawValue, "elementsChanged")

        let json = try XCTUnwrap(encodedRecordedTraceJSON(script))
        XCTAssertNotNil(json["captures"])
        let captures = try XCTUnwrap(json["captures"] as? [[String: Any]])
        XCTAssertEqual(captures.count, 2)
        XCTAssertNotNil(captures.first?["interface"])
    }

    @ButtonHeistActor
    func testRecordHeistEvidenceStartsNewTraceSegmentForScreenChange() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "screen-change-trace")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeReceiptTestInterface([
                makeElement(heistId: "title", label: "Menu", traits: [.header]),
            ])
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeReceiptTestInterface([
                makeElement(heistId: "title", label: "Checkout", traits: [.header]),
            ]),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "test navigation")
        )

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: activateArgumentValues(label: "Checkout"),
            actionResult: ActionResult(
                success: true,
                method: .activate,
                accessibilityTrace: AccessibilityTrace(captures: [before, after])
            ),
            targetCapture: nil
        )

        let script = try bookKeeper.stopHeistRecording()
        let recordedTrace = try XCTUnwrap(script.steps[0].recorded?.accessibilityTrace)
        XCTAssertEqual(recordedTrace.captures.map(\.hash), [before.hash, after.hash])
        XCTAssertEqual(recordedTrace.screenSegmentsProjection.count, 2)
        XCTAssertEqual(recordedTrace.screenSegmentsProjection.map(\.baseline.hash), [before.hash, after.hash])
        XCTAssertTrue(recordedTrace.screenSegmentsProjection.allSatisfy(\.transitions.isEmpty))
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
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
            args: activateArgumentValues(heistId: "save"),
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
        XCTAssertEqual(script.steps[0].target?.matcher.identifier, "primary.save")
        XCTAssertNil(script.steps[0].target?.ordinal)
        XCTAssertEqual(script.steps[0].recorded?.heistId, "save")
        XCTAssertEqual(script.steps[0].recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
    }

    @ButtonHeistActor
    func testRecordHeistEvidenceRejectsHeistIdMissingFromTargetCapture() async throws {
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
            args: activateArgumentValues(heistId: "save"),
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

        XCTAssertThrowsError(try bookKeeper.stopHeistRecording()) { error in
            guard case BookKeeperError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testCanStartNewHeistAfterStop() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .activate, args: activateArgumentValues(label: "Go"), targetCapture: nil)
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

        let excluded = TheFence.Command.allCases.filter { !$0.isHeistRecordable }
        for command in excluded {
            let args = minimalHeistTestArguments(for: command)
            try recordHeistEvidence(bookKeeper, command: command, args: args, targetCapture: nil)
        }

        try recordHeistEvidence(bookKeeper, command: .activate, args: activateArgumentValues(label: "Go"), targetCapture: nil)
        let script = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(script.steps.count, 1)
        XCTAssertEqual(script.steps[0].command, "activate")
    }

    @ButtonHeistActor
    func testRecordingIgnoredWhenNotRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try recordHeistEvidence(bookKeeper, command: .activate, args: activateArgumentValues(label: "Go"), targetCapture: nil)
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordsMatcherFromArgs() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .activate,
            args: activateArgumentValues(label: "Submit", traits: ["button"]),
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].target?.matcher.label, "Submit")
        XCTAssertEqual(script.steps[0].target?.matcher.traits, [.button])
    }

    @ButtonHeistActor
    func testRecordsCommandArguments() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .typeText,
            args: [
                "text": .string("hello world"),
                "timeout": .int(30),
            ],
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertNil(script.steps[0].target)
        XCTAssertEqual(script.steps[0].arguments["text"], .string("hello world"))
        XCTAssertNil(script.steps[0].arguments["timeout"])
    }

    @ButtonHeistActor
    func testEvidenceArgumentsAcceptOnlyCommandFields() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "evidence-fields")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try recordHeistEvidence(bookKeeper, command: .typeText,
            args: [
                "text": .string("hello world"),
                "target": targetArgumentValue(identifier: "login.email"),
            ],
            targetCapture: nil
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].target?.matcher.identifier, "login.email")
        XCTAssertEqual(script.steps[0].arguments, ["text": .string("hello world")])
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
                "timeout": .int(2),
                "expect": .object([
                    "type": .string("element_appeared"),
                    "matcher": .object([
                        "label": .string("Submit"),
                        "traits": .array([.string("button")]),
                    ]),
                ]),
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
    }

    @ButtonHeistActor
    func testRecordingUsesFenceSchemaForArguments() async throws {
        let request: [String: HeistValue] = [
            "text": .string("hello world"),
            "metadata": .string("not allowed"),
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
            args: activateArgumentValues(heistId: "button_submit"),
            targetCapture: capture
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].target?.matcher.label, "Submit")
        XCTAssertNil(script.steps[0].target?.matcher.traits)
        XCTAssertEqual(script.steps[0].recorded?.heistId, "button_submit")
    }

    @ButtonHeistActor
    func testHeistIdWithNoMatcherPredicatesIsNotReplayable() async throws {
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
            args: activateArgumentValues(heistId: "anonymous_2"),
            actionResult: ActionResult(
                success: true,
                method: .activate,
                accessibilityTrace: AccessibilityTrace(capture: capture)
            ),
            targetCapture: capture
        )
        XCTAssertThrowsError(try bookKeeper.stopHeistRecording()) { error in
            guard case BookKeeperError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testCoordinateOnlyFlagged() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .oneFingerTap,
            args: [
                "x": .double(100.0),
                "y": .double(200.0),
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
        var request = activateArgumentValues(label: "Save")
        request["pngData"] = .string("base64binarydata")

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
            args: activateArgumentValues(label: "Missing"),
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "missing",
                errorKind: .elementNotFound
            ),
            targetCapture: nil
        )
        try recordHeistEvidence(bookKeeper, command: .activate,
            args: activateArgumentValues(label: "Go"),
            targetCapture: nil
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].target?.matcher.label, "Go")
    }

    @ButtonHeistActor
    func testFailedActionResultSkipsRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: activateArgumentValues(label: "Missing"),
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "missing",
                errorKind: .elementNotFound
            ),
            targetCapture: nil
        )

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: activateArgumentValues(label: "Go"),
            targetCapture: nil
        )

        let heist = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].target?.matcher.label, "Go")
    }

    @ButtonHeistActor
    func testSuccessfulActionResultIsRecorded() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try recordHeistEvidence(bookKeeper, command: .activate,
            args: activateArgumentValues(label: "Go"),
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
                HeistEvidence(command: "activate", target: semanticTarget(label: "Go", traits: [.button])),
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
        XCTAssertEqual(loaded.steps[0].target?.matcher.label, "Go")
        XCTAssertEqual(loaded.steps[1].arguments["text"], .string("test"))
    }

    // MARK: - Malformed evidence contract

    @ButtonHeistActor
    func testStopHeistRejectsMalformedEvidenceLines() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "malformed-evidence")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        try recordHeistEvidence(bookKeeper, command: .activate, args: activateArgumentValues(label: "Go"), targetCapture: nil)

        guard case .active(let session) = bookKeeper.phase,
              case .recording(let recording) = session.heistRecording else {
            return XCTFail("Expected active heist recording")
        }
        recording.fileHandle.write(Data("this-is-not-json\n".utf8))

        let onDisk = try String(contentsOf: recording.filePath, encoding: .utf8)
        XCTAssertTrue(
            onDisk.contains("this-is-not-json"),
            "Malformed line must still be present when stopHeistRecording reads the file"
        )

        XCTAssertThrowsError(try bookKeeper.stopHeistRecording()) { error in
            guard case .heistRecording(.evidenceReadFailed(let path, let reason)) = error as? BookKeeperError else {
                return XCTFail("Expected evidenceReadFailed, got \(error)")
            }
            XCTAssertEqual(path, recording.filePath.path)
            XCTAssertTrue(reason.contains("line 2 is malformed"))
        }
    }

    // MARK: - Close session with open heist recording

    @ButtonHeistActor
    func testCloseSessionWithActiveHeistClosesHandle() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "close-with-heist")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        try recordHeistEvidence(bookKeeper, command: .activate, args: activateArgumentValues(label: "Go"), targetCapture: nil)

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
        heistId: HeistId,
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

private func minimalHeistTestArguments(for command: TheFence.Command) -> [String: HeistValue] {
    switch command {
    case .runBatch:
        return ["steps": .array([
            .object([
                "command": .string(TheFence.Command.activate.rawValue),
                "target": targetArgumentValue(label: "Ignored"),
            ]),
        ])]
    case .stopHeist:
        return ["output": .string("ignored.heist")]
    case .playHeist:
        return ["input": .string("ignored.heist")]
    default:
        return [:]
    }
}

private func activateArgumentValues(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [String]? = nil,
    excludeTraits: [String]? = nil,
    ordinal: Int? = nil
) -> [String: HeistValue] {
    [
        "target": targetArgumentValue(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits,
            ordinal: ordinal
        ),
    ]
}

private func activateArgumentValues(heistId: String) -> [String: HeistValue] {
    ["target": targetArgumentValue(heistId: heistId)]
}

@ButtonHeistActor
private func recordHeistEvidence(
    _ bookKeeper: TheBookKeeper,
    command: TheFence.Command,
    args: [String: HeistValue],
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
    args: [String: HeistValue]
) throws -> TheFence.ParsedRequest {
    var request = args
    request["requestId"] = .string("test")
    return try TheFence(configuration: .init()).parseRequest(
        command: command,
        arguments: TheFence.CommandArgumentEnvelope(values: request)
    )
}

@ButtonHeistActor
private func appendEvidenceLine(_ evidence: HeistEvidence, to bookKeeper: TheBookKeeper) throws {
    guard case .active(let session) = bookKeeper.phase,
          case .recording(let recording) = session.heistRecording else {
        throw BookKeeperError.heistRecording(.notRecording)
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(evidence)
    data.append(contentsOf: [0x0A])
    recording.fileHandle.write(data)
}

private func encodedRecordedTraceJSON(_ script: HeistPlayback) throws -> [String: Any]? {
    let data = try JSONEncoder().encode(script)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let steps = try XCTUnwrap(json["steps"] as? [[String: Any]])
    let recorded = try XCTUnwrap(steps.first?["_recorded"] as? [String: Any])
    return recorded["accessibilityTrace"] as? [String: Any]
}
