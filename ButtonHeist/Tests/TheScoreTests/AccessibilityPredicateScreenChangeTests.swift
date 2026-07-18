import ButtonHeistTestSupport
import AccessibilitySnapshotModel
import XCTest
import ThePlans
@testable import TheScore

private typealias Fixture = AccessibilityPredicateTestFixture

extension AccessibilityPredicateTests {

    // MARK: - Codable

    func testScreenChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.screen())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    // MARK: - Validation: screen changed

    func testScreenChangedMetWhenTraceChangesScreen() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let action = Fixture.result(success: true, trace: .screenChangedForTests(replacementInterface: interface), completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testScreenChangedNotMetWhenTraceOnlyChangesElements() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "0", new: "1")
        let action = Fixture.result(success: true, trace: trace, completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "elementsChanged")
    }

    func testScreenChangedNotMetWithoutTrace() throws {
        let action = Fixture.result(success: true)
        let result = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: action)
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
            transition: Fixture.screenChangedTransition()
        )
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(Fixture.traceEvidence(
                    AccessibilityTrace(captures: [first, last]),
                    completeness: .incomplete
                ))

        )

        let outcome = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: result)

        XCTAssertTrue(outcome.met)
        XCTAssertNil(outcome.actual)
    }

    func testScreenAssertionsUseCurrentReplacementInterface() throws {
        let trace = Fixture.screenTrace(
            before: makeTestInterface(elements: [Fixture.element(label: "Home")]),
            after: makeTestInterface(elements: [Fixture.element(label: "Settings")])
        )
        let predicate = AccessibilityPredicate.changed(.screen([
            .exists(.label("Settings")),
            .missing(.label("Home")),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: Fixture.result(success: true, trace: trace, completeness: .incomplete)).met)
    }

    func testScreenChangedRequiresTraceEndpointEdge() throws {
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(Fixture.traceEvidence(
                    AccessibilityTrace(interface: Interface(
                        timestamp: Date(timeIntervalSince1970: 0),
                        tree: []
                    )),
                    completeness: .incomplete
                ))

        )

        let outcome = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: result)

        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "noChange")
    }

}
