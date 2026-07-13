import ButtonHeistTestSupport
import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class EvidenceMinimumMatcherTests: XCTestCase {
    func testMinimumMatcherUsesSettledBeforeState() throws {
        let label = makeReceiptTestElement(label: "Delete", traits: [.staticText])
        let button = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicateTemplate(label: "Delete"), ordinal: 1),
            subject: button,
            before: [label, button],
            after: [label, button]
        )

        XCTAssertEqual(
            EvidenceMinimumMatcher.minimumTarget(actionResult: actionResult),
            .predicate(ElementPredicateTemplate(label: "Delete", traits: [.button]))
        )
    }

    func testMinimumMatcherRefusesUnsettledEvidence() throws {
        let button = makeReceiptTestElement(label: "Delete", traits: [.button])
        let actionResult = semanticActionResult(
            method: .activate,
            source: .resolvedSemanticTarget,
            target: .predicate(ElementPredicateTemplate(label: "Delete")),
            subject: button,
            before: [button],
            after: [button],
            settled: false
        )

        XCTAssertNil(EvidenceMinimumMatcher.minimumTarget(actionResult: actionResult))
    }
}

private func semanticActionResult(
    method: ActionMethod,
    source: ActionSubjectEvidence.Source,
    target: AccessibilityTarget,
    subject: HeistElement,
    before: [HeistElement],
    after: [HeistElement],
    settled: Bool = true
) -> ActionResult {
    ActionResult.success(
        method: method,
        evidence: ActionResultSuccessEvidence(
            observation: .settledTrace(
                makeTestTraceEvidence(
                    makeReceiptTestTrace(
                        before: makeReceiptTestInterface(before),
                        after: makeReceiptTestInterface(after)
                    ),
                    completeness: settled ? .complete : .incomplete
                ),
                settled ? .settled(durationMs: 0) : .timedOut(durationMs: 0)
            ),
            subjectEvidence: ActionSubjectEvidence(
                source: source,
                target: target,
                element: subject,
                resolution: ActionSubjectResolution(origin: .visible),
                settledObservationSequence: 1
            )
        )
    )
}
