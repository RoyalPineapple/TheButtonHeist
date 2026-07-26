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
/// **Everything is `exists` or `missing`.** A predicate is one element search
/// against one tree. Nothing else exists, so nothing else needs a rule.
///
/// **A delta predicate is a pair of predicates matched in order on mismatched
/// hashes.** That is the whole definition. `appeared(X)` is `missing(X)` then
/// `exists(X)`; `disappeared(X)` is the reverse; `updated(X, v1, v2)` is
/// `exists(X and v1)` then `exists(X and v2)`. All three conditions carry
/// weight: a pair, so there is no delta type; in order, so relaxing it makes
/// `appeared` mean `disappeared` (rows 12-13); on mismatched hashes, so one
/// tree cannot answer both and be a change (rows 2, 4).
///
/// **The hash is the only thing carried.** A step keeps a list of predicates and
/// one hash — what its last drain landed on. No baseline, no tick counter, no
/// evidence kinds. Its scope follows the question the author asked: a property,
/// an element, or the whole tree.
///
/// **A level is not a transition.** `exists(X)` holds on the first tree that has
/// X, including the baseline, because it is one predicate with nothing before it
/// to order against. An element that was always there never *appears* (rows 1-4).
///
/// **The baseline is the first tick.** Nothing precedes it, so an element already
/// present there has no absent reading behind it and cannot appear (row 7).
///
/// **Independent between steps.** Two assertions written together are two steps,
/// and neither blocks the other. Ordering exists only inside a step.
///
/// **A drain never blocks what is behind it.** The next predicate in the step is
/// still asked; it refuses on a matching hash. So one tree fulfils many steps but
/// never two predicates of the same step — not by a rule against it, but because
/// one tree is one hash.
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

    // MARK: - The decomposition

    /// What each predicate becomes before any tick arrives.
    ///
    /// The truth table above asks whether a run of ticks satisfies a predicate.
    /// This asks the earlier question: what legs is it made of. One leg asks
    /// about a moment, two ask about a change — and the lane is the leg's own
    /// property, so a step never mixes them.
    ///
    /// Every authored form has a row. A form with no row is a decomposition
    /// nobody agreed to.
    func testEveryPredicateDecomposition() throws {
        let pay = AccessibilityTarget.label("Pay")

        let exists = "exists(target(predicate(label=\"Pay\")))"
        let missing = "missing(target(predicate(label=\"Pay\")))"
        let boundary = "the screen to change"
        let elementChange = "the elements to change"

        try assert(decompositions: [
            // A moment: one search against one tree.
            Decomposition("exists", .exists(pay), legs: [exists]),
            Decomposition("missing", .missing(pay), legs: [missing]),

            // A moment in the speech lane.
            Decomposition("announcement", .announcement(AnnouncementPredicate()),
                          legs: ["announcement"]),
            Decomposition("announcement, matched", .announcement(AnnouncementPredicate(match: .exact("Saved"))),
                          legs: ["announcement(\"Saved\")"]),

            // A moment in the boundary lane: naming the destination asks which
            // screen, and only the tick carries the heading.
            Decomposition("screen, named", .screenChanged("Settings"),
                          legs: ["the screen to change to \"Settings\""]),

            // Nothing named in the boundary lane: one leg, because a boundary
            // tick is the evidence for a boundary and nothing constrains where
            // it landed.
            Decomposition("screen, nothing named", .screenChanged,
                          legs: [boundary]),

            // Nothing named in the element lane: two legs any snapshot answers,
            // so only the reading separates them.
            Decomposition("elements, nothing named", .elementsChanged([]),
                          legs: [elementChange, elementChange]),

            // A change with an element named: the pair the assertion composes
            // into, in order. The order is the meaning.
            Decomposition("appeared", .elementsChanged([.appeared(pay)]),
                          legs: [missing, exists]),
            Decomposition("disappeared", .elementsChanged([.disappeared(pay)]),
                          legs: [exists, missing], drainsFirstLegOn: ["Pay"]),

            // `updated` with no property: both legs are the bare anchor, so the
            // reading at the named scope is the only thing that can separate them.
            Decomposition("updated, no property", .elementsChanged([.updated(pay, .value(after: nil))]),
                          legs: [exists, exists], drainsFirstLegOn: ["Pay"]),
        ])
    }

    // MARK: - The latch

    /// Met is a conjunction: every predicate drained, *and* stillness arrived.
    ///
    /// The gate is the second half and it is not optional — a run whose legs are
    /// all satisfied is still not met until a `noChange` tick says the tree
    /// stopped moving. Nothing else can supply it: more snapshots are more
    /// change, which is the opposite of stillness.
    func testMetRequiresEveryLegAndStillnessAsTheFinalTick() throws {
        var expectation = try Expectation([
            Shape.appeared("Ready").resolved(),
            Shape.disappeared("Spinner").resolved(),
        ])

        expectation.snapshot(interface(["Spinner"]))
        XCTAssertFalse(expectation.isMet, "neither pair has finished")

        expectation.snapshot(interface(["Ready"]))
        XCTAssertEqual(legs(of: expectation), [], "both pairs drained")
        XCTAssertFalse(expectation.isMet, "drained legs are not a settled tree")

        expectation.noChange()
        XCTAssertTrue(expectation.isMet, "outstanding: \(expectation.outstanding)")
    }

    /// Stillness does not stand in for a leg. It drains nothing, so an
    /// outstanding predicate is still outstanding after it, and the run is not
    /// met however many times it arrives.
    func testStillnessDoesNotSatisfyAnOutstandingLeg() throws {
        var expectation = try Expectation([Shape.appeared("Ready").resolved()])
        expectation.snapshot(interface([]))
        expectation.noChange()
        expectation.noChange()

        XCTAssertFalse(expectation.isMet)
        XCTAssertEqual(legs(of: expectation), ["exists(target(predicate(label=\"Ready\")))"])
    }

    /// One unsatisfied leg withholds the whole run, however many others drained.
    func testOneOutstandingLegWithholdsTheRun() throws {
        var expectation = try Expectation([
            Shape.exists("Ready").resolved(),
            Shape.appeared("Ghost").resolved(),
        ])
        expectation.snapshot(interface(["Ready"]))
        expectation.noChange()

        XCTAssertFalse(expectation.isMet, "Ghost never appeared")
        XCTAssertEqual(legs(of: expectation).count, 1)
    }

    /// The second leg needs both conditions, and a differing reading alone is
    /// not one of them.
    ///
    /// `appeared("Pay")` drains its `missing` half on the empty tree, then meets a
    /// tree holding something else. That reads differently — so the hash would
    /// allow it — but the `exists("Pay")` search still fails, so the leg stays.
    func testADifferingReadingDoesNotDrainALegThatIsNotSatisfied() throws {
        var expectation = try Expectation([
            AccessibilityPredicate.elementsChanged([.appeared(.label("Pay"))])
                .resolve(in: .empty),
        ])
        expectation.snapshot(interface([]))
        expectation.snapshot(interface(["Cancel"]))
        expectation.noChange()

        XCTAssertFalse(expectation.isMet, "Pay never arrived")
        XCTAssertEqual(expectation.outstanding.count, 1)
    }

    /// An assertion list is one step per assertion, not one step of many legs:
    /// two assertions written side by side were never a claim about order.
    func testAnAssertionListIsOneStepPerAssertion() throws {
        let steps = try AccessibilityPredicate.elementsChanged([
            .appeared(.label("Processing")),
            .disappeared(.label("Submit")),
        ]).resolve(in: .empty).pendingSteps

        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps.map(\.descriptions.count), [2, 2])
    }

    /// What the expectation is still waiting on, without the settlement gate —
    /// which is outstanding until stillness arrives and is not a leg.
    private func legs(of expectation: Expectation) -> [String] {
        expectation.outstanding.filter { $0 != "the tree to stop changing" }
    }

    private struct Decomposition {
        let says: String
        let predicate: AccessibilityPredicate
        let legs: [String]
        /// A tree the first leg accepts. Only two-leg rows need one, and the
        /// default is the empty tree — which `missing` and `anyChange` both take.
        let drainsFirstLegOn: [String]

        init(
            _ says: String,
            _ predicate: AccessibilityPredicate,
            legs: [String],
            drainsFirstLegOn: [String] = []
        ) {
            self.says = says
            self.predicate = predicate
            self.legs = legs
            self.drainsFirstLegOn = drainsFirstLegOn
        }
    }

    private func assert(
        decompositions: [Decomposition],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for row in decompositions {
            let resolved = try row.predicate.resolve(in: .empty)
            let steps = resolved.pendingSteps
            XCTAssertEqual(
                steps.count, 1,
                "\(row.says): one assertion is one step", file: file, line: line
            )
            XCTAssertEqual(
                steps.first?.descriptions, row.legs,
                "\(row.says)", file: file, line: line
            )
            guard row.legs.count == 2 else { continue }
            assertOneTickReachesOnlyTheFirstLeg(resolved, row, file: file, line: line)
        }
    }

    /// A tick enters a step once. It is offered to the first leg that has not
    /// drained, and if that leg takes it the reading is saved at the step's own
    /// scope. The second leg then drains only when a *later* tick both satisfies
    /// it and reads differently — two conditions, and either one alone leaves it
    /// outstanding.
    ///
    /// Every two-leg row is checked the same way, whatever its lane.
    private func assertOneTickReachesOnlyTheFirstLeg(
        _ predicate: ResolvedAccessibilityPredicate,
        _ row: Decomposition,
        file: StaticString,
        line: UInt
    ) {
        var expectation = Expectation([predicate])
        expectation.snapshot(interface(row.drainsFirstLegOn))
        XCTAssertEqual(
            legs(of: expectation), [row.legs[1]],
            "\(row.says): a tick enters a step once, so the second leg is left",
            file: file, line: line
        )

        // The same tree again. Where the second leg is the same search as the
        // first it *is* satisfied here, so only the matching reading can refuse
        // it — which is the whole job of the saved hash.
        expectation.snapshot(interface(row.drainsFirstLegOn))
        XCTAssertFalse(
            expectation.isMet,
            "\(row.says): satisfied is not enough, the reading must also differ",
            file: file, line: line
        )
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
            expectation.screenChanged(ScreenFacts(idAfter: "Second"))
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

    /// A pair needs two ticks *and* two hashes, and one tick supplies neither.
    ///
    /// The two conditions are why the hash is of the whole tree rather than of
    /// what matched. Two predicates of a pair can match *different elements* on
    /// one tree — a tree holding Count at "1" and Count at "2" answers both sides
    /// of `updated(Count, 1 → 2)` — so a hash of the matched element would differ
    /// and let one tree be both sides of a change. Hashing the tree makes every
    /// predicate on one tick see one reading, so the second always refuses.
    ///
    /// Asserted by count rather than by `isMet` so a step that drained twice on
    /// one tick is visible as a step that vanished too early.
    func testAPairCannotDrainTwiceOnOneTick() throws {
        var expectation = try Expectation([Shape.disappeared("Ready").resolved()])
        expectation.snapshot(interface(["Ready"]))
        XCTAssertTrue(
            expectation.outstanding.contains { $0.contains("missing") },
            "one tick drained both predicates: \(expectation.outstanding)"
        )

        // The same tree again is the same reading, so it cannot be the second
        // predicate of the pair however many times it arrives.
        expectation.snapshot(interface(["Ready"]))
        expectation.snapshot(interface(["Ready"]))
        XCTAssertTrue(
            expectation.outstanding.contains { $0.contains("missing") },
            "a repeated reading is one reading: \(expectation.outstanding)"
        )

        expectation.snapshot(interface([]))
        expectation.noChange()
        XCTAssertTrue(expectation.isMet, "outstanding: \(expectation.outstanding)")
    }

    /// Draining one predicate of a pair advances the step; it does not finish it.
    ///
    /// `disappeared(Ready)` offered a tree with Ready drains its `exists`, and the
    /// walk carries on to the `missing`, which is asked and refuses — the tree it
    /// would have to drain on is the one the `exists` just used. So the step is
    /// still outstanding between ticks, one notch further along.
    func testDrainingTheFirstHalfAdvancesTheStepWithoutFinishingIt() throws {
        var expectation = try Expectation([Shape.disappeared("Ready").resolved()])
        XCTAssertTrue(expectation.outstanding.contains { $0.contains("exists") })

        expectation.snapshot(interface(["Ready"]))
        XCTAssertFalse(expectation.isMet, "the missing predicate is still owed")
        XCTAssertFalse(
            expectation.outstanding.contains { $0.contains("exists") },
            "the exists drained: \(expectation.outstanding)"
        )
        XCTAssertTrue(
            expectation.outstanding.contains { $0.contains("missing") },
            "the step survives its first drain: \(expectation.outstanding)"
        )

        // A second tree, so the missing predicate has a reading that is not the
        // one the exists drained on.
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
            AccessibilityPredicate.elementsChanged([
                .updated(.label("Count"), .value(before: "1", after: "2")),
            ]).resolve(in: .empty)
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
                return .elementsChanged([.appeared(.label(label))])
            case .disappeared(let label):
                return .elementsChanged([.disappeared(.label(label))])
            case .pair(let appeared, let disappeared):
                return .elementsChanged([
                    .appeared(.label(appeared)),
                    .disappeared(.label(disappeared)),
                ])
            }
        }
    }

    // MARK: - Helpers

    private func nameless() throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.elementsChanged([]).resolve(in: .empty)
    }

    private func interface(_ labels: [String]) -> Interface {
        makeTestInterface(
            elements: labels.map { makeTestHeistElement(description: $0, label: $0) }
        )
    }
}
