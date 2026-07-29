import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

/// Observable truth table for deterministic expectation evaluation.
final class PredicateTruthMatrixTests: XCTestCase {
    func testPresenceAndTransitionTruthTable() throws {
        let rows: [Row] = [
            Row(
                "exists is satisfied by any matching tick",
                predicates: [.exists("Ready")],
                labels: [[], ["Ready"], []],
                holds: true
            ),
            Row(
                "exists remains outstanding without a match",
                predicates: [.exists("Ready")],
                labels: [[], ["Other"]],
                holds: false
            ),
            Row(
                "missing is satisfied by any missing tick",
                predicates: [.missing("Ready")],
                labels: [["Ready"], []],
                holds: true
            ),
            Row(
                "always present does not appear",
                predicates: [.appeared("Ready")],
                labels: [["Ready"], ["Ready"]],
                holds: false
            ),
            Row(
                "missing then exists is an appearance",
                predicates: [.appeared("Ready")],
                labels: [[], ["Ready"]],
                holds: true
            ),
            Row(
                "exists then missing is not an appearance",
                predicates: [.appeared("Ready")],
                labels: [["Ready"], []],
                holds: false
            ),
            Row(
                "exists then missing is a disappearance",
                predicates: [.disappeared("Ready")],
                labels: [["Ready"], []],
                holds: true
            ),
            Row(
                "missing then exists is not a disappearance",
                predicates: [.disappeared("Ready")],
                labels: [[], ["Ready"]],
                holds: false
            ),
            Row(
                "a transient appearance remains satisfied",
                predicates: [.appeared("Ready")],
                labels: [[], ["Ready"], []],
                holds: true
            ),
            Row(
                "exact label matching does not accept combined text",
                predicates: [.appeared("Ticket saved.")],
                labels: [[], ["Ticket saved., Dismiss"]],
                holds: false
            ),
            Row(
                "exact label matching accepts exact text",
                predicates: [.appeared("Ticket saved.")],
                labels: [[], ["Ticket saved."]],
                holds: true
            ),
        ]

        for row in rows {
            let replay = try Expectation(
                row.predicates.map { try $0.resolved() }
            ).evaluating(row.labels.map {
                .elementsChanged(Self.snapshot($0))
            })

            XCTAssertEqual(
                replay.isSatisfied,
                row.holds,
                row.name
            )
            XCTAssertEqual(
                replay.outstandingDescription == nil,
                row.holds,
                row.name
            )
        }
    }

    func testAuthoredPredicateOrderIsTemporalOrder() throws {
        let firstThenSecond = Expectation([
            try Shape.exists("First").resolved(),
            try Shape.exists("Second").resolved(),
        ])

        XCTAssertTrue(firstThenSecond.evaluating([
            .elementsChanged(Self.snapshot(["First"])),
            .elementsChanged(Self.snapshot(["Second"])),
        ]).isSatisfied)
        XCTAssertFalse(firstThenSecond.evaluating([
            .elementsChanged(Self.snapshot(["Second"])),
            .elementsChanged(Self.snapshot(["First"])),
        ]).isSatisfied)
    }

    func testOneEventCanSatisfyConsecutiveCurrentPredicates() throws {
        let expectation = Expectation([
            try Shape.exists("A").resolved(),
            try Shape.exists("B").resolved(),
            try Shape.exists("C").resolved(),
        ])

        XCTAssertTrue(expectation.evaluating([
            .elementsChanged(Self.snapshot(["A", "B", "C"])),
        ]).isSatisfied)
    }

    func testUnmetPredicateBlocksLaterPredicatesOnThatEvent() throws {
        let expectation = Expectation([
            try Shape.exists("A").resolved(),
            try Shape.exists("Never").resolved(),
            try Shape.exists("C").resolved(),
        ])
        let replay = expectation.evaluating([
            .elementsChanged(Self.snapshot(["A", "C"])),
        ])

        XCTAssertFalse(replay.isSatisfied)
        XCTAssertTrue(replay.outstandingDescription?.contains("Never") == true)
    }

    func testOneEventAdvancesAtMostOneLegOfATransition() throws {
        let appeared = Expectation([
            try Shape.appeared("Ready").resolved(),
        ])
        let afterMissing = appeared.evaluating([
            .elementsChanged(Self.snapshot([])),
        ])

        XCTAssertFalse(afterMissing.isSatisfied)
        XCTAssertTrue(afterMissing.outstandingDescription?.contains("Ready") == true)
        XCTAssertTrue(appeared.evaluating([
            .elementsChanged(Self.snapshot([])),
            .elementsChanged(Self.snapshot(["Ready"])),
        ]).isSatisfied)
    }

