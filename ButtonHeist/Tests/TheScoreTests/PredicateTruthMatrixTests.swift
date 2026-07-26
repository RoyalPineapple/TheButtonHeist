import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

/// The truth table for the predicate algebra: one predicate, one tick
/// sequence, one verdict.
///
/// `ExpectationTests` asks *when* a predicate drains — which tick answers it,
/// what order survives. This asks the flatter question: given a run of ticks,
/// is the predicate satisfied or not. Every row is a closed statement about
/// the algebra, and the table is the point — a shape with no row is a hole you
/// can see.
///
/// # The rules the table encodes
///
/// **Everything is `exists` or `missing`.** A predicate decomposes into one or
/// two element searches against one tree. `appeared(X)` is `missing(X)` then
/// `exists(X)`; `disappeared(X)` is the reverse. Nothing else exists, so
/// nothing else needs a rule.
///
/// **A level is not a transition.** `exists(X)` asks about one tree and holds
/// on the first tree that has X — including the baseline. `appeared(X)`
/// composes two halves and needs a tree without X *before* a tree with it, so
/// an element that was always there never appears (rows 1-4). This is the only
/// reason the halves are ordered: relax it and `appeared` means `disappeared`.
///
/// **The baseline is the first tick.** Nothing precedes it, so a delta cannot
/// measure across it. An element already present at the baseline has no
/// absent-tree behind it and cannot appear (row 7).
///
/// **Ordered inside a step, independent between steps.** Inside one step, a
/// half cannot drain until every half before it is gone — that ordering is what
/// makes a pair mean a change rather than a coincidence. Between steps there is
/// no ordering at all: two assertions written together are two steps, and
/// neither blocks the other.
///
/// **A reading drains at most one half per step.** Every step is offered the
/// same reading and advances if its tip is answered, so one tree can fulfil many
/// predicates — but never two halves of the same one. That is what stops a
/// single tree from being both sides of a change.
///
/// **`noChange` drains nothing.** It is the stillness signal, not evidence: it
/// passes every predicate untouched and only settles the gate. A predicate
/// still outstanding when stillness arrives is still outstanding.
final class PredicateTruthMatrixTests: XCTestCase {

    // MARK: - The table

    /// Rows 1-7 are the invariants rescued from the deleted evidence-kind
    /// truth matrix, re-expressed as tick sequences. The rest close the shapes
    /// that matrix never stated.
    func testTheTruthTable() throws {
        let ready = ["Ready"]
        let empty: [String] = []

        try assert(rows: [
            // # 1-4: a level is not a transition.
            Row(1, "always-present exists is a level",
                predicate: .exists("Ready"), ticks: [ready, ready], holds: true),
            Row(2, "always-present does not appear",
                predicate: .appeared("Ready"), ticks: [ready, ready], holds: false),
            Row(3, "always-absent missing is a level",
                predicate: .missing("Ready"), ticks: [empty, empty], holds: true),
            Row(4, "always-absent does not disappear",
                predicate: .disappeared("Ready"), ticks: [empty, empty], holds: false),

            // # 5: the two halves, in order, over two trees.
            Row(5, "absent then present is an appearance",
                predicate: .appeared("Ready"), ticks: [empty, ready], holds: true),
            Row(6, "present then absent is a disappearance",
                predicate: .disappeared("Ready"), ticks: [ready, empty], holds: true),

            // # 7: the baseline is the first tick, so nothing precedes it.
            Row(7, "appearance before the baseline is excluded",
                predicate: .appeared("Ready"), ticks: [ready], holds: false),

            // # 8-9: an exact matcher is not promoted by a longer label.
            Row(8, "exact match is not satisfied by a combined label",
                predicate: .appeared("Ticket saved."),
                ticks: [empty, ["Ticket saved., Dismiss"]], holds: false),
            Row(9, "exact match is satisfied by the exact label",
                predicate: .appeared("Ticket saved."),
                ticks: [empty, ["Ticket saved."]], holds: true),

            // # 10-11: a transient lives inside the run, and the halves that
            // read it drain when they see it — a later tree cannot un-see it.
            Row(10, "an appearance inside the run drains at the tick that shows it",
                predicate: .appeared("Ready"), ticks: [empty, ready, empty], holds: true),
            Row(11, "a level reads the tick it lands on, not the run",
                predicate: .exists("Ready"), ticks: [empty, empty], holds: false),

            // # 12-13: the halves are ordered, and the order is the meaning.
            Row(12, "a departure is not satisfied by an arrival",
                predicate: .disappeared("Ready"), ticks: [empty, ready], holds: false),
            Row(13, "an arrival is not satisfied by a departure",
                predicate: .appeared("Ready"), ticks: [ready, empty], holds: false),

            // # 14-16: steps are independent of each other.
            Row(14, "two assertions about one frame are both satisfied",
                predicate: .pair(appeared: "Processing", disappeared: "Submit"),
                ticks: [["Submit"], ["Processing"]], holds: true),
            Row(15, "an unsatisfiable sibling does not block the other",
                predicate: .pair(appeared: "Processing", disappeared: "Ghost"),
                ticks: [["Submit"], ["Processing"]], holds: false),
            Row(16, "order between assertions does not matter",
                predicate: .pair(appeared: "Submit", disappeared: "Processing"),
                ticks: [["Processing"], ["Submit"]], holds: true),

            // # 17-18: nothing asked still waits for stillness; a level with
            // no tree to read is not satisfied by stillness alone.
            Row(17, "a level is not answered by stillness",
                predicate: .exists("Ready"), ticks: [], holds: false),
            Row(18, "a satisfied level survives later stillness",
                predicate: .exists("Ready"), ticks: [ready], holds: true),

            // # 19: a level drains on the first tree that answers it, and it
            // stays drained. The element returning on a later tree does not
            // un-answer it, because a drained half is gone from the list.
            Row(19, "a level is answered by any tree, not by the last one",
                predicate: .missing("Header"), ticks: [empty, ["Header"]], holds: true),
        ])
    }

