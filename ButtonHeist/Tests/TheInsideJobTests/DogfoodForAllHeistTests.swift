#if canImport(UIKit)
import XCTest

import TheInsideJob

private enum DogfoodHome {
    static let openScreen = HeistDef<String>("DemoHome.openScreen", parameter: "screen") { screen in
        try DogfoodNavigation.backToRootIfNeeded()

        Activate(.predicate(ElementPredicateTemplate(label: screen, traits: [.button])))
            .expect(.changed(.screen(where: .present(.label(screen)))), timeout: .seconds(8))
    }
}

private enum DogfoodNavigation {
    private static let controlsBackTarget = ElementPredicateTemplate(
        label: .literal("Controls Demo"),
        traits: [.backButton]
    )
    private static let rootBackTarget = ElementPredicateTemplate(
        label: .literal("ButtonHeist Demo"),
        traits: [.backButton]
    )

    static let backToRootIfNeeded = HeistDef<Void>("DogfoodNavigation.backToRootIfNeeded") {
        WaitFor(timeout: .milliseconds(500)) {
            Case(.present(controlsBackTarget)) {
                Activate(.predicate(controlsBackTarget))
                    .expect(.changed(.screen(where: .present(.label("Controls Demo")))), timeout: .seconds(8))
            }
            Else {}
        }

        WaitFor(timeout: .milliseconds(500)) {
            Case(.present(rootBackTarget)) {
                Activate(.predicate(rootBackTarget))
                    .expect(.changed(.screen(where: .present(.label("ButtonHeist Demo")))), timeout: .seconds(8))
            }
            Else {}
        }
    }

    static let backTo = HeistDef<String>("DogfoodNavigation.backTo", parameter: "title") { title in
        Activate(.predicate(ElementPredicateTemplate(label: title, traits: [.backButton])))
            .expect(.changed(.screen(where: .present(.label(title)))), timeout: .seconds(8))
    }
}

private enum ControlsDemoScreen {
    static let openScreen = HeistDef<String>("ControlsDemo.openScreen", parameter: "screen") { screen in
        Activate(.predicate(ElementPredicateTemplate(label: screen, traits: [.button])))
            .expect(.changed(.screen(where: .present(.label(screen)))), timeout: .seconds(8))
    }
}

private enum TextInputScreen {
    private static let nameField = ElementTarget.value("Name")
    private static let emailField = ElementTarget.value("Email")

    static let fillProfile = HeistDef<String>("TextInputScreen.fillProfile", parameter: "name") { name in
        TypeText(name, into: nameField)
            .expect(.present(.value(name)), timeout: .seconds(2))

        TypeText("dogfood@example.com", into: emailField)
            .expect(.present(.value("dogfood@example.com")), timeout: .seconds(2))

        DismissKeyboard()
            .withoutExpectation("Keyboard dismissal only prepares navigation")
    }

    static let pasteName = HeistDef<Void>("TextInputScreen.pasteName") {
        Activate(nameField)
            .withoutExpectation("Focuses the name field for the edit action")

        SetPasteboard("Dogfood clipboard name")
            .withoutExpectation("Seeds pasteboard for the public Edit(.paste) action")

        Edit(.paste)
            .expect(.present(.value("Dogfood clipboard name")), timeout: .seconds(2))

        DismissKeyboard()
            .withoutExpectation("Keyboard dismissal only prepares navigation")
    }
}

private enum TodoScreen {
    static let completeItem = HeistDef<String>("TodoScreen.completeItem", parameter: "item") { item in
        CustomAction("Toggle", on: .label(item))
            .expect(
                .present(ElementPredicateTemplate(label: item, value: StringExpr("Completed"))),
                timeout: .seconds(2)
            )
    }
}

