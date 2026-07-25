#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting

/// One tap, every element fact, in order.
///
/// Deltas measure from a fixed baseline — the graph as it was when the tap
/// fired — and that baseline moves only on a screen change or a new action. So
/// every assertion here is about what the tap graph did or did not contain:
///
///   disappeared "Ready"                 Ready was in the baseline, and left
///   appeared    "Loading"               no Loading in the baseline
///   appeared    "Loading" at 100%       nor a Loading at 100%
///   disappeared "Loading"               ...
///   appeared    "Ready"                 ...
///
/// The 100% state is an `appeared` rather than an `updated` for that reason:
/// `updated` needs its anchor to hold in the baseline, and at tap time this
/// button read "Ready". Nothing named "Loading" was there to be updated.
///
/// The final `appeared("Ready")` is why this test exists. "Ready" was on screen
/// before the tap, so any model that asks "was this ever true" passes it for the
/// wrong reason. Only an ordered drain can say this Ready is a second arrival:
/// the first one is consumed by the leading `disappeared`, and the list has
/// moved past it by the time the last predicate is asked.
@MainActor
final class ProgressButtonOrderedExpectationTests: XCTestCase {

    func testOneTapDrainsEveryElementFactInAuthoredOrder() async throws {
        _ = try await runHeist("ProgressButton_readyToLoadingToReady") {
            try DogfoodHome.openScreen("Progress Button")

            Activate(.label("Ready"))
                .expect(
                    .changed(.elements([
                        .disappeared(.label("Ready")),
                        .appeared(.label("Loading")),
                        .appeared(.label("Loading").and(.value(.exact("100%")))),
                        .disappeared(.label("Loading")),
                        .appeared(.label("Ready")),
                    ])),
                    timeout: 8
                )
        }
    }
}
#endif
