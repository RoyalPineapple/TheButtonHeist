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
    func testRecordAndStopProducesHeist() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: ["command": "activate", "label": "Go", "traits": ["button"]],
            actionResult: ActionResult(
                success: true,
                method: .activate,
                accessibilityDelta: .noChange(.init(elementCount: 1)),
                accessibilityTrace: AccessibilityTrace(interface: Interface(
                    timestamp: Date(timeIntervalSince1970: 0),
                    tree: [.element(makeElement(heistId: "go", label: "Go", traits: [.button]))]
                )),
                screenName: "Home",
                screenId: "home",
                settled: true,
                settleTimeMs: 12
            ),
            interfaceCache: [:]
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
        XCTAssertNil(script.steps[0].toRequestDictionary()["_recorded"])
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordHeistEvidenceDerivesMatcherFromTraceCapture() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let fallbackCache = [
            "save": makeElement(heistId: "save", label: "Save", traits: [.button]),
            "duplicate": makeElement(heistId: "duplicate", label: "Save", traits: [.button]),
        ]
        let preActionInterface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(makeElement(
                    heistId: "save",
                    label: "Save",
                    identifier: "primary.save",
                    traits: [.button]
                )),
                .element(makeElement(heistId: "cancel", label: "Cancel", traits: [.button])),
            ]
        )
        let postActionInterface = Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: [
                .element(makeElement(
                    heistId: "save",
                    label: "Save",
                    identifier: "post-action.save",
                    traits: [.button]
                )),
            ]
        )
        let preActionCapture = AccessibilityTrace.Capture(sequence: 1, interface: preActionInterface)

        bookKeeper.recordHeistEvidence(
            command: .activate,
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
            interfaceCache: fallbackCache
        )

        let script = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(script.steps[0].target?.identifier, "primary.save")
        XCTAssertNil(script.steps[0].ordinal)
        XCTAssertEqual(script.steps[0].recorded?.heistId, "save")
    }

    @ButtonHeistActor
    func testRecordHeistEvidenceDoesNotDeriveMatcherFromPostActionOnlyTrace() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let fallbackCache = [
            "save": makeElement(heistId: "save", label: "Save", identifier: "fallback.save", traits: [.button]),
            "duplicate": makeElement(heistId: "duplicate", label: "Save", traits: [.button]),
        ]
        let preActionInterface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [.element(makeElement(heistId: "cancel", label: "Cancel", traits: [.button]))]
        )
        let postActionInterface = Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: [
                .element(makeElement(
                    heistId: "save",
                    label: "Save",
                    identifier: "post-action.save",
                    traits: [.button]
                )),
            ]
        )
        let preActionCapture = AccessibilityTrace.Capture(sequence: 1, interface: preActionInterface)

        bookKeeper.recordHeistEvidence(
            command: .activate,
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
            interfaceCache: fallbackCache
        )

        let script = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(script.steps[0].target?.identifier, "fallback.save")
        XCTAssertNil(script.steps[0].ordinal)
    }

    @ButtonHeistActor
    func testCanStartNewHeistAfterStop() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(command: .activate, args: ["command": "activate", "label": "Go"], interfaceCache: [:])
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
            bookKeeper.recordHeistEvidence(command: command, args: ["command": command.rawValue], interfaceCache: [:])
        }

        bookKeeper.recordHeistEvidence(command: .activate, args: ["command": "activate", "label": "Go"], interfaceCache: [:])
        let script = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(script.steps.count, 1)
        XCTAssertEqual(script.steps[0].command, "activate")
    }

    @ButtonHeistActor
    func testRecordingIgnoredWhenNotRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        bookKeeper.recordHeistEvidence(command: .activate, args: ["command": "activate", "label": "Go"], interfaceCache: [:])
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordsMatcherFromArgs() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: [
                "command": "activate",
                "label": "Submit",
                "traits": ["button"],
            ],
            interfaceCache: [:]
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
        bookKeeper.recordHeistEvidence(
            command: .typeText,
            args: [
                "command": "type_text",
                "text": "hello world",
                "clearFirst": true,
            ],
            interfaceCache: [:]
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertNil(script.steps[0].target)
        XCTAssertEqual(script.steps[0].arguments["text"], .string("hello world"))
        XCTAssertEqual(script.steps[0].arguments["clearFirst"], .bool(true))
    }

    @ButtonHeistActor
    func testHeistIdResolvedToMatcher() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        let element = makeElement(heistId: "button_submit", label: "Submit", traits: [.button])
        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: [
                "command": "activate",
                "heistId": "button_submit",
            ],
            interfaceCache: ["button_submit": element]
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].target?.label, "Submit")
        XCTAssertNil(script.steps[0].target?.traits)
        XCTAssertEqual(script.steps[0].recorded?.heistId, "button_submit")
    }

    @ButtonHeistActor
    func testCoordinateOnlyFlagged() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(
            command: .oneFingerTap,
            args: [
                "command": "one_finger_tap",
                "x": 100.0,
                "y": 200.0,
            ],
            interfaceCache: [:]
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertNil(script.steps[0].target)
        XCTAssertEqual(script.steps[0].recorded?.coordinateOnly, true)
    }

    @ButtonHeistActor
    func testBinaryDataStripped() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: [
                "command": "activate",
                "label": "Save",
                "pngData": "base64binarydata",
                "videoData": "morebinarydata",
            ],
            interfaceCache: [:]
        )
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertNil(script.steps[0].arguments["pngData"])
        XCTAssertNil(script.steps[0].arguments["videoData"])
        XCTAssertNil(script.steps[0].arguments["command"])
    }

    // MARK: - Error Skipping

    @ButtonHeistActor
    func testErrorResponseSkipsRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")

        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: ["command": "activate", "label": "Missing"],
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "missing",
                errorKind: .elementNotFound
            ),
            interfaceCache: [:]
        )
        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: ["command": "activate", "label": "Go"],
            interfaceCache: [:]
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

        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: ["command": "activate", "label": "Missing"],
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "missing",
                errorKind: .elementNotFound
            ),
            interfaceCache: [:]
        )

        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: ["command": "activate", "label": "Go"],
            interfaceCache: [:]
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

        bookKeeper.recordHeistEvidence(
            command: .activate,
            args: ["command": "activate", "label": "Go"],
            interfaceCache: [:]
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
        bookKeeper.recordHeistEvidence(command: .activate, args: ["command": "activate", "label": "Go"], interfaceCache: [:])

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
        bookKeeper.recordHeistEvidence(command: .activate, args: ["command": "activate", "label": "Done"], interfaceCache: [:])

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
        bookKeeper.recordHeistEvidence(command: .activate, args: ["command": "activate", "label": "Go"], interfaceCache: [:])

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
