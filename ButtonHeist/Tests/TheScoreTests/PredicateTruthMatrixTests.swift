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
/// is the predicate satisfied or not.
///
/// # The rules the table encodes
///
/// **Everything is `exists` or `missing`.** A predicate is one element search
/// against one tree.
///
/// **A delta predicate is a pair of predicates matched in order on mismatched
/// hashes.** `appeared(X)` is `missing(X)` then
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
/// **The list is a narrative.** This happened, then this happened, then this
/// happened. A tick walks the steps from the front and stops at the first one
/// that refuses, so a step holds every step behind it until it drains. Ordering
/// runs the whole way down: between steps, and between the halves inside one.
///
/// **A drain never blocks what is behind it on the same tick.** Once a step is
/// gone the walk carries on, so one tree drains as many *consecutive* steps as it
/// answers. What it can never do is drain two halves of the same step, because
/// one tree is one hash.
///
/// **`noChange` drains nothing.** It is the stillness signal, not evidence: it
/// passes every predicate untouched and only settles the gate. A predicate
/// still outstanding when stillness arrives is still outstanding.
/// One reading a shape needs, and what it needs to read.
private enum Leg: Equatable {
    case present(String)
    case absent(String)
}

final class PredicateTruthMatrixTests: XCTestCase {

    // MARK: - The table

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

            // # 14-16: consecutive steps drain off one run of trees, and a step
            // that refuses holds the ones behind it.
            Row(14, "two assertions about one frame are both satisfied",
                predicate: .pair(appeared: "Processing", disappeared: "Submit"),
                ticks: [["Submit"], ["Processing"]], holds: true),
            Row(15, "an unsatisfiable step blocks the one behind it",
                predicate: .pair(appeared: "Ghost", disappeared: "Submit"),
                ticks: [["Submit"], ["Processing"]], holds: false),
            Row(16, "the beats are read in the order they were written",
                predicates: [.exists("Submit"), .exists("Processing")],
                ticks: [["Submit"], ["Submit", "Processing"]], holds: true),

            // # 20-22: the list is a narrative, so a beat cannot be told before
            // the one in front of it.
            Row(20, "a later beat is not satisfied by an earlier tree",
                predicates: [.exists("Second"), .exists("First")],
                ticks: [["First"], ["Second"]], holds: false),
            Row(21, "one tree drains every consecutive beat it answers",
                predicates: [.exists("A"), .exists("B"), .exists("C")],
                ticks: [["A", "B", "C"]], holds: true),
            Row(22, "a beat the tree answers still waits behind an unmet one",
                predicates: [.exists("A"), .exists("Never"), .exists("C")],
                ticks: [["A", "C"]], holds: false),

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

    // MARK: - The table, generated

    /// Every narrative of three beats, told to the graphs it asks for.
    ///
    /// The rows above hand a narrative trees someone typed next to it. This
    /// derives them: a narrative is a run of `exists`/`missing` legs, so walking
    /// the legs *is* the sequence of graphs that tells it. Nothing states an
    /// expected verdict — the graphs were built from the narrative, so it holds
    /// by construction, and a run of them that leaves anything outstanding is
    /// the reducer disagreeing with the decomposition it was handed.
    ///
    /// Every ordering of three beats over two elements, which is where the
    /// interesting ones live: two beats about the same element must interleave
    /// with a third about another, and a graph carries both at once.
    func testEveryNarrativeIsSatisfiedByTheGraphsItAsksFor() throws {
        let beats: [Shape] = [
            .appeared("Ready"), .disappeared("Ready"),
            .appeared("Spinner"), .disappeared("Spinner"),
            .exists("Ready"), .missing("Spinner"),
        ]

        for narrative in orderedTriples(of: beats) {
            let told = try Expectation(narrative.map { try $0.resolved() })
                .folding(graphs(telling: narrative).map { .elementsChanged(interface($0)) })

            XCTAssertTrue(
                told.isMet,
                "\(name(of: narrative)) against \(graphs(telling: narrative))"
                    + " — outstanding: \(told.outstanding)"
            )
        }
    }

