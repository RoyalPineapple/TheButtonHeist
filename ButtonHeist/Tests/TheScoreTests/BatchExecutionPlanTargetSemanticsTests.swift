import XCTest
@testable import TheScore

final class BatchPlanTargetSemanticsTests: XCTestCase {

    func testMinimumMatcherTargetKeepsSourceHeistIdAsMetadataOnly() throws {
        let targetElement = makeElement(heistId: "checkout_total_$12", label: "Total", value: "$12.00", traits: [.staticText])
        let capture = makeCapture([
            targetElement,
            makeElement(heistId: "checkout_tax_$1", label: "Tax", value: "$1.00", traits: [.staticText]),
        ])
        let minimumMatcher = MinimumMatcher.build(element: targetElement, in: capture)

        let target = BatchExecutionTarget(minimumMatcher)

        XCTAssertEqual(target.sourceHeistId, "checkout_total_$12")
        XCTAssertEqual(target.matcher, ElementMatcher(label: "Total"))
        XCTAssertNil(target.matcher.heistId)
        guard case .matcher(let executableMatcher, let ordinal) = target.executableTarget else {
            return XCTFail("Expected executable identity to be matcher-based")
        }
        XCTAssertEqual(executableMatcher, ElementMatcher(label: "Total"))
        XCTAssertNil(executableMatcher.heistId)
        XCTAssertNil(ordinal)
    }

    func testValueChangingActionTargetUsesMatcherIdentityAfterRoundTrip() throws {
        let target = BatchExecutionTarget(
            sourceHeistId: "stepper_count_1",
            matcher: ElementMatcher(label: "Count", traits: [.adjustable])
        )
        let plan = BatchPlan(steps: [
            .action(.increment(target), expect: .elementUpdated(newValue: "2")),
        ])

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(BatchPlan.self, from: data)

        guard let decodedStep = decoded.steps.first,
              case .increment(let decodedTarget) = decodedStep.action,
              decodedStep.expectation == .elementUpdated(newValue: "2") else {
            return XCTFail("Expected increment action with elementUpdated expectation")
        }
        XCTAssertEqual(decodedTarget.sourceHeistId, "stepper_count_1")
        XCTAssertNil(decodedTarget.matcher.heistId)
        guard case .matcher(let executableMatcher, let ordinal) = decodedTarget.executableTarget else {
            return XCTFail("Expected matcher executable target")
        }
        XCTAssertEqual(executableMatcher, ElementMatcher(label: "Count", traits: [.adjustable]))
        XCTAssertNil(ordinal)
    }

    private func makeCapture(_ elements: [HeistElement]) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeTestInterface(elements: elements)
        )
    }

    private func makeElement(
        heistId: HeistId,
        label: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label ?? heistId,
            label: label,
            value: value,
            identifier: nil,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }
}
