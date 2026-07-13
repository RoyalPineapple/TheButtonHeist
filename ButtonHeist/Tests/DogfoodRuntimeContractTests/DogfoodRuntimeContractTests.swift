#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class DogfoodRuntimeContractTests: XCTestCase {

    func testPublicRootInputsAndPrebuiltPlansDriveDemoApp() async throws {
        let stringRoot = try await runHeist("DogfoodFillProfileName", argument: "Grace Hopper") { name in
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")
            try TextInputScreen.fillProfile(name)

            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()
        }

        XCTAssertEqual(stringRoot.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
        ])
        XCTAssertTrue(stringRoot.result.actionMethods.contains(.typeText))
        XCTAssertTrue(stringRoot.result.actionMethods.contains(.resignFirstResponder))

        let targetRoot = try await runHeist(
            "DogfoodActivatePrimaryButton",
            argument: .element(.label("Primary Button"), .traits([.button]))
        ) { target in
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Buttons & Actions")

            Activate(target)
                .expect(.exists(.label("Tap count: 1")), timeout: .seconds(2))

            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()
        }

        XCTAssertEqual(targetRoot.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .action,
            .invoke,
            .invoke,
        ])
        XCTAssertTrue(targetRoot.result.actionMethods.contains(.activate))

        let prebuilt = try HeistPlan("DogfoodPrebuiltCalculator") {
            try DogfoodHome.openScreen("Calculator")
            try CalculatorScreen.addSevenAndFive()
            try DemoNavigation.backToRoot()
        }
        let prebuiltRun = try await runHeist(prebuilt)

        XCTAssertEqual(prebuiltRun.result.steps.map(\.kind), [.invoke, .invoke, .invoke])
        XCTAssertEqual(prebuiltRun.result.steps.first?.reportDisplayName, #"RunHeist("DemoHome.openScreen", "Calculator")"#)
    }

    func testRuntimeControlFlowAndLoopResultsUseDemoAppEvidence() async throws {
        let heist = try await runHeist("DogfoodRuntimeControlFlowAndLoops") {
            try DogfoodHome.openScreen("Controls Demo")

            If {
                Case(.exists(.label("Controls Demo"))) {
                    Warn("conditional matched Controls Demo")
                }
                Else {
                    Fail("conditional missed Controls Demo")
                }
            }

            WaitFor(.exists(.label("Controls Demo")), timeout: .seconds(2))
                .else {
                    Fail("wait case missed Controls Demo")
                }

            Warn("wait case matched Controls Demo")

            ForEach(ElementPredicate(label: "Text Input", traits: [.button]), limit: 1) { target in
                WaitFor(.exists(target), timeout: .seconds(1))
            }

            try DemoNavigation.backToRoot()
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .conditional,
            .wait,
            .warn,
            .forEachElement,
            .invoke,
        ])
        XCTAssertEqual(
            heist.result.steps[1].caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.matchedCase(index: 0)
        )
        XCTAssertEqual(heist.result.steps[2].waitEvidence?.expectation.met, true)
        XCTAssertEqual(heist.result.steps[4].forEachElementEvidence?.matchedCount, 1)
        XCTAssertEqual(heist.result.steps[4].forEachElementEvidence?.iterationCount, 1)
        XCTAssertEqual(heist.result.warnings.map(\.message), [
            "conditional matched Controls Demo",
            "wait case matched Controls Demo",
        ])
    }

    func testAdvancedRuntimeActionsUsePublicHeistsAgainstDemoApp() async throws {
        let heist = try await runHeist("DogfoodAdvancedRuntimeActions") {
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Adjustable Controls")
            try AdjustableControlsScreen.adjustVolume()
            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()

            try DogfoodHome.openScreen("Custom Rotors")
            try CustomRotorsScreen.findFirstError()
            try DemoNavigation.backToRoot()

            try DogfoodHome.openScreen("Touch Canvas")
            try TouchCanvasScreen.exerciseMechanicalGestures()
            try DemoNavigation.backToRoot()
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
        ])
        XCTAssertTrue(heist.result.actionMethods.contains(.increment))
        XCTAssertTrue(heist.result.actionMethods.contains(.decrement))
        XCTAssertTrue(heist.result.actionMethods.contains(.rotor))
        XCTAssertTrue(heist.result.actionMethods.contains(.syntheticTap))
        XCTAssertTrue(heist.result.actionMethods.contains(.syntheticLongPress))
        XCTAssertTrue(heist.result.actionMethods.contains(.syntheticSwipe))
        XCTAssertTrue(heist.result.actionMethods.contains(.syntheticDrag))
    }

    func testViewportRuntimeCommandsUseDemoAppThroughDirectDispatch() async throws {
        addTeardownBlock {
            let cleanupHeist = try await runHeist("DogfoodViewportRuntimeCleanup") {
                try DemoNavigation.backToRoot()
            }
            XCTAssertEqual(cleanupHeist.result.steps.map(\.kind), [.invoke])
        }

        let openHeist = try await runHeist("DogfoodOpenLongListForViewportRuntimeCommands") {
            try DogfoodHome.openScreen("Long List")
            try LongListScreen.openTopAnchor()
        }

        XCTAssertEqual(openHeist.result.steps.map(\.kind), [.invoke, .invoke])

        let results = try await executeDirectRuntimeActions([
            .viewportScrollToEdge(ScrollToEdgeTarget(edge: .top)),
            .viewportScroll(ScrollTarget(direction: .down)),
            .viewportScrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
            .viewportScrollToVisible(.label("Widget 0, Hardware")),
        ])

        XCTAssertEqual(results.count, 4)

        let topResult = results[0]
        XCTAssertTrue(topResult.outcome.isSuccess, topResult.message ?? "scroll_to_edge top failed")
        XCTAssertEqual(topResult.method, .scrollToEdge)

        let scrollResult = results[1]
        XCTAssertTrue(scrollResult.outcome.isSuccess, scrollResult.message ?? "scroll failed")
        XCTAssertEqual(scrollResult.method, .scroll)

        let bottomResult = results[2]
        XCTAssertTrue(bottomResult.outcome.isSuccess, bottomResult.message ?? "scroll_to_edge bottom failed")
        XCTAssertEqual(bottomResult.method, .scrollToEdge)

        let visibleResult = results[3]
        XCTAssertTrue(visibleResult.outcome.isSuccess, visibleResult.message ?? "scroll_to_visible failed")
        XCTAssertEqual(visibleResult.method, .scrollToVisible)
    }

    func testDirectRuntimeSessionStopsResourcesAfterSuccessAndFailure() async throws {
        var successfulJob: TheInsideJob?
        let value = try await withDirectRuntimeSession { job in
            successfulJob = job
            return "success"
        }

        XCTAssertEqual(value, "success")
        assertDirectRuntimeStopped(try XCTUnwrap(successfulJob))

        var failedJob: TheInsideJob?
        do {
            let _: Void = try await withDirectRuntimeSession { job in
                failedJob = job
                throw DirectRuntimeSessionProbeError.expected
            }
            XCTFail("Expected direct runtime operation to throw")
        } catch let error as DirectRuntimeSessionProbeError {
            XCTAssertEqual(error, .expected)
        }

        assertDirectRuntimeStopped(try XCTUnwrap(failedJob))
    }

    func testFailedDogfoodHeistPreservesInspectableRunResult() async throws {
        do {
            _ = try await runHeist("DogfoodIntentionalFailure") {
                WaitFor(.exists(.label("ButtonHeist Demo")), timeout: .seconds(2))
                Warn("before dogfood failure")
                Fail("intentional dogfood failure")
                Warn("after dogfood failure")
            }
            XCTFail("Expected failed dogfood heist to throw")
        } catch let failure as Heist.Failure {
            XCTAssertEqual(failure.failedStepPath, "$.body[2]")
            XCTAssertEqual(failure.failedStepKind, .fail)
            XCTAssertEqual(failure.message, "intentional dogfood failure")
            XCTAssertEqual(failure.result.abortedAtPath, "$.body[2]")
            XCTAssertEqual(failure.result.steps.map(\.kind), [.wait, .warn, .fail, .warn, .action])
            XCTAssertEqual(failure.result.steps.map(\.status), [.passed, .passed, .failed, .skipped, .passed])
            XCTAssertEqual(failure.result.executedTopLevelStepCount, 3)
            XCTAssertEqual(failure.result.executedNodeCount, 4)
            XCTAssertEqual(failure.result.outputReceiptNodes.map(\.kind), [.wait, .warn, .fail, .warn, .action])
            XCTAssertEqual(
                failure.result.outputReceiptNodes.map(\.path),
                ["$.body[0]", "$.body[1]", "$.body[2]", "$.body[3]", "$.body[2].failure.actions[0]"]
            )
            XCTAssertEqual(failure.result.failureScreenshotStep?.path, "$.body[2].failure.actions[0]")
            XCTAssertEqual(failure.result.failureScreenshotStep?.actionEvidence?.command, .takeScreenshot)
            XCTAssertEqual(failure.result.expectationsChecked, 1)
            XCTAssertEqual(failure.result.expectationsMet, 1)
            XCTAssertEqual(failure.result.warnings, [
                HeistExecutionWarning(
                    path: "$.body[1]",
                    message: "before dogfood failure"
                ),
            ])
        }
    }
}