    /// The same narratives, each told with one graph taken out of the middle.
    ///
    /// The run above is satisfiable by construction, which proves nothing on its
    /// own — a reducer that drained everything offered would also pass it. So
    /// each narrative is told again with one of its graphs withheld, every
    /// position tried in turn, and the story has to come up short.
    ///
    /// No narrative is told by nothing, or by graphs that never move.
    ///
    /// The run above is satisfiable by construction, which proves nothing on its
    /// own — a reducer that drained everything offered would also pass it. This
    /// is the floor that rules that out: a change needs two readings, so a run
    /// that supplies one reading, or none, can never tell a story that contains
    /// one.
    ///
    /// Narratives of pure levels are excluded, since one graph can genuinely
    /// answer every level in them, which rows 21 and 22 already state.
    func testNoNarrativeContainingAChangeIsToldByOneReading() throws {
        let beats: [Shape] = [
            .appeared("Ready"), .disappeared("Ready"),
            .appeared("Spinner"), .disappeared("Spinner"),
            .exists("Ready"), .missing("Spinner"),
        ]

        for narrative in orderedTriples(of: beats) {
            guard let whole = graphs(telling: narrative).last else { continue }
            guard narrative.contains(where: { $0.legs.count > 1 }) else { continue }

            for run in [[], [whole], [whole, whole]] {
                let told = try Expectation(narrative.map { try $0.resolved() })
                    .folding(run.map { .elementsChanged(interface($0)) })

                XCTAssertFalse(
                    told.isMet,
                    "\(name(of: narrative)) was told by \(run), which never moves"
                )
            }
        }
    }

    /// The graphs a narrative asks for, in the order it asks for them.
    ///
    /// One leg is one reading, so a leg asks for the graph before it with that
    /// leg's element added or taken away. Everything the leg does not name
    /// carries over untouched.
    ///
    /// Consecutive duplicates collapse. A leg that asks for the graph it was
    /// already given is answered by that graph — `appeared(X)` followed by
    /// `disappeared(X)` wants X present twice over, and one graph holding X
    /// serves both. Emitting it twice would produce a graph nothing depends on,
    /// which is what makes every graph here load-bearing.
    private func graphs(telling narrative: [Shape]) -> [[String]] {
        var showing: Set<String> = []
        var asked: [[String]] = []
        for leg in narrative.flatMap(\.legs) {
            switch leg {
            case .present(let label): showing.insert(label)
            case .absent(let label): showing.remove(label)
            }
            guard asked.last != showing.sorted() else { continue }
            asked.append(showing.sorted())
        }
        return asked
    }

    /// Every ordered choice of three from a list, no beat used twice.
    private func orderedTriples(of beats: [Shape]) -> [[Shape]] {
        beats.indices.flatMap { first in
            beats.indices.filter { $0 != first }.flatMap { second in
                beats.indices.filter { $0 != first && $0 != second }.map { third in
                    [beats[first], beats[second], beats[third]]
                }
            }
        }
    }

    private func name(of narrative: [Shape]) -> String {
        narrative.map(\.name).joined(separator: " then ")
    }

    /// Every ordering of the three lanes against one run that carries all three.
    ///
    /// Lanes are independent narratives sharing one log, so a tick only ever
    /// meets the head of its own lane. Whatever order the three are authored in,
    /// a run holding all three answers them all.
    func testLanesDrainWhateverOrderTheyWereAuthoredIn() throws {
        let element = try Shape.exists("Ready").resolved()
        let screen = try AccessibilityPredicate.screenChanged("Settings").resolve(in: .empty)
        let spoken = try AccessibilityPredicate
            .announcement(AnnouncementPredicate(match: .exact("Saved")))
            .resolve(in: .empty)

        for authoring in permutations(of: [element, screen, spoken]) {
            let told = Expectation(authoring).folding([
                .elementsChanged(interface(["Ready"])),
                .screenChanged(ScreenFacts(idAfter: "Settings")),
                .announcement("Saved"),
                .noChange,
            ])

            XCTAssertTrue(told.isMet, "outstanding: \(told.outstanding)")
        }
    }

