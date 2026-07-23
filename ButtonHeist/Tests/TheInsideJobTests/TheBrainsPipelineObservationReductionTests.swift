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

    func testScopedScreenChangedStartsNewScreenGeneration() async throws {
        let oldScreenEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let newScreenEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let oldBaseline = try XCTUnwrap(oldScreenEvent.moment)
        let transitionTrace = AccessibilityTrace(captures: [
            oldBaseline.capture,
            newScreenEvent.moment.capture,
        ])

        XCTAssertNotEqual(newScreenEvent.generation, oldScreenEvent.generation)
        XCTAssertNil(newScreenEvent.trace.captures.last?.transition.fallbackReason)
        XCTAssertEqual(
            newScreenEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            transitionTrace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        let boundaryElementFacts = transitionTrace.changeFacts.compactMap { fact -> AccessibilityTrace.ElementsChangeFact? in
            guard case .elementsChanged(let elements) = fact else { return nil }
            return elements
        }
        XCTAssertEqual(boundaryElementFacts.count, 2)
        XCTAssertFalse(boundaryElementFacts[0].disappeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts[0].appeared.isEmpty)
        XCTAssertFalse(boundaryElementFacts[1].appeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts[1].disappeared.isEmpty)
        XCTAssertTrue(boundaryElementFacts.allSatisfy(\.updated.isEmpty))

        let newBaseline = try XCTUnwrap(newScreenEvent.moment)
        let nextEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertEqual(nextEvent.generation, newScreenEvent.generation)
        let history = await brains.vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: newBaseline)
        }
        XCTAssertEqual(history, .events([.snapshot(nextEvent)]))
    }

    func testPassiveCommitConsumesScopedScreenChangedSinceLastCommit() async {
        let notifications = brains.vault.accessibilityNotifications
        let heistScope = notifications.beginHeistScope()
        defer { heistScope.cancel() }
        let before = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        notifications.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(
            after.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
    }

    func testPassiveCommitIgnoresAmbientScreenChangedBetweenHeistScopes() async {
        let notifications = brains.vault.accessibilityNotifications
        let before = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let firstScope = notifications.beginHeistScope()
        firstScope.cancel()
        notifications.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        let secondScope = notifications.beginHeistScope()
        defer { secondScope.cancel() }

        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertEqual(after.generation, before.generation)
        XCTAssertTrue(after.trace.captures.last?.transition.accessibilityNotifications.isEmpty == true)
        XCTAssertTrue(after.trace.changeFacts.isEmpty)
    }

    func testElementChangedNotificationDoesNotSuppressSnapshotFallback() async throws {
        let before = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
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

    func testNotificationGapFallsBackToSnapshotClassification() async throws {
        let before = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(
                kind: .elementChanged(.layout),
                gap: AccessibilityNotificationGap(droppedThroughSequence: 1)
            )
        )

        XCTAssertNotEqual(after.generation, before.generation)
        XCTAssertEqual(after.trace.captures.last?.transition.fallbackReason, .primaryHeaderChanged)
    }

    func testScreenChangedReplacesDiscoveryOnlyTargetableTruthBeforePublication() async {
        await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old offscreen row", .staticText, "old_offscreen_row"),
            ])
        )

        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("New visible row", .staticText, "new_visible_row"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNil(brains.vault.interfaceTree.elements["old_offscreen_row"])
        XCTAssertNotNil(brains.vault.interfaceTree.elements["new_visible_row"])
    }

    func testScreenChangedReplacesDiscoveryCommitInsteadOfMergingOldTruth() async {
        await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old discovered row", .staticText, "old_discovered_row"),
            ])
        )

        await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("New discovered row", .staticText, "new_discovered_row"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertNil(brains.vault.interfaceTree.elements["old_discovered_row"])
        XCTAssertNotNil(brains.vault.interfaceTree.elements["new_discovered_row"])
    }

    func testExplicitScreenChangedPublishesSettledCandidateExactly() async {
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Home", .header, "home_header"),
                ("Old control", .button, "old_control"),
            ])
        )

        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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

    func testUnknownNotificationRequiresExplicitSnapshotFallbackForScreenChange() async throws {
        let before = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
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

    func testChangePredicatesReadScreenAndElementFactsSeparately() async throws {
        let oldScreenEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let newScreenEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let oldScreenBaseline = try XCTUnwrap(oldScreenEvent.moment)
        let screenEvidence = PredicateObservationEvidence(
            observation: brains.actionEvidenceProjector.projectSettledEvidence(from: newScreenEvent),
            baseline: oldScreenBaseline,
            eventsSinceBaseline: await brains.vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: oldScreenBaseline)
            }
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

        let elementBaselineEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let elementCurrentEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let elementBaseline = try XCTUnwrap(elementBaselineEvent.moment)
        let elementEvidence = PredicateObservationEvidence(
            observation: brains.actionEvidenceProjector.projectSettledEvidence(from: elementCurrentEvent),
            baseline: elementBaseline,
            eventsSinceBaseline: await brains.vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: elementBaseline)
            }
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

    func testPredicateObservationStreamPreservesChangeBaselineAcrossReductions() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let intermediateEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let finalEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
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
            eventsSinceBaseline: await brains.vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baselineEvent.moment)
            }
        )
        let final = intermediate.state.reducing(
            brains.actionEvidenceProjector.projectSettledEvidence(from: finalEvent),
            predicate: predicate,
            predicateExpression: expression,
            eventsSinceBaseline: await brains.vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baselineEvent.moment)
            }
        )

        XCTAssertEqual(intermediate.reduction.changeBaseline?.sequence, baselineEvent.sequence)
        XCTAssertEqual(final.reduction.changeBaseline?.sequence, baselineEvent.sequence)
        XCTAssertEqual(
            final.reduction.eventsSinceBaseline,
            .events([.snapshot(intermediateEvent), .snapshot(finalEvent)])
        )
    }

    func testPredicateObservationStreamDoesNotOwnWindowForCurrentStateWait() async throws {
        let predicate: AccessibilityPredicate = .missing(
            .label("Removed")
        )
        let baselineEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Anchor", .staticText, "anchor"),
                ("Removed", .staticText, "removed"),
            ])
        )
        let finalEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Anchor", .staticText, "anchor")])
        )

        let resolved = try resolvedPredicate(predicate)
        let stream = PredicateObservationStreamState().seedingBaseline(
            .currentObservation,
            from: baselineEvent,
            when: resolved.requiresChangeBaseline
        )
        let final = stream.reducing(
            brains.actionEvidenceProjector.projectSettledEvidence(from: finalEvent),
            predicate: resolved,
            predicateExpression: predicate
        )

        XCTAssertNil(stream.observationBaseline)
        XCTAssertTrue(final.reduction.expectation.met)
        XCTAssertNil(final.reduction.changeBaseline)
        XCTAssertNil(final.reduction.eventsSinceBaseline)
        XCTAssertTrue(final.reduction.trace?.changeFacts.contains {
            if case .elementsChanged = $0 { true } else { false }
        } == true)
    }
}

#endif
