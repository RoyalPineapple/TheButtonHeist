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
    func testNotRecordingByDefault() throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testStartHeistRecording() throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        XCTAssertTrue(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testStartHeistWhileAlreadyRecordingThrows() throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        XCTAssertThrowsError(try bookKeeper.startHeistRecording(app: "com.example.app"))
    }

    @ButtonHeistActor
    func testStartHeistWithoutSessionThrows() {
        let bookKeeper = makeBookKeeper()
        XCTAssertThrowsError(try bookKeeper.startHeistRecording(app: "com.example.app"))
    }

    @ButtonHeistActor
    func testStopHeistWithoutRecordingThrows() throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        XCTAssertThrowsError(try bookKeeper.stopHeistRecording())
    }

    @ButtonHeistActor
    func testStopHeistWithNoStepsThrows() throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        try bookKeeper.startHeistRecording(app: "com.example.app")
        XCTAssertThrowsError(try bookKeeper.stopHeistRecording())
    }

    @ButtonHeistActor
    func testRecordAndStopProducesHeist() throws {
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
    func testCanStartNewHeistAfterStop() throws {
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
    func testExcludedCommandsAreNotRecorded() throws {
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
    func testRecordingIgnoredWhenNotRecording() throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.beginSession(identifier: "test")
        bookKeeper.recordHeistEvidence(command: "activate", args: ["command": "activate", "label": "Go"])
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testRecordsMatcherFromArgs() throws {
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
    func testRecordsCommandArguments() throws {
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
    func testHeistIdResolvedToMatcher() throws {
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
    func testCoordinateOnlyFlagged() throws {
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
    func testBinaryDataStripped() throws {
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

    // MARK: - Minimal Matcher

    @ButtonHeistActor
    func testMinimalMatcherPrefersIdentifier() {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el", label: "Save", identifier: "saveButton", traits: [.button])
        let other = makeElement(heistId: "other", label: "Cancel", traits: [.button])

        let matcher = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, other])

        XCTAssertEqual(matcher.identifier, "saveButton")
        XCTAssertNil(matcher.label)
        XCTAssertNil(matcher.traits)
    }

    @ButtonHeistActor
    func testMinimalMatcherFallsToLabelTraits() {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el", label: "Save", traits: [.button])
        let other = makeElement(heistId: "other", label: "Cancel", traits: [.button])

        let matcher = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, other])

        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertNil(matcher.identifier)
    }

    @ButtonHeistActor
    func testMinimalMatcherUsesIdentifierWhenUnique() {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el1", label: "Item", identifier: "item_1", traits: [.staticText])
        let duplicate = makeElement(heistId: "el2", label: "Item", traits: [.staticText])

        let matcher = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, duplicate])

        XCTAssertEqual(matcher.identifier, "item_1")
        XCTAssertNil(matcher.label)
        XCTAssertNil(matcher.traits)
    }

    @ButtonHeistActor
    func testMinimalMatcherNeverUsesValue() {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el1", label: "Slider", value: "50%", traits: [.adjustable])
        let duplicate = makeElement(heistId: "el2", label: "Slider", value: "75%", traits: [.adjustable])

        let matcher = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, duplicate])

        XCTAssertEqual(matcher.label, "Slider")
        XCTAssertNil(matcher.value)
        XCTAssertEqual(matcher.traits, [.adjustable])
    }

    @ButtonHeistActor
    func testMinimalMatcherFiltersStateTraits() {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el1", label: "Toggle", traits: [.button, .selected])
        let other = makeElement(heistId: "el2", label: "Cancel", traits: [.button])

        let matcher = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, other])

        XCTAssertEqual(matcher.label, "Toggle")
        XCTAssertEqual(matcher.traits, [.button])
    }

    @ButtonHeistActor
    func testMinimalMatcherAcceptsAmbiguityRatherThanUseState() {
        let bookKeeper = makeBookKeeper()
        let target = makeElement(heistId: "el1", label: "Item", traits: [.staticText])
        let duplicate = makeElement(heistId: "el2", label: "Item", traits: [.staticText])

        let matcher = bookKeeper.buildMinimalMatcher(element: target, allElements: [target, duplicate])

        XCTAssertEqual(matcher.label, "Item")
        XCTAssertEqual(matcher.traits, [.staticText])
        XCTAssertNil(matcher.value)
        XCTAssertNil(matcher.identifier)
    }

    // MARK: - Expectation Generation

    @ButtonHeistActor
    func testExpectationScreenChanged() {
        let bookKeeper = makeBookKeeper()
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 5)
        let result = makeActionResult(delta: delta)
        let expect = bookKeeper.generateExpectation(
            actionResult: result, args: [:], interfaceCache: [:], allElements: []
        )
        XCTAssertEqual(expect, .string("screen_changed"))
    }

    @ButtonHeistActor
    func testExpectationNoChange() {
        let bookKeeper = makeBookKeeper()
        let delta = InterfaceDelta(kind: .noChange, elementCount: 5)
        let result = makeActionResult(delta: delta)
        let expect = bookKeeper.generateExpectation(
            actionResult: result, args: [:], interfaceCache: [:], allElements: []
        )
        XCTAssertNil(expect)
    }

    @ButtonHeistActor
    func testExpectationElementUpdatedValue() {
        let bookKeeper = makeBookKeeper()
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(
                heistId: "slider_volume",
                changes: [PropertyChange(property: .value, old: "30%", new: "50%")]
            )]
        )
        let result = makeActionResult(delta: delta)
        let expect = bookKeeper.generateExpectation(
            actionResult: result,
            args: ["heistId": "slider_volume"],
            interfaceCache: [:],
            allElements: []
        )
        let expected = HeistValue.object([
            "elementUpdated": .object([
                "property": .string("value"),
                "newValue": .string("50%"),
            ]),
        ])
        XCTAssertEqual(expect, expected)
    }

    @ButtonHeistActor
    func testExpectationGeometryOnlyFallsToElementsChanged() {
        let bookKeeper = makeBookKeeper()
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(
                heistId: "btn",
                changes: [PropertyChange(property: .frame, old: "0,0,100,44", new: "10,0,100,44")]
            )]
        )
        let result = makeActionResult(delta: delta)
        let expect = bookKeeper.generateExpectation(
            actionResult: result, args: ["heistId": "btn"], interfaceCache: [:], allElements: []
        )
        XCTAssertEqual(expect, .string("elements_changed"))
    }

    @ButtonHeistActor
    func testExpectationElementAppeared() {
        let bookKeeper = makeBookKeeper()
        let addedElement = makeElement(heistId: "new_task", label: "New Task", traits: [.staticText])
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 6,
            added: [addedElement]
        )
        let result = makeActionResult(delta: delta)
        let expect = bookKeeper.generateExpectation(
            actionResult: result, args: [:], interfaceCache: [:], allElements: [addedElement]
        )
        guard case .object(let dict) = expect,
              let appeared = dict["elementAppeared"],
              case .object(let matcherDict) = appeared else {
            return XCTFail("Expected elementAppeared object, got \(String(describing: expect))")
        }
        XCTAssertEqual(matcherDict["label"], .string("New Task"))
    }

    @ButtonHeistActor
    func testExpectationElementDisappeared() {
        let bookKeeper = makeBookKeeper()
        let removedElement = makeElement(heistId: "button_old", label: "Old", traits: [.button])
        let cache: [String: HeistElement] = ["button_old": removedElement]
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 4,
            removed: ["button_old"]
        )
        let result = makeActionResult(delta: delta)
        let expect = bookKeeper.generateExpectation(
            actionResult: result, args: [:], interfaceCache: cache, allElements: [removedElement]
        )
        guard case .object(let dict) = expect,
              let disappeared = dict["elementDisappeared"],
              case .object(let matcherDict) = disappeared else {
            return XCTFail("Expected elementDisappeared object, got \(String(describing: expect))")
        }
        XCTAssertEqual(matcherDict["label"], .string("Old"))
    }

    @ButtonHeistActor
    func testExpectationCompoundForInsertionAndUpdate() {
        let bookKeeper = makeBookKeeper()
        let addedElement = makeElement(heistId: "new", label: "New Row", traits: [.staticText])
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 6,
            added: [addedElement],
            updated: [ElementUpdate(
                heistId: "counter",
                changes: [PropertyChange(property: .value, old: "2", new: "3")]
            )]
        )
        let result = makeActionResult(delta: delta)
        let expect = bookKeeper.generateExpectation(
            actionResult: result,
            args: ["heistId": "counter"],
            interfaceCache: [:],
            allElements: [addedElement]
        )
        guard case .array(let items) = expect else {
            return XCTFail("Expected array, got \(String(describing: expect))")
        }
        XCTAssertEqual(items.count, 2)
    }

    // MARK: - Expectation Matcher (state enrichment)

    @ButtonHeistActor
    func testExpectationMatcherIncludesStateTraits() {
        let bookKeeper = makeBookKeeper()
        let element = makeElement(heistId: "el", label: "Submit", traits: [.button, .notEnabled])
        let other = makeElement(heistId: "other", label: "Cancel", traits: [.button])

        let matcher = bookKeeper.buildExpectationMatcher(element: element, allElements: [element, other])

        XCTAssertEqual(matcher.label, "Submit")
        XCTAssertTrue(matcher.traits?.contains(.button) == true)
        XCTAssertTrue(matcher.traits?.contains(.notEnabled) == true)
    }

    @ButtonHeistActor
    func testExpectationMatcherIncludesValue() {
        let bookKeeper = makeBookKeeper()
        let element = makeElement(heistId: "el", label: "Counter", value: "6", traits: [.staticText])
        let other = makeElement(heistId: "other", label: "Title", traits: [.staticText])

        let matcher = bookKeeper.buildExpectationMatcher(element: element, allElements: [element, other])

        XCTAssertEqual(matcher.label, "Counter")
        XCTAssertEqual(matcher.value, "6")
    }

    @ButtonHeistActor
    func testExpectationMatcherNoStateWhenDefault() {
        let bookKeeper = makeBookKeeper()
        let element = makeElement(heistId: "el", label: "OK", traits: [.button])
        let other = makeElement(heistId: "other", label: "Cancel", traits: [.button])

        let matcher = bookKeeper.buildExpectationMatcher(element: element, allElements: [element, other])

        XCTAssertEqual(matcher.label, "OK")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertNil(matcher.value)
    }

    private func makeActionResult(delta: InterfaceDelta?) -> ActionResult {
        ActionResult(
            success: true,
            method: .syntheticTap,
            interfaceDelta: delta
        )
    }

    // MARK: - Heist File I/O

    @ButtonHeistActor
    func testWriteAndReadHeist() throws {
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
    func testRecoverAbandonedSessionCompressesLog() throws {
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
    func testRecoverSkipsCleanSessions() throws {
        let sessionDir = tempDirectory.appendingPathComponent("clean-2026-04-03-120000")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try Data().write(to: sessionDir.appendingPathComponent("session.jsonl.gz"))

        let bookKeeper = makeBookKeeper()
        let recovered = bookKeeper.recoverAbandonedSessions()

        XCTAssertTrue(recovered.isEmpty)
    }

    @ButtonHeistActor
    func testRecoverPreservesHeistEvidence() throws {
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
    func testRecoverEmptyBaseDirectory() {
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