    /// Every ordering of a list.
    private func permutations<Element>(of elements: [Element]) -> [[Element]] {
        guard elements.count > 1 else { return [elements] }
        return elements.indices.flatMap { index -> [[Element]] in
            var rest = elements
            let held = rest.remove(at: index)
            return permutations(of: rest).map { [held] + $0 }
        }
    }

    // MARK: - The decomposition

    /// What each predicate becomes before any tick arrives.
    ///
    /// The truth table above asks whether a run of ticks satisfies a predicate.
    /// This asks the earlier question: what legs is it made of. One leg asks
    /// about a moment, two ask about a change — and the lane is the leg's own
    /// property, so a step never mixes them.
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
            // into, in order.
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

    // MARK: - Met is every leg

    /// Met is every authored leg drained. A pair drains in order, so both halves
    /// of both pairs have to land before the whole is answered.
    func testMetRequiresEveryLeg() throws {
        var expectation = try Expectation([
            Shape.appeared("Ready").resolved(),
            Shape.disappeared("Spinner").resolved(),
        ])

        expectation = expectation.folding([.elementsChanged(interface(["Spinner"]))])
        XCTAssertFalse(expectation.isMet, "neither pair has finished")

        expectation = expectation.folding([.elementsChanged(interface(["Ready"]))])
        XCTAssertEqual(legs(of: expectation), [], "both pairs drained")
        XCTAssertTrue(expectation.isMet, "outstanding: \(expectation.outstanding)")
    }

    /// Stillness does not stand in for a leg. It drains nothing, so an
    /// outstanding predicate is still outstanding after it, and the run is not
    /// met however many times it arrives.
    func testStillnessDoesNotSatisfyAnOutstandingLeg() throws {
        var expectation = try Expectation([Shape.appeared("Ready").resolved()])
        expectation = expectation.folding([.elementsChanged(interface([])), .noChange, .noChange])

        XCTAssertFalse(expectation.isMet)
        XCTAssertEqual(legs(of: expectation), ["exists(target(predicate(label=\"Ready\")))"])
    }

    /// One unsatisfied leg withholds the whole run, however many others drained.
    func testOneOutstandingLegWithholdsTheRun() throws {
        var expectation = try Expectation([
            Shape.exists("Ready").resolved(),
            Shape.appeared("Ghost").resolved(),
        ])
        expectation = expectation.folding([.elementsChanged(interface(["Ready"])), .noChange])

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
        expectation = expectation.folding([
            .elementsChanged(interface([])),
            .elementsChanged(interface(["Cancel"])),
            .noChange,
        ])

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
        XCTAssertEqual(steps.map(\.pending.count), [2, 2])
    }

