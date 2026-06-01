import XCTest
@testable import ButtonHeist
import TheScore

final class HeistStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = TempDirectoryFixture.make(prefix: "heist-store-tests")
    }

    override func tearDown() {
        TempDirectoryFixture.remove(tempDirectory)
        super.tearDown()
    }

    @ButtonHeistActor
    func testStartsAppendsAndFinishesHeistRecording() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "checkout-flow", app: "com.example.app")

        try heistStore.appendStep(
            try activateStep(label: "Pay", traits: [.button])
        )
        let heist = try heistStore.finishRecording()

        XCTAssertFalse(heistStore.isRecordingHeist)
        XCTAssertEqual(heist.version, HeistPlan.currentVersion)
        XCTAssertEqual(heist.steps, [
            try activateStep(label: "Pay", traits: [.button]),
        ])
    }

    @ButtonHeistActor
    func testRejectsStartWhileRecording() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "first", app: "com.example.app")

        XCTAssertThrowsError(try heistStore.startRecording(identifier: "second", app: "com.example.app")) { error in
            guard case StorageError.heistRecording(.alreadyRecording) = error else {
                return XCTFail("Expected alreadyRecording, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRejectsUnsafeHeistIdentifier() async {
        let heistStore = makeHeistStore()

        XCTAssertThrowsError(try heistStore.startRecording(identifier: "../archive", app: "com.example.app")) { error in
            guard case StorageError.unsafePath("../archive") = error else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRejectsFinishWhenIdle() async {
        let heistStore = makeHeistStore()

        XCTAssertThrowsError(try heistStore.finishRecording()) { error in
            guard case StorageError.heistRecording(.notRecording) = error else {
                return XCTFail("Expected notRecording, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRejectsEmptyRecordingAndLeavesRecorderIdle() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "empty", app: "com.example.app")

        XCTAssertThrowsError(try heistStore.finishRecording()) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
        XCTAssertFalse(heistStore.isRecordingHeist)
    }

    @ButtonHeistActor
    func testAbandonedRecordingCleansHandleAndAllowsNewRecording() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "abandoned", app: "com.example.app")
        let abandonedPath = try XCTUnwrap(heistStore.recordingFilePath)
        try heistStore.appendStep(try activateStep(label: "Old"))

        heistStore.abandonRecording()

        XCTAssertFalse(heistStore.isRecordingHeist)
        XCTAssertTrue(FileManager.default.fileExists(atPath: abandonedPath.path))
        try heistStore.startRecording(identifier: "new", app: "com.example.app")
        try heistStore.appendStep(try activateStep(label: "New"))
        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps[0], try activateStep(label: "New"))
    }

    @ButtonHeistActor
    func testMalformedStepFailsWithLineNumber() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "malformed", app: "com.example.app")
        let path = try XCTUnwrap(heistStore.recordingFilePath)

        try heistStore.appendStep(try activateStep(label: "Go"))
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not-json\n".utf8))
        try handle.close()

        XCTAssertThrowsError(try heistStore.finishRecording()) { error in
            guard case StorageError.heistRecording(.stepReadFailed(let failedPath, let reason)) = error else {
                return XCTFail("Expected stepReadFailed, got \(error)")
            }
            XCTAssertEqual(failedPath, path.path)
            XCTAssertTrue(reason.contains("line 2 is malformed"))
        }
    }

    @ButtonHeistActor
    func testRecordHeistStepSkipsFailedActions() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "failed-actions", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Missing")],
            actionResult: ActionResult(success: false, method: .activate, errorKind: .elementNotFound)
        )
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Go")]
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [try activateStep(label: "Go")])
    }

    @ButtonHeistActor
    func testRecordHeistStepKeepsOnlyDescriptorOwnedReplayArguments() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "descriptor-args", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: [
                "target": targetArgumentValue(label: "Save"),
                "expect": .object(["type": .string("screen_changed")]),
                "timeout": .double(2.5),
            ]
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            try activateStep(
                label: "Save",
                expectation: WaitStep(predicate: .changed(.screen()), timeout: 2.5)
            ),
        ])
    }

    @ButtonHeistActor
    func testRecordHeistStepDropsUnusedExpectationTimeout() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "unused-timeout", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: [
                "target": targetArgumentValue(label: "Save"),
                "timeout": .int(3),
            ]
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            try activateStep(label: "Save"),
        ])
    }

    @ButtonHeistActor
    func testWriteAndReadHeist() async throws {
        let heist = HeistPlan(
            steps: [
                try activateStep(label: "Go", traits: [.button]),
                .action(try ActionStep(command: .typeText(TypeTextTarget(text: "test")))),
            ]
        )

        let filePath = tempDirectory.appendingPathComponent("test.heist")
        try HeistStore.writeHeist(heist, to: filePath)

        let loaded = try HeistStore.readHeist(from: filePath)
        XCTAssertEqual(loaded, heist)
    }

    @ButtonHeistActor
    private func makeHeistStore() -> HeistStore {
        HeistStore(baseDirectory: tempDirectory)
    }
}

private func activateStep(
    label: String,
    traits: [HeistTrait] = [],
    expectation: WaitStep? = nil
) throws -> HeistStep {
    .action(try ActionStep(
        command: .activate(.predicate(ElementPredicate(label: label, traits: traits))),
        expectation: expectation
    ))
}

@ButtonHeistActor
private func recordHeistStep(
    _ heistStore: HeistStore,
    command: TheFence.Command,
    args: [String: HeistValue],
    actionResult: ActionResult? = nil,
    expectation: ExpectationResult? = nil
) throws {
    var request = args
    request["requestId"] = .string("test")
    let parsed = try TheFence(configuration: .init()).parseRequest(
        command: command,
        arguments: TheFence.CommandArgumentEnvelope(values: request)
    )
    heistStore.recordHeistStep(
        parsed,
        actionResult: actionResult,
        expectation: expectation
    )
}
