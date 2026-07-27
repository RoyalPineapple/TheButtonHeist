import ButtonHeistTestSupport
import AccessibilitySnapshotModel
import XCTest
import ThePlans
@testable import TheScore

extension AccessibilityPredicateTests {

    // MARK: - Codable

    func testScreenChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.screenChanged
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    /// A nameless predicate round-trips without exercising the `match` key at
    /// all, which is how a decoder that dropped the name stayed green.
    func testANamedScreenPredicateKeepsItsNameAcrossTheWire() throws {
        for match in [StringMatch.exact("Settings"), .contains("Sett"), .prefix("Set")] {
            let predicate = AccessibilityPredicate.screenChanged(match)
            let data = try JSONEncoder().encode(predicate)
            let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
            XCTAssertEqual(decoded, predicate, "\(match) did not survive the wire")
        }
    }

    // MARK: - Validation: screen changed

    /// The trace leaves an empty screen and arrives at one holding something, so
    /// the two readings differ and the boundary is proved by the captures
    /// themselves rather than by the notification that flagged them.
    func testScreenChangedMetWhenTraceChangesScreen() throws {
        let arrived = makeTestInterface(elements: [
            makeTestHeistElement(description: "Settings", label: "Settings"),
        ])
        let action = result(success: true, trace: .screenChangedForTests(replacementInterface: arrived), completeness: .incomplete)
        let result = try AccessibilityPredicate.screenChanged.resolve(in: .empty).validate(against: action)
        XCTAssertTrue(result.met, "outstanding: \(result.actual ?? "-")")
    }

    /// The boundary tick is the evidence, so a nameless boundary holds even when
    /// both sides read alike: what changed was the screen, not its elements.
    func testScreenChangedMetWhenBothSidesOfTheBoundaryReadTheSame() throws {
        let empty = makeTestInterface(elements: [])
        let action = result(success: true, trace: .screenChangedForTests(replacementInterface: empty), completeness: .incomplete)
        let result = try AccessibilityPredicate.screenChanged.resolve(in: .empty).validate(against: action)
        XCTAssertTrue(result.met, "outstanding: \(result.actual ?? "-")")
    }

    func testScreenChangedNotMetWithoutTrace() throws {
        let action = result(success: true)
        let result = try AccessibilityPredicate.screenChanged.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testScreenChangedUsesTraceEndpointProjection() throws {
        let before = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let after = makeTestInterface(elements: [
            HeistElement(
                description: "Settings",
                label: "Settings",
                value: nil,
                identifier: nil,
                traits: [.header],
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: []
            ),
        ])
        let first = AccessibilityTrace.Capture(
            sequence: 1,
            interface: before,
            context: AccessibilityTrace.Context(screenId: "home")
        )
        let last = AccessibilityTrace.Capture(
            sequence: 2,
            interface: after,
            parentHash: first.hash,
            context: AccessibilityTrace.Context(screenId: "settings"),
            transition: screenChangedTransition()
        )
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(traceEvidence(
                    AccessibilityTrace(captures: [first, last]),
                    completeness: .incomplete
                ))

        )

        let outcome = try AccessibilityPredicate.screenChanged.resolve(in: .empty).validate(against: result)

        XCTAssertTrue(outcome.met)
        XCTAssertNil(outcome.actual)
    }

    func testAScreenPredicateAsksAboutTheScreenAndNotItsElements() throws {
        let trace = screenTrace(
            before: makeTestInterface(elements: [header(label: "Home")]),
            after: makeTestInterface(elements: [header(label: "Settings")])
        )
        let result = result(success: true, trace: trace, completeness: .incomplete)

        // Any boundary answers a nameless one.
        XCTAssertTrue(
            try AccessibilityPredicate.screenChanged
                .resolve(in: .empty).validate(against: result).met
        )
        // A named one asks only about the name. Which elements left and which
        // arrived are element predicates, and they are siblings, not payload.
        XCTAssertTrue(
            try AccessibilityPredicate.screenChanged("Settings")
                .resolve(in: .empty).validate(against: result).met
        )
        XCTAssertFalse(
            try AccessibilityPredicate.screenChanged("Home")
                .resolve(in: .empty).validate(against: result).met
        )
    }

    /// A header is the only thing a screen name can come from, so a screen
    /// predicate needs one to have anything to match against.
    private func header(label: String) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            traits: [.header],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }

}