    /// Two ordered sequences meet: the halves of a step, and the readings.
    ///
    /// A reading is offered to the tip of each step — the first half not yet
    /// drained — and a half cannot drain until every half before it is gone.
    /// That single ordering rule is what makes a pair mean a change rather than
    /// a coincidence, and it means what a reading does to a step depends
    /// entirely on how far that step has got.
    ///
    /// A screen boundary needs no rule of its own. A screen change is every
    /// element going away, a moment of nothing, then elements arriving — so the
    /// empty tick is a tree with nothing in it because the screen was empty. The
    /// elements on the new screen are new elements; nothing persisted across the
    /// gap, even where labels repeat. The tip rule then decides each shape:
    ///
    /// - `missing(X)` has its only half at the tip, so the empty moment drains
    ///   it, with X on both screens or neither. X was absent; that is the answer.
    /// - `appeared(X)` leads with `missing(X)`, so the empty moment drains that
    ///   half and the arriving screen drains the `exists`. Elements arriving on a
    ///   new screen did appear.
    /// - `disappeared(X)` leads with `exists(X)`, which the empty moment cannot
    ///   answer. Its `missing` half cannot drain while the `exists` is still
    ///   there, so a boundary alone never satisfies it.
    func testAReadingIsOfferedOnlyToTheTipOfEachStep() throws {
        func acrossABoundary(_ predicate: ResolvedAccessibilityPredicate) -> Bool {
            var expectation = Expectation([predicate])
            expectation.empty(at: Date())
            expectation.screenChange(ScreenFacts(idAfter: "Second"))
            expectation.snapshot(interface(["Header"]))
            expectation.noChange()
            return expectation.isMet
        }

        XCTAssertTrue(
            try acrossABoundary(Shape.missing("Header").resolved()),
            "the gap is a reading without Header"
        )
        XCTAssertTrue(
            try acrossABoundary(Shape.appeared("Header").resolved()),
            "the gap drains the missing half; the new screen drains the exists"
        )
        XCTAssertFalse(
            try acrossABoundary(Shape.disappeared("Header").resolved()),
            "the leading exists half was never drained, so the gap never reached the missing"
        )
    }

    /// One reading fulfils as many steps as it can, but each one atomically:
    /// every step is offered the same reading, and each advances by at most one
    /// half.
    ///
    /// Three steps at different depths meet one tree holding "Ready". The
    /// `exists` drains outright. `appeared` had already drained its `missing`, so
    /// this tree drains its second half and completes it. `disappeared` is at its
    /// `exists` tip, so this tree drains that half and leaves the `missing`
    /// outstanding — one tree cannot carry it further, which is the atomicity.
    func testOneReadingDrainsEveryStepButOnlyOneHalfOfEach() throws {
        var expectation = try Expectation([
            Shape.exists("Ready").resolved(),
            Shape.appeared("Ready").resolved(),
            Shape.disappeared("Ready").resolved(),
        ])
        expectation.snapshot(interface([]))
        expectation.snapshot(interface(["Ready"]))
        expectation.noChange()

        XCTAssertFalse(expectation.isMet, "the disappearance still needs a tree without Ready")
        XCTAssertEqual(
            expectation.outstanding.count, 1,
            "only the disappearance is outstanding: \(expectation.outstanding)"
        )

        expectation.snapshot(interface([]))
        expectation.noChange()
        XCTAssertTrue(expectation.isMet, "outstanding: \(expectation.outstanding)")
    }

