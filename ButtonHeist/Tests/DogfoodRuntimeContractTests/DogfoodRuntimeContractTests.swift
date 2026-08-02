#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans

@MainActor
final class DogfoodRuntimeContractTests: XCTestCase {

    func testBackActivationCompletesWithoutDoubleDispatch() async throws {
        let heist = try await runHeist("DogfoodRefusedBackActivation") {
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")
            try DemoNavigation.backTo("Controls Demo")
        }
        let backAction = try XCTUnwrap(
            heist.result.outputNodes
                .compactMap { $0.actionEvidence?.result }
                .last {
                    $0.subjectEvidence?.element.semantics.assertable.label == "Controls Demo"
                }
        )
        let trace = try XCTUnwrap(backAction.activationTrace)

        let axActivateReturned = try XCTUnwrap(trace.axActivateReturned)
        XCTAssertFalse(axActivateReturned && trace.tapActivationDispatched)
        if trace.tapActivationDispatched {
            XCTAssertFalse(axActivateReturned)
            XCTAssertEqual(trace.tapActivationSucceeded, true)
        }
    }

    func testPublicRootArgumentAndPrebuiltPlanDriveDemoApp() async throws {
        try await runHeist("DogfoodFillProfileName", argument: "Grace Hopper") { name in
            try DogfoodHome.openScreen("Controls Demo")
            try ControlsDemoScreen.openScreen("Text Input")
            try TextInputScreen.fillProfile(name)

            try DemoNavigation.backTo("Controls Demo")
            try DemoNavigation.backToRoot()
        }

        let prebuilt = try HeistPlan("DogfoodPrebuiltCalculator") {
            try DogfoodHome.openScreen("Calculator")
            try CalculatorScreen.addSevenAndFive()
            try DemoNavigation.backToRoot()
        }

        try await runHeist(prebuilt)
    }

    func testAdvancedActionCrossesPublicControlFlowBoundary() async throws {
        try await runHeist("DogfoodAdvancedActionControlFlow") {
            try DogfoodHome.openScreen("Custom Rotors")
            // The navigation title settles before SwiftUI lazily mounts this visible UIKit row.
            WaitFor(.exists(.label("Rotor Host")), timeout: 2)

            If {
                Case(.exists(.label("Rotor Host"))) {
                    Rotor("Errors", on: .label("Rotor Host"))
                        .expect(.exists(.label("Rotor Result: Missing amount")), timeout: 2)
                }
                Else {
                    Fail("Custom Rotors did not expose its semantic rotor host")
                }
            }
            try DemoNavigation.backToRoot()
        }
    }
}

#endif // canImport(UIKit)
