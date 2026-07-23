#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import ThePlans

@MainActor
final class DogfoodRuntimeContractTests: XCTestCase {

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