    /// What the expectation is still waiting on, without the settlement gate —
    /// which is outstanding until stillness arrives and is not a leg.
    private func legs(of expectation: Expectation) -> [String] {
        expectation.outstanding.filter { $0.tick != .noChange }.map(\.description)
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
                steps.first?.pending.map(\.description), row.legs,
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
    private func assertOneTickReachesOnlyTheFirstLeg(
        _ predicate: ResolvedAccessibilityPredicate,
        _ row: Decomposition,
        file: StaticString,
        line: UInt
    ) {
        var expectation = Expectation([predicate])
        expectation = expectation.folding([.elementsChanged(interface(row.drainsFirstLegOn))])
        XCTAssertEqual(
            legs(of: expectation), [row.legs[1]],
            "\(row.says): a tick enters a step once, so the second leg is left",
            file: file, line: line
        )

        // The same tree again. Where the second leg is the same search as the
        // first it *is* satisfied here, so only the matching reading can refuse
        // it — which is the whole job of the saved hash.
        expectation = expectation.folding([.elementsChanged(interface(row.drainsFirstLegOn))])
        XCTAssertFalse(
            expectation.isMet,
            "\(row.says): satisfied is not enough, the reading must also differ",
            file: file, line: line
        )
    }

    /// Two ordered sequences meet: the halves of a step, and the readings.
    ///
    /// A reading is offered to the tip of each step — the first half not yet
    /// drained — and a half cannot drain until every half before it is gone. So
    /// what a reading does to a step depends on how far that step has got.
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
            expectation = expectation.folding([
                .elementsChanged(.empty(at: Date())),
                .screenChanged(ScreenFacts(idAfter: "Second")),
                .elementsChanged(interface(["Header"])),
                .noChange,
            ])
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

    /// One reading drains as many consecutive steps as it can, but each one
    /// atomically: a step advances by at most one half per tick, and the half it
    /// advances holds the steps behind it until it is spent.
    ///
    /// The narrative is Ready is here, then it goes, then it returns. The tree
    /// holding "Ready" drains the leading `exists` and then the `exists` half of
    /// the `disappeared` behind it — two consecutive halves off one reading. It
    /// cannot also drain that step's `missing`, because a change needs two
    /// readings, and it never reaches the trailing `appeared` at all.
    func testOneReadingDrainsEveryStepButOnlyOneHalfOfEach() throws {
        var expectation = try Expectation([
            Shape.exists("Ready").resolved(),
            Shape.disappeared("Ready").resolved(),
            Shape.appeared("Ready").resolved(),
        ])
        expectation = expectation.folding([
            .elementsChanged(interface(["Ready"])),
            .noChange,
        ])

        XCTAssertFalse(expectation.isMet, "the departure still needs a tree without Ready")
        XCTAssertEqual(
            expectation.outstanding.count, 3,
            "the missing half, then the return's two halves: \(expectation.outstanding)"
        )

        expectation = expectation.folding([.elementsChanged(interface([])), .noChange])
        XCTAssertEqual(
            expectation.outstanding.count, 1,
            "that tree spent the departure and the return's missing: \(expectation.outstanding)"
        )

        expectation = expectation.folding([.elementsChanged(interface(["Ready"])), .noChange])
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
        let missingReady = try Shape.missing("Ready").resolved()

        var expectation = try Expectation([Shape.disappeared("Ready").resolved()])
        expectation = expectation.folding([.elementsChanged(interface(["Ready"]))])
        XCTAssertEqual(
            owed(expectation), [missingReady],
            "one tick drained both predicates"
        )

        // The same tree again is the same reading, so it cannot be the second
        // predicate of the pair however many times it arrives.
        expectation = expectation.folding([
            .elementsChanged(interface(["Ready"])),
            .elementsChanged(interface(["Ready"])),
        ])
        XCTAssertEqual(
            owed(expectation), [missingReady],
            "a repeated reading is one reading"
        )

        expectation = expectation.folding([.elementsChanged(interface([])), .noChange])
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
        XCTAssertEqual(
            owed(expectation),
            [try Shape.exists("Ready").resolved(), try Shape.missing("Ready").resolved()],
            "both legs are owed before any tick"
        )

        expectation = expectation.folding([.elementsChanged(interface(["Ready"]))])
        XCTAssertFalse(expectation.isMet, "the missing predicate is still owed")
        XCTAssertEqual(
            owed(expectation), [try Shape.missing("Ready").resolved()],
            "the exists drained and the step survives it"
        )

        // A second tree, so the missing predicate has a reading that is not the
        // one the exists drained on.
        expectation = expectation.folding([.elementsChanged(interface([])), .noChange])
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
        quiet = quiet.folding([.noChange])
        XCTAssertFalse(quiet.isMet, "stillness alone is not a change")

        var moved = try Expectation([nameless()])
        moved = moved.folding([.elementsChanged(interface(["Ready"]))])
        moved = moved.folding([.elementsChanged(interface([]))])
        moved = moved.folding([.noChange])
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
        let tree = makeTestCapture(elements: [
            makeTestHeistElement(description: "Count", label: "Count", value: "1"),
            makeTestHeistElement(description: "Count", label: "Count", value: "2"),
        ])
        expectation = expectation.folding([.elementsChanged(tree), .noChange])
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
            var expectation = try Expectation(row.predicates.map { try $0.resolved() })
            for labels in row.ticks {
                expectation = expectation.folding([.elementsChanged(interface(labels))])
            }
            expectation = expectation.folding([.noChange])
            XCTAssertEqual(
                expectation.isMet, row.holds,
                "row \(row.number): \(row.name) — outstanding: \(expectation.outstanding)",
                file: file, line: line
            )
        }
    }