    /// The nullary case is not a row: it names no element, so it has no target
    /// to search for and cannot decompose into `exists`/`missing` like every
    /// other predicate. It is answerable anyway, because it asks about the tick
    /// stream rather than about a tree — a `snapshot` tick *is* a change now
    /// that the producer decides change-vs-stillness, so any snapshot answers
    /// it. A quiet tree must not, or a wait on it returns immediately.
    func testANamelessChangeNeedsMovementAndNotMerelyStillness() throws {
        var quiet = try Expectation([nameless()])
        quiet.noChange()
        XCTAssertFalse(quiet.isMet, "stillness alone is not a change")

        var moved = try Expectation([nameless()])
        moved.snapshot(interface(["Ready"]))
        moved.snapshot(interface([]))
        moved.noChange()
        XCTAssertTrue(moved.isMet, "outstanding: \(moved.outstanding)")
    }

    /// One tree is one reading, so it cannot be both sides of a change — even
    /// when two different elements on it answer the two halves separately.
    func testAnUpdateIsNotSatisfiedByOneTree() throws {
        var expectation = try Expectation([
            AccessibilityPredicate.changed(.elements([
                .updated(.label("Count"), .value(before: "1", after: "2")),
            ])).resolve(in: .empty)
        ])
        // Two elements match the target, at the two values the assertion names.
        let tree = makeTestInterface(elements: [
            makeTestHeistElement(description: "Count", label: "Count", value: "1"),
            makeTestHeistElement(description: "Count", label: "Count", value: "2"),
        ])
        expectation.snapshot(tree)
        expectation.noChange()
        XCTAssertFalse(
            expectation.isMet,
            "one tree answered both halves, so nothing changed"
        )
    }

    // MARK: - The runner

    /// Every row is the same fold: feed the trees as snapshot ticks, then the
    /// `noChange` that ends any real run, and read the verdict. Settlement is
    /// part of `isMet`, so the trailing `noChange` is what makes a satisfied
    /// predicate list into a met expectation.
    private func assert(rows: [Row], file: StaticString = #filePath, line: UInt = #line) throws {
        for row in rows {
            var expectation = try Expectation([row.predicate.resolved()])
            for labels in row.ticks {
                expectation.snapshot(interface(labels))
            }
            expectation.noChange()
            XCTAssertEqual(
                expectation.isMet, row.holds,
                "row \(row.number): \(row.name) — outstanding: \(expectation.outstanding)",
                file: file, line: line
            )
        }
    }

    private struct Row {
        let number: Int
        let name: String
        let predicate: Shape
        let ticks: [[String]]
        let holds: Bool

        init(_ number: Int, _ name: String, predicate: Shape, ticks: [[String]], holds: Bool) {
            self.number = number
            self.name = name
            self.predicate = predicate
            self.ticks = ticks
            self.holds = holds
        }
    }

    /// The predicate shapes the algebra admits. `exists`/`missing` are the
    /// single-half ones; the rest compose into two halves or two steps.
    private enum Shape {
        case exists(String)
        case missing(String)
        case appeared(String)
        case disappeared(String)
        case pair(appeared: String, disappeared: String)

        func resolved() throws -> ResolvedAccessibilityPredicate {
            try authored().resolve(in: .empty)
        }

        private func authored() -> AccessibilityPredicate {
            switch self {
            case .exists(let label):
                return .exists(.label(label))
            case .missing(let label):
                return .missing(.label(label))
            case .appeared(let label):
                return .changed(.elements([.appeared(.label(label))]))
            case .disappeared(let label):
                return .changed(.elements([.disappeared(.label(label))]))
            case .pair(let appeared, let disappeared):
                return .changed(.elements([
                    .appeared(.label(appeared)),
                    .disappeared(.label(disappeared)),
                ]))
            }
        }
    }

    // MARK: - Helpers

    private func nameless() throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.changed(.elements([])).resolve(in: .empty)
    }

    private func interface(_ labels: [String]) -> Interface {
        makeTestInterface(
            elements: labels.map { makeTestHeistElement(description: $0, label: $0) }
        )
    }
}
