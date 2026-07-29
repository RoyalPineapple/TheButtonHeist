#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting

@MainActor
final class ProgressButtonHostedBehaviorTests: XCTestCase {

    func testOneTapRecordsOneCompletedRun() async throws {
        _ = try await runHeist("ProgressButton_recordsCompletedRun") {
            try DogfoodHome.openScreen("Progress Button")

            Activate(.label("Ready"))
                .expect(
                    .elementsChanged([
                        .updated(
                            .label("Completed runs"),
                            .value(before: "0", after: "1")
                        ),
                    ]),
                    timeout: 8
                )
        }
    }
}
#endif