    /// One row: the predicates as authored, the trees they meet in order, and
    /// whether the whole narrative was told.
    private struct Row {
        let number: Int
        let name: String
        let predicates: [Shape]
        let ticks: [[String]]
        let holds: Bool

        init(_ number: Int, _ name: String, predicate: Shape, ticks: [[String]], holds: Bool) {
            self.init(number, name, predicates: [predicate], ticks: ticks, holds: holds)
        }

        init(_ number: Int, _ name: String, predicates: [Shape], ticks: [[String]], holds: Bool) {
            self.number = number
            self.name = name
            self.predicates = predicates
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

        /// One `elementsChanged` carrying an authored assertion list, which is
        /// how a row states several beats inside one predicate.
        case assertions([Shape])

        func resolved() throws -> ResolvedAccessibilityPredicate {
            try authored().resolve(in: .empty)
        }

        private func authored() -> AccessibilityPredicate {
            switch self {
            case .exists(let label):
                return .exists(.label(label))
            case .missing(let label):
                return .missing(.label(label))
            case .appeared, .disappeared, .pair, .assertions:
                return .elementsChanged(assertions)
            }
        }

        /// The readings this shape decomposes into, in order.
        ///
        /// The same decomposition the runtime makes, stated in terms of what a
        /// graph would have to hold rather than of resolved predicates, so a
        /// narrative can be turned back into the graphs that tell it.
        var legs: [Leg] {
            switch self {
            case .exists(let label): return [.present(label)]
            case .missing(let label): return [.absent(label)]
            case .appeared(let label): return [.absent(label), .present(label)]
            case .disappeared(let label): return [.present(label), .absent(label)]
            case .pair(let appeared, let disappeared):
                return Shape.appeared(appeared).legs + Shape.disappeared(disappeared).legs
            case .assertions(let shapes): return shapes.flatMap(\.legs)
            }
        }

        var name: String {
            switch self {
            case .exists(let label): return "exists(\(label))"
            case .missing(let label): return "missing(\(label))"
            case .appeared(let label): return "appeared(\(label))"
            case .disappeared(let label): return "disappeared(\(label))"
            case .pair(let appeared, let disappeared):
                return "appeared(\(appeared)) + disappeared(\(disappeared))"
            case .assertions(let shapes):
                return shapes.map(\.name).joined(separator: " + ")
            }
        }

        /// This shape as the assertions it contributes to an enclosing list.
        private var assertions: [ElementAssertion] {
            switch self {
            case .exists(let label):
                return [.exists(.label(label))]
            case .missing(let label):
                return [.missing(.label(label))]
            case .appeared(let label):
                return [.appeared(.label(label))]
            case .disappeared(let label):
                return [.disappeared(.label(label))]
            case .pair(let appeared, let disappeared):
                return [.appeared(.label(appeared)), .disappeared(.label(disappeared))]
            case .assertions(let shapes):
                return shapes.flatMap(\.assertions)
            }
        }
    }

    // MARK: - Helpers

    /// The resolved questions still owed, ignoring the stillness gate.
    ///
    /// Compared as values against what `Shape` resolves to, so a row states
    /// *which* search is outstanding rather than testing a rendered word.
    private func owed(_ expectation: Expectation) -> [ResolvedAccessibilityPredicate] {
        expectation.outstanding.filter { $0.tick != .noChange }.compactMap(\.query)
    }

    private func nameless() throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.elementsChanged([]).resolve(in: .empty)
    }

    private func interface(_ labels: [String]) -> AccessibilityTrace.Capture {
        makeTestCapture(
            elements: labels.map { makeTestHeistElement(description: $0, label: $0) }
        )
    }
}