@MainActor
private func executeDirectRuntimeActions(_ commands: [HeistActionCommand]) async throws -> [ActionResult] {
    try await withDirectRuntimeSession { job in
        var results: [ActionResult] = []
        for command in commands {
            let result = await job.brains.executeRuntimeAction(try command.resolveForRuntimeDispatch(in: .empty))
            results.append(result)
        }
        return results
    }
}

@MainActor
private func withDirectRuntimeSession<Value>(
    _ operation: @MainActor (TheInsideJob) async throws -> Value
) async throws -> Value {
    let job = TheInsideJob(token: "dogfood-direct-runtime")
    job.tripwire.startPulse()
    job.brains.startSemanticObservation()
    job.brains.safecracker.startKeyboardObservation()
    job.brains.stash.clearInterfaceForHeistBootstrap()
    _ = await job.brains.interactionObservation.observeVisibleState(
        timeout: SemanticObservationTiming.defaultTimeout
    )

    let outcome: Result<Value, Error>
    do {
        outcome = .success(try await operation(job))
    } catch {
        outcome = .failure(error)
    }

    await stopDirectRuntime(job)
    return try outcome.get()
}

@MainActor
private func stopDirectRuntime(_ job: TheInsideJob) async {
    _ = await job.tripwire.waitForAllClear(timeout: SemanticObservationTiming.defaultTimeout)
    job.brains.stopSemanticObservation()
    job.tripwire.stopPulse()
    job.brains.safecracker.stopKeyboardObservation()
    job.brains.clearCache()
}

@MainActor
private func assertDirectRuntimeStopped(
    _ job: TheInsideJob,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(job.brains.semanticObservationIsActive, file: file, line: line)
    XCTAssertFalse(job.tripwire.isPulseRunning, file: file, line: line)
    XCTAssertEqual(job.brains.stash.interfaceElementCount, 0, file: file, line: line)
}

private enum DirectRuntimeSessionProbeError: Error, Equatable {
    case expected
}

#endif // canImport(UIKit)