private enum CalculatorScreen {
    static let addSevenAndFive = HeistDef<Void>("CalculatorScreen.addSevenAndFive") {
        Activate(.element(label: "all clear", traits: [.button]))
            .expect(.present(.label("0")), timeout: .seconds(1))

        Activate(.element(label: "7", traits: [.button]))
            .expect(.present(.label("7")), timeout: .seconds(1))

        Activate(.element(label: "+", traits: [.button]))
            .expect(.changed(.elements), timeout: .seconds(1))

        Activate(.element(label: "5", traits: [.button]))
            .expect(.present(.label("5")), timeout: .seconds(1))

        Activate(.element(label: "equals", traits: [.button]))
            .expect(.present(.label("12")), timeout: .seconds(1))
    }
}

private enum TogglePickerScreen {
    static let subscribe = HeistDef<Void>("TogglePickerScreen.subscribe") {
        Activate(.label("Subscribe to newsletter"))
            .expect(.present(.label("Last action: Toggle: ON")), timeout: .seconds(2))
    }
}

private enum AlertsScreen {
    static let acceptSimpleAlert = HeistDef<Void>("AlertsScreen.acceptSimpleAlert") {
        Activate(.element(label: "Show Alert", traits: [.button]))
            .expect(.present(.label("Alert Title")), timeout: .seconds(2))

        Activate(.element(label: "OK", traits: [.button]))
            .expect(.absent(.label("Alert Title")), timeout: .seconds(2))

        WaitFor(.present(.label("Last action: Alert: OK")), timeout: .seconds(2))
    }
}

private enum AdjustableControlsScreen {
    static let adjustVolume = HeistDef<Void>("AdjustableControls.adjustVolume") {
        Increment(.label("Volume"))
            .expect(.present(.value("60")), timeout: .seconds(2))

        Decrement(.label("Volume"))
            .expect(.present(.value("50")), timeout: .seconds(2))
    }
}

private enum CustomRotorsScreen {
    static let findFirstError = HeistDef<Void>("CustomRotors.findFirstError") {
        Rotor("Errors", on: .label("Rotor Host"))
            .expect(.present(.label("Rotor Result: Missing amount")), timeout: .seconds(2))
    }
}

private enum TouchCanvasScreen {
    private static let canvas = ElementTarget.element(label: "Touch Canvas", traits: [.allowsDirectInteraction])

    static let exerciseMechanicalGestures = HeistDef<Void>("TouchCanvas.exerciseMechanicalGestures") {
        Mechanical.Tap(canvas)
            .withoutExpectation("Canvas drawing is intentionally spatial, not semantic")

        Mechanical.LongPress(canvas)
            .withoutExpectation("Long press gesture delivery is the behavior under test")

        Mechanical.Swipe(canvas, .left)
            .withoutExpectation("Swipe gesture delivery is the behavior under test")

        Mechanical.Drag(
            from: ScreenPoint(x: 120, y: 360),
            to: ScreenPoint(x: 260, y: 460)
        )
        .withoutExpectation("Drag gesture delivery is the behavior under test")
    }
}

private enum LongListScreen {
    static let exerciseViewportRuntimeCommands = HeistDef<Void>("LongList.exerciseViewportRuntimeCommands") {
        try rawAction(
            .viewportScroll(ScrollTarget(direction: .down)),
            waiver: "Explicit viewport scroll is the runtime feature under test"
        )

        try rawAction(
            .viewportScrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
            expectation: WaitStep(
                predicate: .predicate(.present(.label("Device 99, Optical"))),
                timeout: .seconds(3)
            )
        )

        try rawAction(
            .viewportScrollToVisible(.target(.label("Widget 0, Hardware"))),
            expectation: WaitStep(
                predicate: .predicate(.present(.label("Widget 0, Hardware"))),
                timeout: .seconds(3)
            )
        )
    }
}

@MainActor
final class DogfoodForAllHeistTests: XCTestCase {

