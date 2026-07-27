import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

/// A pair is proved by two legs in order and a reading that differs, and the
/// reading is taken at the innermost scope the assertion specified.
///
/// The scope earns its keep where the two legs are the *same* search and ordering
/// alone cannot separate them: `updated(X)` with no property is `exists(X)` twice,
/// and `changed(.elements())` is a leg any tree answers, twice. For those, the
/// reading is the only thing that can say the tree moved — and it must move at the
/// scope that was asked about, not anywhere on screen.
final class ReadingScopeTests: XCTestCase {

    private func resolved(_ predicate: AccessibilityPredicate) throws -> ResolvedAccessibilityPredicate {
        try predicate.resolve(in: .empty)
    }

    private func tree(_ labels: [String]) -> AccessibilityTrace.Capture {
        makeTestCapture(elements: labels.map { makeTestHeistElement(description: $0, label: $0) })
    }

    private func counter(_ value: String?) -> AccessibilityTrace.Capture {
        makeTestCapture(elements: [
            makeTestHeistElement(description: "Count", label: "Count", value: value),
        ])
    }

    // MARK: - Nothing named at all

    func testOneSnapshotAloneDoesNotProveANamelessChange() throws {
        var expectation = try Expectation([resolved(.elementsChanged([]))])
        expectation.snapshot(tree(["Ready"]))
        expectation.noChange()
        XCTAssertFalse(expectation.isMet, "one tick is one reading: nothing was shown to change")
    }

    func testTheSameTreeTwiceDoesNotProveANamelessChange() throws {
        var expectation = try Expectation([resolved(.elementsChanged([]))])
        expectation.snapshot(tree(["Ready"]))
        expectation.snapshot(tree(["Ready"]))
        expectation.noChange()
        XCTAssertFalse(expectation.isMet, "the same tree twice is one reading")
    }

    // MARK: - A boundary, with nothing named about it

    /// A boundary is proved by a boundary tick, because that is the evidence for
    /// a boundary. Snapshots answer element questions, whichever screen they
    /// were taken on.
    func testABoundaryWithNothingNamedIsProvedByTheBoundaryTick() throws {
        var expectation = try Expectation([resolved(.screenChanged)])
        expectation.screenChanged(ScreenFacts(idAfter: "Settings"))
        expectation.noChange()
        XCTAssertTrue(expectation.isMet, "outstanding: \(expectation.outstanding)")
    }

    func testSnapshotsAloneNeverProveABoundary() throws {
        var expectation = try Expectation([resolved(.screenChanged)])
        expectation.snapshot(tree(["Home"]))
        expectation.snapshot(tree(["Settings"]))
        expectation.noChange()
        XCTAssertFalse(
            expectation.isMet,
            "two trees differing is the elements changing, not a screen boundary"
        )
    }

    /// A named destination reads the boundary tick, because the heading is the
    /// one fact a tree does not carry.
    func testANamedDestinationReadsTheBoundaryTickAndNotSnapshots() throws {
        var snapshots = try Expectation([resolved(.screenChanged("Settings"))])
        snapshots.snapshot(tree(["Home"]))
        snapshots.snapshot(tree(["Settings"]))
        snapshots.noChange()
        XCTAssertFalse(snapshots.isMet, "snapshots cannot name the screen they arrived at")

        var named = try Expectation([resolved(.screenChanged("Settings"))])
        named.screenChanged(ScreenFacts(idAfter: "Settings"))
        named.noChange()
        XCTAssertTrue(named.isMet, "outstanding: \(named.outstanding)")
    }

    // MARK: - An element named, no property constrained

    func testAnUnconstrainedUpdateIsNotSatisfiedByTheElementMerelyPersisting() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .updated(.label("Count"), .value(after: nil)),
        ])
        var expectation = try Expectation([resolved(predicate)])
        expectation.snapshot(counter("1"))
        expectation.snapshot(counter("1"))
        expectation.noChange()
        XCTAssertFalse(
            expectation.isMet,
            "both legs are exists(Count), so only the reading can say it updated"
        )
    }

    func testAnUnconstrainedUpdateHoldsWhenTheNamedPropertyMoved() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .updated(.label("Count"), .value(after: nil)),
        ])
        var expectation = try Expectation([resolved(predicate)])
        expectation.snapshot(counter("1"))
        expectation.snapshot(counter("2"))
        expectation.noChange()
        XCTAssertTrue(expectation.isMet, "outstanding: \(expectation.outstanding)")
    }

    /// The scope is the property named, so churn elsewhere is not the change the
    /// assertion asked about.
    func testAnUpdateIgnoresChurnOutsideTheNamedProperty() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .updated(.label("Count"), .value(after: nil)),
        ])
        var expectation = try Expectation([resolved(predicate)])
        expectation.snapshot(counter("1"))
        expectation.snapshot(makeTestCapture(elements: [
            makeTestHeistElement(description: "Count", label: "Count", value: "1"),
            makeTestHeistElement(description: "Total", label: "Total"),
        ]))
        expectation.noChange()
        XCTAssertFalse(
            expectation.isMet,
            "a new element elsewhere did not change Count's value"
        )
    }
}
