import ButtonHeistTestSupport
import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class EvidenceMinimumMatcherTests: XCTestCase {
    func testMinimumMatcherUsesSettledBeforeState() throws {
        let label = makeTestHeistElement(label: "Delete", traits: [.staticText])
        let button = makeTestHeistElement(label: "Delete", traits: [.button], actions: [])
        let actionResult = try semanticActionResult(
            payload: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete"), ordinal: 1),
            subject: button,
            before: [label, button],
            after: [label, button]
        )

        XCTAssertEqual(
            EvidenceMinimumMatcher.minimumTarget(actionResult: actionResult),
            .predicate(ElementPredicate(label: "Delete", traits: [.button]))
        )
    }

    func testMinimumMatcherRefusesUnsettledEvidence() throws {
        let button = makeTestHeistElement(label: "Delete", traits: [.button], actions: [])
        let actionResult = try semanticActionResult(
            payload: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicate(label: "Delete")),
            subject: button,
            before: [button],
            after: [button],
            complete: false
        )

        XCTAssertNil(EvidenceMinimumMatcher.minimumTarget(actionResult: actionResult))
    }
}

private func semanticActionResult(
    payload: ActionResult.Payload,
    source: ActionSubjectEvidence.Source,
    target: AccessibilityTarget,
    subject: HeistElement,
    before: [HeistElement],
    after: [HeistElement],
    complete: Bool = true
) throws -> ActionResult {
    ActionResult.success(
        payload: payload,
        observation: .observed(makeObservationEvidence(
            before: makeTestInterface(elements: before),
            after: makeTestInterface(elements: after),
            completeness: complete ? .complete : .incomplete
        )),
        subjectEvidence: ActionSubjectEvidence(
            source: source,
            target: try target.resolve(in: .empty),
            element: subject,
            resolution: ActionSubjectResolution(origin: .visible)
        )
    )
}
