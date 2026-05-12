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
        bookKeeper.recordHeistEvidence(command: .activate, args: ["command": "activate", "label": "Go", "traits": ["button"]], interfaceCache: [:])
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.version, 1)
        XCTAssertEqual(script.app, "com.example.app")
        XCTAssertEqual(script.steps.count, 1)
        XCTAssertEqual(script.steps[0].command, "activate")
        XCTAssertEqual(script.steps[0].target?.label, "Go")
        XCTAssertFalse(bookKeeper.isRecordingHeist)
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
        XCTAssertEqual(script.steps[0].target?.traits, [.button])
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
            succeeded: false,
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
            succeeded: false,
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

    // MARK: - Minimal Matcher

    @ButtonHeistActor
    func testMinimalMatcherPrefersIdentifier() async {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el", label: "Save", identifier: "saveButton", traits: [.button])
        let other = makeElement(heistId: "other", label: "Cancel", traits: [.button])

        let (matcher, ordinal) = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, other])

        XCTAssertEqual(matcher.identifier, "saveButton")
        XCTAssertNil(matcher.label)
        XCTAssertNil(matcher.traits)
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testMinimalMatcherFallsToLabelTraits() async {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el", label: "Save", traits: [.button])
        let other = makeElement(heistId: "other", label: "Cancel", traits: [.button])

        let (matcher, ordinal) = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, other])

        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertNil(matcher.identifier)
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testMinimalMatcherUsesIdentifierWhenUnique() async {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el1", label: "Item", identifier: "item_1", traits: [.staticText])
        let duplicate = makeElement(heistId: "el2", label: "Item", traits: [.staticText])

        let (matcher, ordinal) = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, duplicate])

        XCTAssertEqual(matcher.identifier, "item_1")
        XCTAssertNil(matcher.label)
        XCTAssertNil(matcher.traits)
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testMinimalMatcherSkipsUUIDIdentifiers() async {
        let bookKeeper = makeBookKeeper()
        let uuidIdentifier = "SwiftUI.550E8400-E29B-41D4-A716-446655440000.42"
        let target = makeElement(heistId: "el1", label: "Proceed", identifier: uuidIdentifier, traits: [.button])
        let other = makeElement(heistId: "el2", label: "Cancel", traits: [.button])

        let (matcher, ordinal) = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, other])

        XCTAssertNil(matcher.identifier, "Runtime UUID identifiers should be ignored for playback stability")
        XCTAssertEqual(matcher.label, "Proceed")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testMinimalMatcherNeverUsesValue() async {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el1", label: "Slider", value: "50%", traits: [.adjustable])
        let duplicate = makeElement(heistId: "el2", label: "Slider", value: "75%", traits: [.adjustable])

        let (matcher, ordinal) = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, duplicate])

        XCTAssertEqual(matcher.label, "Slider")
        XCTAssertNil(matcher.value)
        XCTAssertEqual(matcher.traits, [.adjustable])
        XCTAssertEqual(ordinal, 0, "First of two ambiguous elements should get ordinal 0")
    }

    @ButtonHeistActor
    func testMinimalMatcherFiltersStateTraits() async {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el1", label: "Toggle", traits: [.button, .selected])
        let other = makeElement(heistId: "el2", label: "Cancel", traits: [.button])

        let (matcher, ordinal) = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, other])

        XCTAssertEqual(matcher.label, "Toggle")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testAmbiguousElementsGetOrdinals() async {
        let bookKeeper = makeBookKeeper()
        let first = makeElement(heistId: "el1", label: "Item", traits: [.staticText])
        let second = makeElement(heistId: "el2", label: "Item", traits: [.staticText])
        let third = makeElement(heistId: "el3", label: "Item", traits: [.staticText])
        let allElements = [first, second, third]

        let (matcher0, ordinal0) = bookKeeper.buildMinimalMatcher(element: first, allElements: allElements)
        let (matcher1, ordinal1) = bookKeeper.buildMinimalMatcher(element: second, allElements: allElements)
        let (matcher2, ordinal2) = bookKeeper.buildMinimalMatcher(element: third, allElements: allElements)

        // All share the same matcher
        XCTAssertEqual(matcher0.label, "Item")
        XCTAssertEqual(matcher1.label, "Item")
        XCTAssertEqual(matcher2.label, "Item")

        // Each gets its traversal-order ordinal
        XCTAssertEqual(ordinal0, 0)
        XCTAssertEqual(ordinal1, 1)
        XCTAssertEqual(ordinal2, 2)
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
        XCTAssertEqual(loaded.version, 1)
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
