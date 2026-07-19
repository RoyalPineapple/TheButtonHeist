#if canImport(UIKit)
import Foundation
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheBrainsPipelineTests {

    func testScopedScreenChangedStartsNewScreenGeneration() throws {
        let oldScreenEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let newScreenEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let oldBaseline = try XCTUnwrap(oldScreenEvent.settledCapture)
        let transitionWindow = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: oldBaseline,
            through: newScreenEvent
        ))

        XCTAssertNotEqual(newScreenEvent.generation, oldScreenEvent.generation)
        XCTAssertNil(newScreenEvent.trace.captures.last?.transition.fallbackReason)
        XCTAssertEqual(
            newScreenEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(transitionWindow.completeness, .complete)
        XCTAssertEqual(
            transitionWindow.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        let boundaryElementFacts = transitionWindow.trace.changeFacts.compactMap { fact -> AccessibilityTrace.ElementsChangeFact? in
            guard case .elementsChanged(let elements) = fact else { return nil }
            return elements
        }
        XCTAssertEqual(boundaryElementFacts.count, 2)
        XCTAssertFalse(boundaryElementFacts[0].disappeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts[0].appeared.isEmpty)
        XCTAssertFalse(boundaryElementFacts[1].appeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts[1].disappeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts.allSatisfy(\.updated.isEmpty))

        let newBaseline = try XCTUnwrap(newScreenEvent.settledCapture)
        let nextEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let newScreenWindow = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: newBaseline,
            through: nextEvent
        ))

        XCTAssertEqual(nextEvent.generation, newScreenEvent.generation)
        XCTAssertEqual(newScreenWindow.completeness, .complete)
    }

    func testPassiveCommitConsumesScopedScreenChangedSinceLastCommit() {
        let notifications = brains.vault.accessibilityNotifications
        let heistScope = notifications.beginHeistScope()
        defer { heistScope.cancel() }
        let before = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        notifications.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        let after = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(
            after.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
    }

    func testPassiveCommitIgnoresAmbientScreenChangedBetweenHeistScopes() {
        let notifications = brains.vault.accessibilityNotifications
        let before = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let firstScope = notifications.beginHeistScope()
        firstScope.cancel()
        notifications.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        let secondScope = notifications.beginHeistScope()
        defer { secondScope.cancel() }

        let after = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertEqual(after.generation, before.generation)
        XCTAssertTrue(after.trace.captures.last?.transition.accessibilityNotifications.isEmpty == true)
        XCTAssertTrue(after.trace.changeFacts.isEmpty)
    }

    func testElementChangedNotificationDoesNotSuppressSnapshotFallback() throws {
        let before = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .elementChanged(.layout))
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(after.trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
        XCTAssertEqual(
            after.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.elementChanged(.layout)]
        )
        XCTAssertEqual(
            after.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testNotificationGapFallsBackToSnapshotClassification() throws {
        let before = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(
                kind: .elementChanged(.layout),
                gap: AccessibilityNotificationGap(droppedThroughSequence: 1)
            )
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(after.trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
    }

    func testScreenChangedReplacesDiscoveryOnlyTargetableTruthBeforePublication() {
        brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old offscreen row", .staticText, "old_offscreen_row"),
            ])
        )

        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("New visible row", .staticText, "new_visible_row"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNil(brains.vault.interfaceTree.elements["old_offscreen_row"])
        XCTAssertNotNil(brains.vault.interfaceTree.elements["new_visible_row"])
    }

    func testScreenChangedReplacesDiscoveryCommitInsteadOfMergingOldTruth() {
        brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old discovered row", .staticText, "old_discovered_row"),
            ])
        )

        brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("New discovered row", .staticText, "new_discovered_row"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNil(brains.vault.interfaceTree.elements["old_discovered_row"])
        XCTAssertNotNil(brains.vault.interfaceTree.elements["new_discovered_row"])
    }

    func testExplicitScreenChangedPublishesSettledCandidateExactly() {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Home", .header, "home_header"),
                ("Old control", .button, "old_control"),
            ])
        )

        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Old control", .button, "old_control"),
                ("Details", .header, "details_header"),
                ("Persistent status", .staticText, "persistent_status"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNotNil(brains.vault.interfaceTree.elements["old_control"])
        XCTAssertNotNil(brains.vault.interfaceTree.elements["details_header"])
        XCTAssertNotNil(brains.vault.interfaceTree.elements["persistent_status"])
    }

    func testUnknownNotificationRequiresExplicitSnapshotFallbackForScreenChange() throws {
        let before = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .unknown(4_002))
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(after.trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
        XCTAssertEqual(
            after.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.unknown(4_002)]
        )
        XCTAssertEqual(after.trace.changeFacts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
    }

    func testChangePredicatesReadScreenAndElementFactsSeparately() throws {
        let oldScreenEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let newScreenEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let oldScreenBaseline = try XCTUnwrap(oldScreenEvent.settledCapture)
        let screenWindow = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: oldScreenBaseline,
            through: newScreenEvent
        ))
        let screenEvidence = PredicateObservationEvidence(
            observation: brains.actionEvidenceProjector.projectSettledEvidence(from: newScreenEvent),
            baseline: oldScreenBaseline,
            window: screenWindow
        )

        let screenExpression = AccessibilityPredicate.changed(.screen())
        let elementExpression = AccessibilityPredicate.changed(.elements())
        let screenPredicate = screenEvidence.evaluate(
            try resolvedPredicate(screenExpression),
            expression: screenExpression
        )
        let elementPredicateAgainstScreen = screenEvidence.evaluate(
            try resolvedPredicate(elementExpression),
            expression: elementExpression
        )
        XCTAssertTrue(screenPredicate.met)
        XCTAssertTrue(elementPredicateAgainstScreen.met)

        let elementBaselineEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let elementCurrentEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let elementBaseline = try XCTUnwrap(elementBaselineEvent.settledCapture)
        let elementWindow = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: elementBaseline,
            through: elementCurrentEvent
        ))
        let elementEvidence = PredicateObservationEvidence(
            observation: brains.actionEvidenceProjector.projectSettledEvidence(from: elementCurrentEvent),
            baseline: elementBaseline,
            window: elementWindow
        )

        let elementPredicate = elementEvidence.evaluate(
            try resolvedPredicate(elementExpression),
            expression: elementExpression
        )
        let screenPredicateAgainstElement = elementEvidence.evaluate(
            try resolvedPredicate(screenExpression),
            expression: screenExpression
        )
        XCTAssertTrue(elementPredicate.met)
        XCTAssertFalse(screenPredicateAgainstElement.met)
        XCTAssertEqual(screenPredicateAgainstElement.actual, "elementsChanged")
    }

    func testPredicateObservationStreamPreservesChangeBaselineAcrossReductions() throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let intermediateEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let finalEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "70%")
        )

        let expression = AccessibilityPredicate.changed(.elements())
        let predicate = try resolvedPredicate(expression)
        let stream = PredicateObservationStreamState().seedingBaseline(
            .currentObservation,
            from: baselineEvent,
            when: predicate.requiresChangeBaseline
        )

        let intermediate = stream.reducing(
            brains.actionEvidenceProjector.projectSettledEvidence(from: intermediateEvent),
            predicate: predicate,
            predicateExpression: expression,
            observationWindow: try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
                from: try XCTUnwrap(baselineEvent.settledCapture),
                through: intermediateEvent
            ))
        )
        let final = intermediate.state.reducing(
            brains.actionEvidenceProjector.projectSettledEvidence(from: finalEvent),
            predicate: predicate,
            predicateExpression: expression,
            observationWindow: try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
                from: try XCTUnwrap(baselineEvent.settledCapture),
                through: finalEvent
            ))
        )

        XCTAssertEqual(intermediate.reduction.changeBaseline?.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.changeBaseline?.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.observationWindow?.baseline.cursor.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.observationWindow?.current.cursor.sequence, finalEvent.sequence)
    }

    func testPredicateObservationStreamDoesNotOwnWindowForCurrentStateWait() throws {
        let predicate: AccessibilityPredicate = .missing(
            .label("Removed")
        )
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Anchor", .staticText, "anchor"),
                ("Removed", .staticText, "removed"),
            ])
        )
        let finalEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Anchor", .staticText, "anchor")])
        )

        let resolved = try resolvedPredicate(predicate)
        let window = try XCTUnwrap(brains.vault.semanticObservationStream.observationWindow(
            from: try XCTUnwrap(baselineEvent.settledCapture),
            through: finalEvent
        ))
        let stream = PredicateObservationStreamState().seedingBaseline(
            .currentObservation,
            from: baselineEvent,
            when: resolved.requiresChangeBaseline
        )
        let final = stream.reducing(
            brains.actionEvidenceProjector.projectSettledEvidence(from: finalEvent),
            predicate: resolved,
            predicateExpression: predicate,
            observationWindow: window
        )

        XCTAssertNil(stream.observationBaseline)
        XCTAssertTrue(final.reduction.expectation.met)
        XCTAssertNil(final.reduction.changeBaseline)
        XCTAssertNil(final.reduction.observationWindow)
        XCTAssertTrue(final.reduction.trace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
    }
}

#endif