    func testNoChangeDoesNotSatisfyAnElementPredicate() throws {
        let expectation = Expectation([
            try Shape.appeared("Ready").resolved(),
        ])
        let replay = expectation.evaluating([.noChange, .noChange])

        XCTAssertFalse(replay.isSatisfied)
        XCTAssertNotNil(replay.outstandingDescription)
    }

    func testAssertionListRequiresEveryAssertionInAuthoredOrder() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .appeared(.label("Processing")),
            .disappeared(.label("Submit")),
        ])
        let expectation = Expectation([try predicate.resolve(in: .empty)])

        XCTAssertTrue(expectation.evaluating([
            .elementsChanged(Self.snapshot(["Submit"])),
            .elementsChanged(Self.snapshot(["Processing", "Submit"])),
            .elementsChanged(Self.snapshot(["Processing"])),
        ]).isSatisfied)
        XCTAssertFalse(expectation.evaluating([
            .elementsChanged(Self.snapshot(["Processing"])),
            .elementsChanged(Self.snapshot(["Submit"])),
        ]).isSatisfied)
    }

    func testUpdatedRequiresTwoMatchingEventsAndChangedProperty() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .updated(.label("Count"), .value()),
        ])
        let expectation = Expectation([try predicate.resolve(in: .empty)])
        let one = Observation.Event.elementsChanged(Self.counter("1"))
        let two = Observation.Event.elementsChanged(Self.counter("2"))

        XCTAssertFalse(expectation.evaluating([one]).isSatisfied)
        XCTAssertFalse(expectation.evaluating([one, one]).isSatisfied)
        XCTAssertTrue(expectation.evaluating([one, two]).isSatisfied)
    }

    func testBeforeEventIsNeverReusedForAfter() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .updated(
                .label("Count"),
                .value(before: "1", after: "2")
            ),
        ])
        let expectation = Expectation([try predicate.resolve(in: .empty)])
        let bothSelectorsMatch = Observation.Event.elementsChanged(
            Self.counts(["1", "2"])
        )
        let laterAfter = Observation.Event.elementsChanged(Self.counts(["2"]))

        XCTAssertFalse(
            expectation.evaluating([bothSelectorsMatch]).isSatisfied,
            "The event that satisfies before cannot also satisfy after"
        )
        XCTAssertTrue(
            expectation.evaluating([bothSelectorsMatch, laterAfter]).isSatisfied
        )
    }

    func testBareElementsChangedRequiresChangedGraphReading() throws {
        let expectation = Expectation([
            try AccessibilityPredicate.elementsChanged.resolve(in: .empty),
        ])
        let first = Observation.Event.elementsChanged(Self.snapshot(["First"]))
        let second = Observation.Event.elementsChanged(
            Self.snapshot(["First", "Second"])
        )

        XCTAssertFalse(expectation.evaluating([first]).isSatisfied)
        XCTAssertFalse(expectation.evaluating([first, first]).isSatisfied)
        XCTAssertTrue(expectation.evaluating([first, second]).isSatisfied)
    }

    private struct Row {
        let name: String
        let predicates: [Shape]
        let labels: [[String]]
        let holds: Bool

        init(
            _ name: String,
            predicates: [Shape],
            labels: [[String]],
            holds: Bool
        ) {
            self.name = name
            self.predicates = predicates
            self.labels = labels
            self.holds = holds
        }
    }

    private enum Shape {
        case exists(String)
        case missing(String)
        case appeared(String)
        case disappeared(String)

        func resolved() throws -> ObservationPredicate {
            let authored: AccessibilityPredicate = switch self {
            case .exists(let label):
                .exists(.label(label))
            case .missing(let label):
                .missing(.label(label))
            case .appeared(let label):
                .elementsChanged([.appeared(.label(label))])
            case .disappeared(let label):
                .elementsChanged([.disappeared(.label(label))])
            }
            return try authored.resolve(in: .empty)
        }
    }

    private static func snapshot(_ labels: [String]) -> Observation.Snapshot {
        makeTestObservationSnapshot(
            elements: labels.map {
                makeTestHeistElement(description: $0, label: $0)
            }
        )
    }

    private static func counter(
        _ value: String
    ) -> Observation.Snapshot {
        counts([value])
    }

    private static func counts(
        _ values: [String]
    ) -> Observation.Snapshot {
        makeTestObservationSnapshot(
            elements: values.map {
                makeTestHeistElement(label: "Count", value: $0)
            }
        )
    }
}

private extension Expectation {
    func evaluating(_ events: [Observation.Event]) -> Result {
        evaluateExpectation(self, events: events)
    }
}
