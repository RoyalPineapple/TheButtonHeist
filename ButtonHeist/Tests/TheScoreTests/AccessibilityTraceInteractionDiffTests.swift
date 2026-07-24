import XCTest
import ButtonHeistTestSupport
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

final class AccessibilityTraceInteractionDiffTests: AccessibilityTraceDiffTestCase {
    func testGeometryOnlyMovementKeepsSemanticCaptureStableUnlessGeometryIncluded() throws {
        let beforeInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                activationPointEvidence: .explicit(ScreenPoint(x: 50, y: 22))
            ),
        ])
        let afterInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 10,
                frameY: 20,
                frameWidth: 100,
                frameHeight: 44,
                activationPointEvidence: .explicit(ScreenPoint(x: 60, y: 42))
            ),
        ])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let after = AccessibilityTrace.Capture(sequence: 2, interface: afterInterface, parentHash: before.hash)

        XCTAssertEqual(before.hash, after.hash)
        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected canonical elementsChanged fact")
        }
        let properties = try XCTUnwrap(payload.updated.single?.changes.map(\.property))
        XCTAssertEqual(properties, [.frame, .activationPoint])
    }

    func testGeometryOnlyMovementFeedsCanonicalPredicates() throws {
        let beforeInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                activationPointEvidence: .explicit(ScreenPoint(x: 50, y: 22))
            ),
        ])
        let afterInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 10,
                frameY: 20,
                frameWidth: 100,
                frameHeight: 44,
                activationPointEvidence: .explicit(ScreenPoint(x: 60, y: 42))
            ),
        ])
        let trace = AccessibilityTrace(first: beforeInterface).appending(afterInterface)
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: .complete
        ) else {
            return XCTFail("Expected predicate evidence")
        }
        let framePredicate = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Checkout"),
                .frame(after: ElementFrameMatch(x: 10, y: 20, width: 100, height: 44))
            ),
        ]))
        let semanticPredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Checkout"), .value(after: "Moved")),
        ]))

        XCTAssertTrue(try framePredicate.resolve(in: .empty).evaluate(in: evidence).met)
        XCTAssertFalse(try semanticPredicate.resolve(in: .empty).evaluate(in: evidence).met)
    }

    func testActivationPointEvidencePreservesDefaultExplicitAndUnavailable() throws {
        let defaultElement = makeAccessibilityElement(
            activationPoint: AccessibilityPoint(x: 0, y: 0),
            usesDefaultActivationPoint: true
        )
        let explicitElement = makeAccessibilityElement(
            activationPoint: AccessibilityPoint(x: 12, y: 34),
            usesDefaultActivationPoint: false
        )
        let unavailableElement = makeAccessibilityElement(
            activationPoint: AccessibilityPoint(x: .nan, y: .infinity),
            usesDefaultActivationPoint: false
        )

        let defaultProjection = HeistElement(accessibilityElement: defaultElement)
        let explicitProjection = HeistElement(accessibilityElement: explicitElement)
        let unavailableProjection = HeistElement(accessibilityElement: unavailableElement)

        XCTAssertEqual(
            defaultProjection.activationPointEvidence,
            .defaultCenter(ScreenPoint(x: 50, y: 22))
        )
        XCTAssertEqual(
            explicitProjection.activationPointEvidence,
            .explicit(ScreenPoint(x: 12, y: 34))
        )
        XCTAssertEqual(unavailableProjection.activationPointEvidence, .unavailable)
        XCTAssertNil(unavailableProjection.activationPointEvidence.point)
    }

    func testInteractionDigestReportsScreenAndFirstResponderChanges() throws {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(
                firstResponder: .predicate(ElementPredicate(label: "Email")),
                screenId: "login"
            )
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(
                firstResponder: .predicate(ElementPredicate(label: "Password")),
                screenId: "signup"
            )
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        let digest = try XCTUnwrap(facts.testInteractionDigest)

        XCTAssertTrue(digest.screenIdChanged)
        XCTAssertEqual(digest.screenIdBefore, "login")
        XCTAssertEqual(digest.screenIdAfter, "signup")
        XCTAssertTrue(digest.firstResponderChanged)
        XCTAssertFalse(digest.elementSetChanged)
    }

    func testInteractionDigestTreatsKeyboardVisibilityChangeAsFirstResponderChange() throws {
        let interface = makeInterface()
        let firstResponder = AccessibilityTarget.predicate(ElementPredicate(label: "Search"))
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(
                firstResponder: firstResponder,
                keyboardVisible: false,
                screenId: "library"
            )
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(
                firstResponder: firstResponder,
                keyboardVisible: true,
                screenId: "library"
            )
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        let digest = try XCTUnwrap(facts.testInteractionDigest)

        XCTAssertTrue(digest.firstResponderChanged)
        XCTAssertFalse(digest.screenIdChanged)
        XCTAssertFalse(digest.elementSetChanged)
    }
}
