#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class DogfoodFeatureFlowTests: XCTestCase {

    func testFormFlowsUsePublicHeists() async throws {
        let heist = try await runHeist("DogfoodFormFlows") {
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")
            try TextInputScreen.fillProfile("Ada Lovelace")
            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()
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
        let heist = try await runHeist("DogfoodListAndCalculatorFlows") {
            try DogfoodHome.openScreen("Todo List")
            try TodoScreen.completeItem("Buy groceries, High priority")

            try DemoNavigation.backToRoot()

            try DogfoodHome.openScreen("Calculator")
            try CalculatorScreen.addSevenAndFive()
            try DemoNavigation.backToRoot()
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
        let heist = try await runHeist("DogfoodControlsAndPresentationFlows") {
            try DogfoodHome.openScreen("Controls Demo")

            ForEach("Buttons & Actions", "Display") { screen in
                try ControlsDemoScreen.openScreen(screen)
                try DemoNavigation.backTo("Controls Demo")
            }

            try ControlsDemoScreen.openScreen("Toggles & Pickers")
            try TogglePickerScreen.subscribe()
            try DemoNavigation.backTo("Controls Demo")

            try ControlsDemoScreen.openScreen("Alerts & Sheets")
            try AlertsScreen.acceptSimpleAlert()
            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()
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

    func testAdjustableControlsRepeatUntilDrivesVolumeToMaximum() async throws {
        let heist = try await runHeist("DogfoodAdjustableControlsRepeatUntil") {
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Adjustable Controls")
            try AdjustableControlsScreen.driveVolumeToMaximum()
            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [
            .invoke,
            .invoke,
            .invoke,
            .invoke,
            .invoke,
        ])
        XCTAssertEqual(heist.result.repeatUntilSteps.count, 1)
        XCTAssertEqual(heist.result.repeatUntilSteps.first?.repeatUntilEvidence?.iterationCount, 5)
        XCTAssertEqual(heist.result.repeatUntilSteps.first?.repeatUntilEvidence?.expectation.met, true)
        XCTAssertTrue(heist.result.actionMethods.contains(.increment))
    }

    func testTextEditingPasteboardAndElementForEachUseDemoApp() async throws {
        let heist = try await runHeist("DogfoodTextEditingPasteboardAndElementForEach") {
            let activeFixBug = ElementPredicate(
                label: "Fix bug, High priority",
                value: "Active"
            )

            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")
            try TextInputScreen.pasteName()
            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()

            try DogfoodHome.openScreen("Todo List")
            try TodoScreen.completeItem("Buy groceries, High priority")

            ForEach(activeFixBug, limit: 1) { target in
                WaitFor(.exists(target), timeout: .seconds(1))
            }

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
            .forEachElement,
            .invoke,
        ])
        XCTAssertEqual(heist.result.steps[7].forEachElementEvidence?.matchedCount, 1)
        XCTAssertTrue(heist.result.actionMethods.contains(.setPasteboard))
        XCTAssertTrue(heist.result.actionMethods.contains(.editAction))
        XCTAssertTrue(heist.result.actionMethods.contains(.customAction))
    }
}
#endif // canImport(UIKit)
