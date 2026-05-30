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

    @ButtonHeistActor
    func testStartsAppendsAndFinishesHeistRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.startRecording(identifier: "checkout-flow", app: "com.example.app")

        try bookKeeper.appendStep(
            try HeistStep(command: "activate", target: semanticTarget(label: "Pay", traits: [.button]))
        )
        let heist = try bookKeeper.finishRecording()

        XCTAssertFalse(bookKeeper.isRecordingHeist)
        XCTAssertEqual(heist.version, HeistPlayback.currentVersion)
        XCTAssertEqual(heist.app, "com.example.app")
        XCTAssertEqual(heist.steps, [
            try HeistStep(command: "activate", target: semanticTarget(label: "Pay", traits: [.button])),
        ])
    }

    @ButtonHeistActor
    func testRejectsStartWhileRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.startRecording(identifier: "first", app: "com.example.app")

        XCTAssertThrowsError(try bookKeeper.startRecording(identifier: "second", app: "com.example.app")) { error in
            guard case BookKeeperError.heistRecording(.alreadyRecording) = error else {
                return XCTFail("Expected alreadyRecording, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRejectsUnsafeHeistIdentifier() async {
        let bookKeeper = makeBookKeeper()

        XCTAssertThrowsError(try bookKeeper.startRecording(identifier: "../archive", app: "com.example.app")) { error in
            guard case BookKeeperError.unsafePath("../archive") = error else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRejectsFinishWhenIdle() async {
        let bookKeeper = makeBookKeeper()

        XCTAssertThrowsError(try bookKeeper.finishRecording()) { error in
            guard case BookKeeperError.heistRecording(.notRecording) = error else {
                return XCTFail("Expected notRecording, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRejectsEmptyRecordingAndLeavesRecorderIdle() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.startRecording(identifier: "empty", app: "com.example.app")

        XCTAssertThrowsError(try bookKeeper.finishRecording()) { error in
            guard case BookKeeperError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
        XCTAssertFalse(bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testAbandonedRecordingCleansHandleAndAllowsNewRecording() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.startRecording(identifier: "abandoned", app: "com.example.app")
        let abandonedPath = try XCTUnwrap(bookKeeper.recordingFilePath)
        try bookKeeper.appendStep(try HeistStep(command: "activate", target: semanticTarget(label: "Old")))

        bookKeeper.abandonRecording()

        XCTAssertFalse(bookKeeper.isRecordingHeist)
        XCTAssertTrue(FileManager.default.fileExists(atPath: abandonedPath.path))
        try bookKeeper.startRecording(identifier: "new", app: "com.example.app")
        try bookKeeper.appendStep(try HeistStep(command: "activate", target: semanticTarget(label: "New")))
        let heist = try bookKeeper.finishRecording()
        XCTAssertEqual(heist.steps[0].target, semanticTarget(label: "New"))
    }

    @ButtonHeistActor
    func testMalformedStepFailsWithLineNumber() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.startRecording(identifier: "malformed", app: "com.example.app")
        let path = try XCTUnwrap(bookKeeper.recordingFilePath)

        try bookKeeper.appendStep(try HeistStep(command: "activate", target: semanticTarget(label: "Go")))
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not-json\n".utf8))
        try handle.close()

        XCTAssertThrowsError(try bookKeeper.finishRecording()) { error in
            guard case BookKeeperError.heistRecording(.stepReadFailed(let failedPath, let reason)) = error else {
                return XCTFail("Expected stepReadFailed, got \(error)")
            }
            XCTAssertEqual(failedPath, path.path)
            XCTAssertTrue(reason.contains("line 2 is malformed"))
        }
    }

    @ButtonHeistActor
    func testRecordHeistStepDerivesMatcherFromCaptureLocalHeistId() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.startRecording(identifier: "semantic", app: "com.example.app")

        let element = HeistElement(
            heistId: "button_submit",
            description: "Submit",
            label: "Submit",
            value: nil,
            identifier: "checkout.submit",
            traits: [.button],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
        let capture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeReceiptTestInterface([element], timestamp: Date(timeIntervalSince1970: 0))
        )

        try recordHeistStep(
            bookKeeper,
            command: .activate,
            args: ["target": targetArgumentValue(heistId: "button_submit")],
            targetCapture: capture
        )
        let heist = try bookKeeper.finishRecording()

        XCTAssertEqual(heist.steps[0].target, semanticTarget(identifier: "checkout.submit"))
    }

    @ButtonHeistActor
    func testRecordHeistStepSkipsFailedActions() async throws {
        let bookKeeper = makeBookKeeper()
        try bookKeeper.startRecording(identifier: "failed-actions", app: "com.example.app")

        try recordHeistStep(
            bookKeeper,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Missing")],
            actionResult: ActionResult(success: false, method: .activate, errorKind: .elementNotFound),
            targetCapture: nil
        )
        try recordHeistStep(
            bookKeeper,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Go")],
            targetCapture: nil
        )

        let heist = try bookKeeper.finishRecording()
        XCTAssertEqual(heist.steps.map(\.target), [semanticTarget(label: "Go")])
    }

    @ButtonHeistActor
    func testWriteAndReadHeist() async throws {
        let heist = HeistPlayback(
            app: "com.example.app",
            steps: [
                try HeistStep(command: "activate", target: semanticTarget(label: "Go", traits: [.button])),
                try HeistStep(command: "type_text", arguments: ["text": .string("test")]),
            ]
        )

        let filePath = tempDirectory.appendingPathComponent("test.heist")
        try TheBookKeeper.writeHeist(heist, to: filePath)

        let loaded = try TheBookKeeper.readHeist(from: filePath)
        XCTAssertEqual(loaded, heist)
    }

    @ButtonHeistActor
    private func makeBookKeeper() -> TheBookKeeper {
        TheBookKeeper(baseDirectory: tempDirectory)
    }
}

@ButtonHeistActor
private func recordHeistStep(
    _ bookKeeper: TheBookKeeper,
    command: TheFence.Command,
    args: [String: HeistValue],
    actionResult: ActionResult? = nil,
    expectation: ExpectationResult? = nil,
    targetCapture: AccessibilityTrace.Capture?
) throws {
    var request = args
    request["requestId"] = .string("test")
    let parsed = try TheFence(configuration: .init()).parseRequest(
        command: command,
        arguments: TheFence.CommandArgumentEnvelope(values: request)
    )
    bookKeeper.recordHeistStep(
        parsed,
        actionResult: actionResult,
        expectation: expectation,
        targetCapture: targetCapture
    )
}
