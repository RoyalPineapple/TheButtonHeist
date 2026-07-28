import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

extension AccessibilityPredicateTests {
    func testScreenChangedPredicatesRoundTrip() throws {
        let predicates: [AccessibilityPredicate] = [
            .screenChanged,
            .screenChanged(.exact("Settings")),
            .screenChanged(.contains("Setting")),
            .screenChanged(.prefix("Set")),
        ]

        for predicate in predicates {
            let data = try JSONEncoder().encode(predicate)
            XCTAssertEqual(
                try JSONDecoder().decode(
                    AccessibilityPredicate.self,
                    from: data
                ),
                predicate
            )
        }
    }

    func testBareScreenChangedMatchesAnyScreenChangedEvent() throws {
        let result = evaluateExpectation(Expectation([
            try resolvedScreen(.screenChanged),
        ]), events: [
            .screenChanged(ScreenFacts(idAfter: nil)),
        ])

        XCTAssertTrue(result.isSatisfied)
        XCTAssertNil(result.outstandingDescription)
    }

    func testNamedScreenChangedMatchesDestinationFacts() throws {
        let expectation = Expectation([
            try resolvedScreen(.screenChanged("Settings")),
        ])

        XCTAssertTrue(evaluateExpectation(expectation, events: [
            .screenChanged(ScreenFacts(idAfter: "Settings")),
        ]).isSatisfied)
        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .screenChanged(ScreenFacts(idAfter: "Home")),
        ]).isSatisfied)
        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .screenChanged(ScreenFacts(idAfter: nil)),
        ]).isSatisfied)
    }

    func testScreenChangedIgnoresElementNotificationAndStillnessEvents() throws {
        let notification = try XCTUnwrap(Observation.Notification(
            text: "Settings",
            element: makeTestHeistElement(label: "Settings").semantics
        ))
        let expectation = Expectation([
            try resolvedScreen(.screenChanged("Settings")),
        ])

        let result = evaluateExpectation(expectation, events: [
            .elementsChanged(observationSnapshot(elements: [
                makeTestHeistElement(label: "Settings"),
            ])),
            .notification(notification),
            .noChange,
        ])

        XCTAssertFalse(result.isSatisfied)
        XCTAssertTrue(
            result.outstandingDescription?.contains("Settings") == true
        )
    }

    private func resolvedScreen(
        _ predicate: AccessibilityPredicate
    ) throws -> ObservationPredicate {
        try predicate.resolve(in: .empty)
    }
}
