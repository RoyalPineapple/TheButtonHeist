#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting

/// One tap, every element fact, in order.
///
/// Each delta is a pair of presence predicates drained in order, so every
/// assertion here reads the tick the one before it left off at:
///
///   disappeared "Ready"                 Ready present, then gone
///   appeared    "Loading"               Loading missing, then present
///   appeared    "Loading" at 100%       and again at 100%
///   disappeared "Loading"               ...
///   appeared    "Ready"                 ...
///
/// The 100% state is an `appeared` rather than an `updated` because `updated`
/// needs its anchor to hold across both legs, and the leg before this one had
/// already drained on a Loading with no value yet.
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
                    .elementsChanged([
                        .disappeared(.label("Ready")),
                        .appeared(.label("Loading")),
                        .appeared(.label("Loading").and(.value(.exact("100%")))),
                        .disappeared(.label("Loading")),
                        .appeared(.label("Ready")),
                    ]),
                    timeout: 8
                )
        }
    }
}
#endif
