#if canImport(UIKit)
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
@testable import TheScore

@MainActor
final class FirstResponderEvidenceInvariantTests: XCTestCase {

    func testParseNormalizesFirstResponderIntoValueSnapshot() throws {
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(AccessibilityElement.make(label: "Email", traits: .textEntry), traversalIndex: 0),
                .element(AccessibilityElement.make(label: "Password", traits: .textEntry), traversalIndex: 1),
            ]
        )
        let facts = TheBurglar.InterfaceObservationBuildFacts(
            focus: TheBurglar.InterfaceObservationBuildFocusFacts(firstResponderPaths: [secondPath])
        )

        let parsed = TheBurglar.buildObservation(from: result, facts: facts)
        let firstResponderHeistId = try XCTUnwrap(parsed.liveCapture.heistId(forPath: secondPath))
        let valueOnly = try InterfaceObservation.build(tree: parsed.tree)

        XCTAssertNotEqual(firstResponderHeistId, parsed.liveCapture.heistId(forPath: firstPath))
        XCTAssertEqual(parsed.tree.viewportCapture.firstResponderHeistId, firstResponderHeistId)
        XCTAssertEqual(valueOnly.liveCapture.firstResponderHeistId, firstResponderHeistId)
        XCTAssertTrue(valueOnly.liveCapture.elementRefs.isEmpty)
    }

    func testFirstResponderSnapshotDoesNotRetainUIKitObject() {
        let heistId: HeistId = "email_field"
        var responder: UITextField? = UITextField()
        let capture = InterfaceObservation.makeForTests(
            [
                InterfaceObservation.TestEntry(
                    label: "Email",
                    heistId: heistId,
                    traits: .textEntry,
                    object: responder
                ),
            ],
            firstResponderHeistId: heistId
        ).liveCapture

        XCTAssertTrue(capture.object(for: heistId) === responder)
        responder = nil

        XCTAssertNil(capture.object(for: heistId))
        XCTAssertEqual(capture.snapshot.firstResponderHeistId, heistId)
    }

    func testFirstResponderInflationAcceptsReplacementObjectUnderSameHeistId() throws {
        let heistId: HeistId = "email_field"
        let original = UITextField()
        let replacement = UITextField()
        let before = responderObservation(heistId: heistId, object: original)
        let after = responderObservation(heistId: heistId, object: replacement)
        let expected = try XCTUnwrap(before.liveCapture.firstResponderHeistId)

        XCTAssertFalse(before.liveCapture.object(for: heistId) === after.liveCapture.object(for: heistId))
        XCTAssertNil(ElementInflation.firstResponderIdentityFailure(
            expected: expected,
            current: after.liveCapture.firstResponderHeistId,
            inflated: heistId
        ))
    }

    func testFirstResponderInflationRejectsCurrentResponderUnderWrongHeistId() throws {
        let expected: HeistId = "email_field"
        let replacement: HeistId = "password_field"
        let before = responderObservation(heistId: expected, object: UITextField())
        let after = responderObservation(heistId: replacement, object: UITextField())
        let captured = try XCTUnwrap(before.liveCapture.firstResponderHeistId)

        let failure = try XCTUnwrap(ElementInflation.firstResponderIdentityFailure(
            expected: captured,
            current: after.liveCapture.firstResponderHeistId,
            inflated: expected
        ))

        XCTAssertEqual(failure.failedStep, .staleRefresh)
        XCTAssertEqual(failure.failureKind, .targetUnavailable)
    }

    func testFirstResponderInflationRejectsInflatedTargetUnderWrongHeistId() throws {
        let expected: HeistId = "email_field"
        let replacement: HeistId = "password_field"

        let failure = try XCTUnwrap(ElementInflation.firstResponderIdentityFailure(
            expected: expected,
            current: expected,
            inflated: replacement
        ))

        XCTAssertEqual(failure.failedStep, .staleRefresh)
        XCTAssertEqual(failure.failureKind, .targetUnavailable)
    }

    func testSemanticAndPostActionContextsShareCanonicalFirstResponderTarget() {
        let brains = TheBrains(tripwire: TheTripwire())
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (AccessibilityElement.make(label: "Email", traits: .textEntry), "email_field"),
                (AccessibilityElement.make(label: "Continue", traits: .button), "continue_button"),
            ],
            firstResponderHeistId: "email_field"
        )
        let expected = literalTarget(ElementPredicate(label: "Email"))

        let postAction = brains.postActionObservation.captureSemanticState(
            from: screen,
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )
        let semantic = brains.stash.semanticObservationStream
            .commitVisibleObservationForTesting(screen)

        XCTAssertEqual(brains.stash.firstResponderTarget(in: screen.tree), expected)
        XCTAssertEqual(postAction.capture.context.firstResponder, expected)
        XCTAssertEqual(semantic.trace.captures.last?.context.firstResponder, expected)
    }

    func testAmbiguousLiveResponderEvidenceIsNotGuessed() {
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(AccessibilityElement.make(label: "Email", traits: .textEntry), traversalIndex: 0),
                .element(AccessibilityElement.make(label: "Password", traits: .textEntry), traversalIndex: 1),
            ]
        )
        let facts = TheBurglar.InterfaceObservationBuildFacts(
            focus: TheBurglar.InterfaceObservationBuildFocusFacts(
                firstResponderPaths: [firstPath, secondPath]
            )
        )

        let parsed = TheBurglar.buildObservation(from: result, facts: facts)

        XCTAssertNil(parsed.tree.viewportCapture.firstResponderHeistId)
        XCTAssertNil(parsed.liveCapture.firstResponderHeistId)
    }

    func testFilteringPreservesOnlyFirstResponderStillInCommittedTree() {
        let brains = TheBrains(tripwire: TheTripwire())
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (AccessibilityElement.make(label: "Email", traits: .textEntry), "email_field"),
                (AccessibilityElement.make(label: "Continue", traits: .button), "continue_button"),
            ],
            firstResponderHeistId: "email_field"
        )

        let retained = screen.removingElements(withIds: ["continue_button"])
        let removed = screen.removingElements(withIds: ["email_field"])

        XCTAssertEqual(retained.tree.viewportCapture.firstResponderHeistId, "email_field")
        XCTAssertEqual(ScreenClassifier.snapshot(of: retained.tree).firstResponderHeistId, "email_field")
        XCTAssertNil(removed.tree.viewportCapture.firstResponderHeistId)
        XCTAssertNil(ScreenClassifier.snapshot(of: removed.tree).firstResponderHeistId)
        XCTAssertNil(brains.stash.firstResponderTarget(in: removed.tree))
    }

    private func responderObservation(
        heistId: HeistId,
        object: NSObject
    ) -> InterfaceObservation {
        InterfaceObservation.makeForTests(
            [
                InterfaceObservation.TestEntry(
                    label: "Text field",
                    heistId: heistId,
                    traits: .textEntry,
                    object: object
                ),
            ],
            firstResponderHeistId: heistId
        )
    }
}

#endif