    func testFormFlowsUsePublicHeists() async throws {
        let heist = try await Heist {
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")
            try TextInputScreen.fillProfile("Ada Lovelace")
            try DogfoodNavigation.backTo("Controls Demo")
            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
        ])
    }

    func testListAndCalculatorFlowsUsePublicHeists() async throws {
        let heist = try await Heist {
            try DogfoodHome.openScreen("Todo List")
            try TodoScreen.completeItem("Review PR, High priority")

            try DogfoodNavigation.backTo("ButtonHeist Demo")

            try DogfoodHome.openScreen("Calculator")
            try CalculatorScreen.addSevenAndFive()
            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
        ])
    }

    func testControlsAndPresentationFlowsUsePublicHeists() async throws {
        let heist = try await Heist {
            try DogfoodHome.openScreen("Controls Demo")

            ForEach(["Buttons & Actions", "Display"]) { screen in
                try ControlsDemoScreen.openScreen(screen)
                try DogfoodNavigation.backTo("Controls Demo")
            }

            try ControlsDemoScreen.openScreen("Toggles & Pickers")
            try TogglePickerScreen.subscribe()
            try DogfoodNavigation.backTo("Controls Demo")

            try ControlsDemoScreen.openScreen("Alerts & Sheets")
            try AlertsScreen.acceptSimpleAlert()
            try DogfoodNavigation.backTo("Controls Demo")
            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .forEachString,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
        ])
        XCTAssertEqual(heist.result.steps[1].forEachStringEvidence?.iterationCount, 2)
    }

    func testPublicRootInputsAndPrebuiltPlansDriveDemoApp() async throws {
        let stringRoot = try await Heist("Grace Hopper") { name in
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")

            TypeText(name, into: .value("Name"))
                .expect(.present(.value(name)), timeout: .seconds(2))

            DismissKeyboard()
                .withoutExpectation("Keyboard dismissal only prepares navigation")

            try DogfoodNavigation.backTo("Controls Demo")
            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }

        XCTAssertEqual(stringRoot.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .action,
            .action,
            .invoke,
            .invoke,
        ])
        XCTAssertTrue(stringRoot.result.actionMethods.contains(.typeText))
        XCTAssertTrue(stringRoot.result.actionMethods.contains(.resignFirstResponder))

        let targetRoot = try await Heist(.element(label: "Primary Button", traits: [.button])) { target in
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Buttons & Actions")

            Activate(target)
                .expect(.present(.label("Tap count: 1")), timeout: .seconds(2))

            try DogfoodNavigation.backTo("Controls Demo")
            try DogfoodNavigation.backTo("ButtonHeist Demo")
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
            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }
        let prebuiltRun = try await Heist(prebuilt, argument: .none)

        XCTAssertEqual(prebuiltRun.result.steps.map(\.kind), [.invoke, .invoke, .invoke])
        XCTAssertEqual(prebuiltRun.result.steps.first?.reportDisplayName, #"RunHeist("DemoHome.openScreen", "Calculator")"#)
    }

    func testRuntimeControlFlowAndLoopResultsUseDemoAppEvidence() async throws {
        let heist = try await Heist {
            try DogfoodHome.openScreen("Controls Demo")

            If {
                Case(.present(.label("Controls Demo"))) {
                    Warn("conditional matched Controls Demo")
                }
                Else {
                    Fail("conditional missed Controls Demo")
                }
            }

            WaitFor(timeout: .seconds(2)) {
                Case(.present(.label("Controls Demo"))) {
                    Warn("wait case matched Controls Demo")
                }
                Else {
                    Fail("wait case missed Controls Demo")
                }
            }

            ForEach(
                ElementMatches.matching(ElementPredicate(label: "Text Input", traits: [.button])),
                limit: 1
            ) { target in
                WaitFor(.present(target), timeout: .seconds(1))
            }

            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .conditional,
            .waitForCases,
            .forEachElement,
            .invoke,
        ])
        XCTAssertEqual(heist.result.steps[1].caseSelectionEvidence?.selection.selectedCaseIndex, 0)
        XCTAssertEqual(heist.result.steps[2].caseSelectionEvidence?.selection.selectedCaseIndex, 0)
        XCTAssertEqual(heist.result.steps[3].forEachElementEvidence?.matchedCount, 1)
        XCTAssertEqual(heist.result.steps[3].forEachElementEvidence?.iterationCount, 1)
        XCTAssertEqual(heist.result.warnings.map(\.message), [
            "conditional matched Controls Demo",
            "wait case matched Controls Demo",
        ])
    }

    func testAdvancedRuntimeActionsUsePublicHeistsAgainstDemoApp() async throws {
        let heist = try await Heist {
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Adjustable Controls")
            try AdjustableControlsScreen.adjustVolume()
            try DogfoodNavigation.backTo("Controls Demo")
            try DogfoodNavigation.backTo("ButtonHeist Demo")

            try DogfoodHome.openScreen("Custom Rotors")
            try CustomRotorsScreen.findFirstError()
            try DogfoodNavigation.backTo("ButtonHeist Demo")

            try DogfoodHome.openScreen("Touch Canvas")
            try TouchCanvasScreen.exerciseMechanicalGestures()
            try DogfoodNavigation.backTo("ButtonHeist Demo")
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

    func testTextEditingPasteboardAndElementForEachUseDemoApp() async throws {
        let heist = try await Heist {
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")
            try TextInputScreen.pasteName()
            try DogfoodNavigation.backTo("Controls Demo")
            try DogfoodNavigation.backTo("ButtonHeist Demo")

            try DogfoodHome.openScreen("Todo List")
            try TodoScreen.completeItem("Review PR, High priority")

            ForEach(
                ElementMatches.matching(ElementPredicate(
                    label: "Fix bug, High priority",
                    value: "Active"
                )),
                limit: 1
            ) { todo in
                WaitFor(.present(todo), timeout: .seconds(1))
            }

            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .forEachElement,
            .invoke,
        ])
        XCTAssertEqual(heist.result.steps[7].forEachElementEvidence?.matchedCount, 1)
        XCTAssertTrue(heist.result.actionMethods.contains(.setPasteboard))
        XCTAssertTrue(heist.result.actionMethods.contains(.editAction))
        XCTAssertTrue(heist.result.actionMethods.contains(.customAction))
    }

    func testViewportRuntimeCommandsUseDemoApp() async throws {
        let heist = try await Heist {
            try DogfoodHome.openScreen("Long List")
            try LongListScreen.exerciseViewportRuntimeCommands()
            try DogfoodNavigation.backTo("ButtonHeist Demo")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke, .invoke, .invoke])
        XCTAssertTrue(heist.result.actionMethods.contains(.scroll))
        XCTAssertTrue(heist.result.actionMethods.contains(.scrollToEdge))
        XCTAssertTrue(heist.result.actionMethods.contains(.scrollToVisible))
    }

    func testFailedDogfoodHeistPreservesInspectableRunResult() async throws {
        do {
            _ = try await Heist {
                WaitFor(.present(.label("ButtonHeist Demo")), timeout: .seconds(2))
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
            XCTAssertEqual(failure.result.steps.map(\.kind), [.wait, .warn, .fail, .warn])
            XCTAssertEqual(failure.result.steps.map(\.status), [.passed, .passed, .failed, .skipped])
            XCTAssertEqual(failure.result.executedTopLevelStepCount, 3)
            XCTAssertEqual(failure.result.executedNodeCount, 3)
            XCTAssertEqual(failure.result.outputReceiptNodes.map(\.kind), [.wait, .warn, .fail, .warn])
            XCTAssertEqual(
                failure.result.outputReceiptNodes.map(\.path),
                ["$.body[0]", "$.body[1]", "$.body[2]", "$.body[3]"]
            )
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

private func rawAction(
    _ command: HeistActionCommand,
    expectation: WaitStep? = nil,
    waiver: String? = nil
) throws -> HeistStep {
    .action(try ActionStep(
        command: command,
        expectation: expectation,
        expectationWaiver: waiver
    ))
}

private extension HeistExecutionResult {
    var actionMethods: [ActionMethod] {
        steps.flatMap(\.actionMethods)
    }
}

private extension HeistExecutionStepResult {
    var actionMethods: [ActionMethod] {
        (dispatchedActionResult.map { [$0.method] } ?? []) + children.flatMap(\.actionMethods)
    }
}

#endif // canImport(UIKit)
