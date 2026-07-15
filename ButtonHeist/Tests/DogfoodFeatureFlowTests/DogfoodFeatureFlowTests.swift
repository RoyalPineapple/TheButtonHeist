#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting

@MainActor
final class DogfoodFeatureFlowTests: XCTestCase {

    func testPublicHeistCanMutateAndVerifyDemoAppState() async throws {
        try await runHeist("DogfoodSemanticFeatureCanary") {
            try DogfoodHome.openScreen("Todo List")
            try TodoScreen.completeItem("Buy groceries, High priority")
            try DemoNavigation.backToRoot()
        }
    }
}
#endif // canImport(UIKit)
