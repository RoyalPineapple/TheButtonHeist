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
        let heist = try finishRecording(heistStore)

        XCTAssertFalse(heistStore.isRecordingHeist)
        XCTAssertEqual(heist.version, HeistPlan.currentVersion)
        XCTAssertEqual(heist.name, "recordedHeist")
        XCTAssertEqual(heist.body, [
            try activateStep(label: "Pay", traits: [.button]),
        ])
    }

    @ButtonHeistActor
    func testRecordingUsesValidIdentifierAsPlanName() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "checkoutFlow", app: "com.example.app")
        try heistStore.appendStep(try activateStep(label: "Pay", traits: [.button]))

        let heist = try finishRecording(heistStore)

        XCTAssertEqual(heist.name, "checkoutFlow")
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

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.notRecording) = error else {
                return XCTFail("Expected notRecording, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testRejectsEmptyRecordingAndLeavesRecorderIdle() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "empty", app: "com.example.app")

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
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
        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body[0], try activateStep(label: "New"))
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

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [try activateStep(label: "Go")])
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
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

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [try activateStep(label: "Delete")])
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [try activateStep(label: "Delete")])
    }

    @ButtonHeistActor
    func testManualScrollBeforeSemanticActionRecordsOnlySemanticAction() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "manual-scroll-setup", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")]
        )

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [try activateStep(label: "Delete")])
    }

    @ButtonHeistActor
    func testReadBetweenManualScrollAndSemanticActionPreservesSemanticRecording() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scroll-read-semantic", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )
        try recordHeistStep(
            heistStore,
            command: .getInterface,
            args: [:],
            dispatchedResponse: .interface(Interface(timestamp: Date(), tree: []))
        )
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")]
        )

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [try activateStep(label: "Delete")])
    }

    @ButtonHeistActor
    func testManualScrollBeforeFailedSemanticActionDoesNotRecordScrollOnlyHeist() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scroll-before-failed-semantic", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")],
            actionResult: ActionResult(success: false, method: .activate, errorKind: .elementNotFound)
        )

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testManualScrollBeforeUnmetSemanticExpectationDoesNotRecordScrollOnlyHeist() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scroll-before-unmet-expectation", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )
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
            expectation: ExpectationResult(
                met: false,
                predicate: .state(.absent(ElementPredicate(label: "Delete"))),
                actual: "Delete still present"
            )
        )

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testManualScrollBeforeAmbiguousSemanticActionDoesNotRecordScrollOnlyHeist() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scroll-before-ambiguous-semantic", app: "com.example.app")

        let first = makeReceiptTestElement(label: "Delete", traits: [.button])
        let second = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete")),
            subject: first,
            before: [first, second],
            after: [first, second]
        )

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")],
            actionResult: actionResult
        )

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testExplicitViewportScrollIsNotRecordedInNormalSemanticRecording() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "explicit-scroll", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testManualScrollBeforeMechanicalTapRecordsOnlyMechanicalIntent() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scroll-before-mechanical-tap", app: "com.example.app")

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )
        try recordHeistStep(
            heistStore,
            command: .oneFingerTap,
            args: ["point": .object(["x": .double(20), "y": .double(30)])],
            actionResult: ActionResult(success: true, method: .syntheticTap)
        )

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
            .action(try ActionStep(command: .oneFingerTap(TapTarget(
                selection: .coordinate(ScreenPoint(x: 20, y: 30))
            )))),
        ])
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
            try activateStep(label: "Delete", traits: [.button]),
        ])
        let encodedData = try JSONEncoder().encode(heist)
        let encoded = try XCTUnwrap(String(bytes: encodedData, encoding: .utf8))
        XCTAssertFalse(encoded.contains("frameX"))
        XCTAssertFalse(encoded.contains("activationPoint"))
        XCTAssertFalse(encoded.contains("heistId"))
        XCTAssertFalse(encoded.contains("containerName"))
        XCTAssertFalse(encoded.contains("capture"))
    }

    @ButtonHeistActor
    func testRecordingSemanticPhysicalTapEvidenceRecordsActivateIntent() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "semantic-tap-evidence", app: "com.example.app")

        let label = makeReceiptTestElement(label: "Delete", traits: [.staticText])
        let button = makeReceiptTestElement(
            label: "Delete",
            traits: [.button],
            actions: [.activate]
        )
        let actionResult = semanticActionResult(
            method: .syntheticTap,
            source: .elementGestureTarget,
            target: .predicate(ElementPredicate(label: "Delete"), ordinal: 1),
            subject: button,
            before: [label, button],
            after: [label, button]
        )

        try recordHeistStep(
            heistStore,
            command: .oneFingerTap,
            args: ["point": .object(["x": .double(20), "y": .double(30)])],
            actionResult: actionResult
        )

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
            try activateStep(label: "Delete", traits: [.button]),
        ])
    }

    @ButtonHeistActor
    func testRecordingNonActivatablePhysicalTapEvidenceKeepsMechanicalIntent() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "non-activatable-tap-evidence", app: "com.example.app")

        let caption = makeReceiptTestElement(label: "Caption", traits: [.staticText])
        let actionResult = semanticActionResult(
            method: .syntheticTap,
            source: .elementGestureTarget,
            target: .predicate(ElementPredicate(label: "Caption")),
            subject: caption,
            before: [caption],
            after: [caption]
        )

        try recordHeistStep(
            heistStore,
            command: .oneFingerTap,
            args: ["element": targetArgumentValue(label: "Caption")],
            actionResult: actionResult
        )

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
            .action(try ActionStep(command: .oneFingerTap(TapTarget(
                selection: .element(.predicate(ElementPredicate(label: "Caption")))
            )))),
        ])
    }

    @ButtonHeistActor
    func testUnsettledSemanticTraceRecordsNoStep() async throws {
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

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testManualScrollBeforeUnsettledSemanticActionDoesNotRecordScrollOnlyHeist() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "scroll-before-unsettled-semantic", app: "com.example.app")

        let button = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete")),
            subject: button,
            before: [button],
            after: [button],
            settled: false
        )

        try recordHeistStep(
            heistStore,
            command: .scroll,
            args: ["direction": .string("down")]
        )
        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")],
            actionResult: actionResult
        )

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
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
        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
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
    func testRecordingInfersCurrentSelectionStateExpectation() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "selection-state", app: "com.example.app")

        let before = makeReceiptTestElement(label: "Wi-Fi", traits: [.button])
        let after = makeReceiptTestElement(label: "Wi-Fi", traits: [.button, .selected])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Wi-Fi")),
            subject: before,
            before: [before],
            after: [after]
        )

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Wi-Fi")],
            actionResult: actionResult
        )

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
            try activateStep(
                label: "Wi-Fi",
                expectation: WaitStep(
                    predicate: .state(.present(ElementPredicate(label: "Wi-Fi", traits: [.selected]))),
                    timeout: 10
                )
            ),
        ])
    }

    @ButtonHeistActor
    func testRecordingInfersScreenChangeWhenNoPreciseTargetExpectationExists() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "screen-change", app: "com.example.app")

        let continueButton = makeReceiptTestElement(label: "Continue", traits: [.button])
        let nextHeader = makeReceiptTestElement(label: "Dashboard", traits: [.header])
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface([continueButton]),
            after: makeReceiptTestInterface([continueButton, nextHeader]),
            beforeScreenId: "login",
            afterScreenId: "dashboard"
        )
        let actionResult = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace,
            settled: true,
            subjectEvidence: ActionSubjectEvidence(
                source: .resolvedSemanticTarget,
                target: .predicate(ElementPredicate(label: "Continue")),
                element: continueButton,
                settledObservationSequence: 1
            )
        )

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Continue")],
            actionResult: actionResult
        )

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
            try activateStep(
                label: "Continue",
                expectation: WaitStep(predicate: .changed(.screen()), timeout: 10)
            ),
        ])
    }

    @ButtonHeistActor
    func testAmbiguousSemanticEvidenceRecordsNoStep() async throws {
        let heistStore = makeHeistStore()
        try heistStore.startRecording(identifier: "ambiguous-semantic-evidence", app: "com.example.app")

        let first = makeReceiptTestElement(label: "Delete", traits: [.button])
        let second = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete")),
            subject: first,
            before: [first, second],
            after: [first, second]
        )

        try recordHeistStep(
            heistStore,
            command: .activate,
            args: ["target": targetArgumentValue(label: "Delete")],
            actionResult: actionResult
        )

        XCTAssertThrowsError(try finishRecording(heistStore)) { error in
            guard case StorageError.heistRecording(.noValidSteps) = error else {
                return XCTFail("Expected noValidSteps, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testCoordinateTapWithoutSemanticEvidenceRecordsMechanicalIntent() async throws {
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

        let heist = try finishRecording(heistStore)
        XCTAssertEqual(heist.body, [
            .action(try ActionStep(command: .oneFingerTap(TapTarget(
                selection: .coordinate(ScreenPoint(x: 20, y: 30))
            )))),
        ])
    }

    @ButtonHeistActor
    func testHeistFileIORoundTripsHeist() async throws {
        let heist = HeistPlan(name: "recordedHeist", body: [
                try activateStep(label: "Go", traits: [.button]),
                .action(try ActionStep(command: .typeText(TypeTextTarget(text: "test")))),
            ]
        )

        let filePath = tempDirectory.appendingPathComponent("test.heist")
        try HeistFileIO.write(heist, to: filePath)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.appendingPathComponent("plan.json").path))

        let loaded = try HeistArtifactCodec.readPlan(from: filePath)
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
private var testRecordingLifecycles: [ObjectIdentifier: FenceHeistRecordingLifecycle] = [:]

@ButtonHeistActor
private func recordingLifecycle(for heistStore: HeistStore) -> FenceHeistRecordingLifecycle {
    let key = ObjectIdentifier(heistStore)
    if let lifecycle = testRecordingLifecycles[key] {
        return lifecycle
    }
    let lifecycle = FenceHeistRecordingLifecycle()
    lifecycle.begin()
    testRecordingLifecycles[key] = lifecycle
    return lifecycle
}

@ButtonHeistActor
private func finishRecording(_ heistStore: HeistStore) throws -> HeistPlan {
    let key = ObjectIdentifier(heistStore)
    guard let lifecycle = testRecordingLifecycles.removeValue(forKey: key) else {
        return try heistStore.finishRecording()
    }
    return try lifecycle.finish(using: heistStore)
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
    // Map the test's chosen responses onto the one-step execution evidence the
    // composition now consumes: the action's own ActionResult and the
    // server-evaluated ExpectationResult. A non-action `dispatchedResponse`
    // (e.g. `.interface`) yields a nil action result, exercising the
    // command-only discard/ignore paths.
    let resolvedActionResult: ActionResult?
    if let dispatchedResponse {
        resolvedActionResult = dispatchedResponse.actionResult
    } else {
        resolvedActionResult = actionResult ?? defaultActionResult(for: command)
    }
    let resolvedExpectation: ExpectationResult?
    if let validatedResponse {
        if case .action(_, _, let validatedExpectation) = validatedResponse {
            resolvedExpectation = validatedExpectation
        } else {
            resolvedExpectation = nil
        }
    } else {
        resolvedExpectation = expectation
    }
    let effect = try HeistRecordingComposition(
        request: parsed,
        actionResult: resolvedActionResult,
        expectation: resolvedExpectation
    ).effect()
    try recordingLifecycle(for: heistStore).apply(effect, to: heistStore)
}

private func defaultActionResult(for command: TheFence.Command) -> ActionResult {
    switch command {
    case .wait:
        return ActionResult(success: true, method: .wait)
    case .scroll:
        return ActionResult(success: true, method: .scroll)
    case .scrollToVisible:
        return ActionResult(success: true, method: .scrollToVisible)
    case .scrollToEdge:
        return ActionResult(success: true, method: .scrollToEdge)
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
