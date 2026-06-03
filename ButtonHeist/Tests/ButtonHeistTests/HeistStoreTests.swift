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
            ],
            expectation: ExpectationResult(
                met: true,
                predicate: .changed(.screen()),
                actual: "screen changed"
            )
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
    func testActionExpectationWaitRecordsOriginalActionIntent() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "validated-wait", app: "com.example.app")

        let expectation = AccessibilityPredicate.state(.absent(ElementPredicate(label: "Delete")))
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: [
                "target": targetArgumentValue(label: "Delete"),
                "expect": .object([
                    "type": .string("absent"),
                    "element": targetArgumentValue(label: "Delete"),
                ]),
            ],
            dispatchedResponse: .action(
                command: .activate,
                result: ActionResult(success: true, method: .activate)
            ),
            validatedResponse: .action(
                command: .wait,
                result: ActionResult(success: true, method: .wait),
                expectation: ExpectationResult(met: true, predicate: expectation, actual: "absent")
            )
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            try activateStep(
                label: "Delete",
                expectation: WaitStep(predicate: expectation, timeout: 10)
            ),
        ])
    }

    @ButtonHeistActor
    func testExplicitExpectationWithoutPassedValidationRecordsNothing() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "missing-expectation-proof", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: [
                "target": targetArgumentValue(label: "Delete"),
                "expect": .object([
                    "type": .string("absent"),
                    "element": targetArgumentValue(label: "Delete"),
                ]),
            ],
            dispatchedResponse: .action(
                command: .activate,
                result: ActionResult(success: true, method: .activate)
            ),
            validatedResponse: .action(
                command: .activate,
                result: ActionResult(success: true, method: .activate)
            )
        )

        XCTAssertThrowsError(try heistStore.finishRecording()) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
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
    func testRecordingObservationCommandsEmitNoStepsAndKeepRecordingActive() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scratchpad-reads", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .getInterface,
            args: [:],
            dispatchedResponse: .interface(Interface(timestamp: Date(), tree: []))
        )
        XCTAssertTrue(heistStore.isRecordingHeist)

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")]
        )
        try recordHeistStep(
            heistStore,
            command: .getInterface,
            args: [:],
            dispatchedResponse: .interface(Interface(timestamp: Date(), tree: []))
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [try activateStep(label: "Delete")])
    }

    @ButtonHeistActor
    func testExplicitWaitRecordsCheckpoint() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "explicit-wait", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .wait,
            args: [
                "predicate": presentPredicateArgumentValue(label: "Ready"),
                "timeout": .int(4),
            ],
            actionResult: ActionResult(success: true, method: .wait)
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            .wait(WaitStep(predicate: .state(.present(ElementPredicate(label: "Ready"))), timeout: 4)),
        ])
    }

    @ButtonHeistActor
    func testScrollToVisibleIsScratchpadViewportSetupDuringRecording() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scroll-setup", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .scrollToVisible,
            args: ["target": targetArgumentValue(label: "Delete")]
        )
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")]
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [try activateStep(label: "Delete")])
    }

    @ButtonHeistActor
    func testRecordingUsesMinimumMatcherFromSettledBeforeState() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "minimum-target", app: "com.example.app")

        let label = makeReceiptTestElement(label: "Delete", traits: [.staticText])
        let button = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete"), ordinal: 1),
            subject: button,
            before: [label, button],
            after: [label, button]
        )

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete", ordinal: 1)],
            actionResult: actionResult
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            try activateStep(label: "Delete", traits: [.button]),
        ])
    }

    @ButtonHeistActor
    func testUnsettledTraceDoesNotGenerateMinimumMatcherOrExpectation() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "unsettled-trace", app: "com.example.app")

        let label = makeReceiptTestElement(label: "Delete", traits: [.staticText])
        let button = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete"), ordinal: 1),
            subject: button,
            before: [label, button],
            after: [label],
            settled: false
        )

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete", ordinal: 1)],
            actionResult: actionResult
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            .action(try ActionStep(command: .activate(
                .predicate(ElementPredicate(label: "Delete"), ordinal: 1)
            ))),
        ])
    }

    @ButtonHeistActor
    func testRecordingInfersTargetDisappearedExpectation() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "target-disappeared", app: "com.example.app")

        let delete = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete")),
            subject: delete,
            before: [delete],
            after: []
        )

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")],
            actionResult: actionResult
        )

        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            try activateStep(
                label: "Delete",
                expectation: WaitStep(predicate: .state(.absentTarget(target)), timeout: 10)
            ),
        ])
    }

    @ButtonHeistActor
    func testRecordingInfersCurrentTextValueExpectation() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "text-value", app: "com.example.app")

        let before = makeReceiptTestElement(label: "Search", value: "", traits: [.searchField])
        let after = makeReceiptTestElement(label: "Search", value: "milk", traits: [.searchField])
        let actionResult = semanticActionResult(
            method: .typeText,
            source: .textInputTarget,
            target: .predicate(ElementPredicate(label: "Search")),
            subject: before,
            before: [before],
            after: [after],
            payload: .value("milk")
        )

        try recordHeistStep(
            heistStore,
            command: .typeText,
            args: [
                "target": targetArgumentValue(label: "Search"),
                "text": .string("milk"),
            ],
            actionResult: actionResult
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            .action(try ActionStep(
                command: .typeText(TypeTextTarget(
                    text: "milk",
                    elementTarget: .predicate(ElementPredicate(label: "Search"))
                )),
                expectation: WaitStep(
                    predicate: .state(.present(ElementPredicate(label: "Search", value: "milk"))),
                    timeout: 10
                )
            )),
        ])
    }

    @ButtonHeistActor
    func testCoordinateTapRecordingDoesNotInferSemanticIntent() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "coordinate-tap", app: "com.example.app")

        let delete = makeReceiptTestElement(label: "Delete", traits: [.button])
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface([delete]),
            after: makeReceiptTestInterface([])
        )
        let actionResult = ActionResult(
            success: true,
            method: .syntheticTap,
            accessibilityTrace: trace,
            settled: true
        )

        try recordHeistStep(
            heistStore,
            command: .oneFingerTap,
            args: ["point": .object(["x": .double(20), "y": .double(30)])],
            actionResult: actionResult
        )

        let heist = try heistStore.finishRecording()
        XCTAssertEqual(heist.steps, [
            .action(try ActionStep(command: .oneFingerTap(TapTarget(
                selection: .coordinate(ScreenPoint(x: 20, y: 30))
            )))),
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

private func presentPredicateArgumentValue(label: String) -> HeistValue {
    .object([
        "type": .string("present"),
        "element": targetArgumentValue(label: label),
    ])
}

@ButtonHeistActor
private func recordHeistStep(
    _ heistStore: HeistStore,
    command: TheFence.Command,
    args: [String: HeistValue],
    actionResult: ActionResult? = nil,
    expectation: ExpectationResult? = nil,
    dispatchedResponse: FenceResponse? = nil,
    validatedResponse: FenceResponse? = nil
) throws {
    var request = args
    request["requestId"] = .string("test")
    let fence = TheFence(configuration: .init())
    let parsed = try fence.parseRequest(
        command: command,
        arguments: TheFence.CommandArgumentEnvelope(values: request)
    )
    let dispatched = dispatchedResponse ?? defaultRecordingResponse(
        command: command,
        result: actionResult
    )
    let validated = validatedResponse ?? FenceResponse.action(
        command: command,
        result: actionResult ?? defaultActionResult(for: command),
        expectation: expectation
    )
    let steps = try HeistRecordingComposition(
        request: parsed,
        dispatchedResponse: dispatched,
        validatedResponse: validated
    ).steps()
    try heistStore.appendRecordingSteps(steps)
}

private func defaultRecordingResponse(
    command: TheFence.Command,
    result: ActionResult?
) -> FenceResponse {
    .action(command: command, result: result ?? defaultActionResult(for: command))
}

private func defaultActionResult(for command: TheFence.Command) -> ActionResult {
    switch command {
    case .wait:
        return ActionResult(success: true, method: .wait)
    case .scrollToVisible:
        return ActionResult(success: true, method: .scrollToVisible)
    default:
        return ActionResult(success: true, method: .activate)
    }
}

private func semanticActionResult(
    method: ActionMethod,
    source: ActionSubjectEvidence.Source,
    target: ElementTarget,
    subject: HeistElement,
    before: [HeistElement],
    after: [HeistElement],
    payload: ResultPayload? = nil,
    settled: Bool = true
) -> ActionResult {
    ActionResult(
        success: true,
        method: method,
        payload: payload,
        accessibilityTrace: makeReceiptTestTrace(
            before: makeReceiptTestInterface(before),
            after: makeReceiptTestInterface(after)
        ),
        settled: settled,
        subjectEvidence: ActionSubjectEvidence(
            source: source,
            target: target,
            element: subject,
            settledObservationSequence: 1
        )
    )
}
