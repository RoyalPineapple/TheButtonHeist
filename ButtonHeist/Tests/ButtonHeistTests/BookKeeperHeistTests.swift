import XCTest
@testable import ButtonHeist

final class BookKeeperHeistTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookkeeper-heist-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
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
        bookKeeper.recordHeistEvidence(command: "activate", args: ["command": "activate", "label": "Go", "traits": ["button"]])
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
        bookKeeper.recordHeistEvidence(command: "activate", args: ["command": "activate", "label": "Go"])
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

        let excluded = [
            "help", "status", "quit", "exit", "list_devices",
            "get_interface", "get_screen", "get_session_state",
            "connect", "list_targets", "start_heist", "stop_heist",
        ]
        for command in excluded {
            bookKeeper.recordHeistEvidence(command: command, args: ["command": command])
        }

        bookKeeper.recordHeistEvidence(command: "activate", args: ["command": "activate", "label": "Go"])
        let script = try bookKeeper.stopHeistRecording()
        XCTAssertEqual(script.steps.count, 1)
        XCTAssertEqual(script.steps[0].command, "activate")
    }

    @ButtonHeistActor
    func testRecordingIgnoredWhenNotRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        bookKeeper.recordHeistEvidence(command: "activate", args: ["command": "activate", "label": "Go"])
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordsMatcherFromArgs() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(command: "activate", args: [
            "command": "activate",
            "label": "Submit",
            "traits": ["button"],
        ])
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertEqual(script.steps[0].target?.label, "Submit")
        XCTAssertEqual(script.steps[0].target?.traits, [.button])
    }

    @ButtonHeistActor
    func testRecordsCommandArguments() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(command: "type_text", args: [
            "command": "type_text",
            "text": "hello world",
            "clearFirst": true,
        ])
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

        let elements = [makeElement(heistId: "button_submit", label: "Submit", traits: [.button])]
        bookKeeper.updateInterfaceCache(elements)

        bookKeeper.recordHeistEvidence(command: "activate", args: [
            "command": "activate",
            "heistId": "button_submit",
        ])
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
        bookKeeper.recordHeistEvidence(command: "one_finger_tap", args: [
            "command": "one_finger_tap",
            "x": 100.0,
            "y": 200.0,
        ])
        let script = try bookKeeper.stopHeistRecording()

        XCTAssertNil(script.steps[0].target)
        XCTAssertEqual(script.steps[0].recorded?.coordinateOnly, true)
    }

    @ButtonHeistActor
    func testBinaryDataStripped() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        bookKeeper.recordHeistEvidence(command: "activate", args: [
            "command": "activate",
            "label": "Save",
            "pngData": "base64binarydata",
            "videoData": "morebinarydata",
        ])
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

        let failedResult = ActionResult(
            success: false, method: .activate,
            message: "element not found", errorKind: .elementNotFound
        )
        bookKeeper.recordHeistEvidence(
            command: "activate",
            args: ["command": "activate", "label": "Missing"],
            actionResult: failedResult
        )
        bookKeeper.recordHeistEvidence(
            command: "activate",
            args: ["command": "activate", "label": "Go"],
            actionResult: ActionResult(success: true, method: .activate)
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

        let failedResult = ActionResult(
            success: false,
            method: .activate,
            message: "element not found",
            errorKind: .elementNotFound
        )
        bookKeeper.recordHeistEvidence(
            command: "activate",
            args: ["command": "activate", "label": "Missing"],
            actionResult: failedResult
        )

        let successResult = ActionResult(success: true, method: .activate)
        bookKeeper.recordHeistEvidence(
            command: "activate",
            args: ["command": "activate", "label": "Go"],
            actionResult: successResult
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

        let result = ActionResult(success: true, method: .activate)
        bookKeeper.recordHeistEvidence(
            command: "activate",
            args: ["command": "activate", "label": "Go"],
            actionResult: result
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

    // MARK: - Recovery

    @ButtonHeistActor
    func testRecoverAbandonedSessionCompressesLog() async throws {
        let sessionDir = tempDirectory.appendingPathComponent("abandoned-2026-04-03-120000")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: sessionDir.appendingPathComponent("session.jsonl"))

        let bookKeeper = makeBookKeeper()
        let recovered = bookKeeper.recoverAbandonedSessions()

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].sessionId, "abandoned-2026-04-03-120000")
        XCTAssertNil(recovered[0].heistEvidenceCount)
        XCTAssertNil(recovered[0].heistFilePath)
        // Raw log should be compressed
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sessionDir.appendingPathComponent("session.jsonl").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionDir.appendingPathComponent("session.jsonl.gz").path
        ))
        // Recovery manifest should exist with endTime
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifestData = try Data(contentsOf: sessionDir.appendingPathComponent("manifest.json"))
        let manifest = try decoder.decode(SessionManifest.self, from: manifestData)
        XCTAssertNotNil(manifest.endTime)
    }

    @ButtonHeistActor
    func testRecoverSkipsCleanSessions() async throws {
        let sessionDir = tempDirectory.appendingPathComponent("clean-2026-04-03-120000")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try Data().write(to: sessionDir.appendingPathComponent("session.jsonl.gz"))

        let bookKeeper = makeBookKeeper()
        let recovered = bookKeeper.recoverAbandonedSessions()

        XCTAssertTrue(recovered.isEmpty)
    }

    @ButtonHeistActor
    func testRecoverPreservesHeistEvidence() async throws {
        let sessionDir = tempDirectory.appendingPathComponent("heist-abandoned-2026-04-03-120000")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: sessionDir.appendingPathComponent("session.jsonl"))
        let heistLine = "{\"command\":\"activate\",\"label\":\"Go\"}\n"
        try Data(heistLine.utf8).write(to: sessionDir.appendingPathComponent("heist.jsonl"))

        let bookKeeper = makeBookKeeper()
        let recovered = bookKeeper.recoverAbandonedSessions()

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].heistEvidenceCount, 1)
        XCTAssertNotNil(recovered[0].heistFilePath)
        // heist.jsonl should still exist — partial evidence preserved
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionDir.appendingPathComponent("heist.jsonl").path
        ))
    }

    @ButtonHeistActor
    func testRecoverEmptyBaseDirectory() async {
        let bookKeeper = makeBookKeeper()
        let recovered = bookKeeper.recoverAbandonedSessions()
        XCTAssertTrue(recovered.isEmpty)
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
