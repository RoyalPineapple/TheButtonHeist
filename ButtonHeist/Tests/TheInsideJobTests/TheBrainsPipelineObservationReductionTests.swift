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
        // A boundary is three facts in causal order: the old screen's nodes
        // depart, the identity moves, the new screen's nodes arrive. The two
        // screens carry the same element here, but no element identity survives
        // a replacement — the header on the new screen is a new object, so it
        // arrives rather than persisting.
        XCTAssertEqual(
            transitionTrace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )

        let newBaseline = try XCTUnwrap(newScreenEvent.moment)
        let nextEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertEqual(nextEvent.generation, newScreenEvent.generation)
        let history = await brains.vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: newBaseline)
        }
        XCTAssertEqual(history, .events([.replayed(nextEvent)]))
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
        XCTAssertEqual(
            after.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    /// The two directions are not symmetric.
    ///
    /// A boundary is projected as three ticks — the old screen's nodes depart,
    /// the identity moves, the new screen's nodes arrive — and the lifecycle
    /// legs are ordinary element ticks. A predicate reads ticks and cannot ask
    /// whether a screen change sits between two of them, so `.elementsChanged`
    /// matches a boundary.
    ///
    /// The reverse does not hold. A same-screen change produces no screen tick
    /// at all, so `.screenChanged` has nothing to read and stays unmet.
    func testChangePredicatesReadScreenAndElementFactsSeparately() async throws {
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let newScreenEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let screenEvidence = try XCTUnwrap(AccessibilityTraceEvidence(
            trace: newScreenEvent.trace,
            completeness: .complete
        ))

        let screenExpression = AccessibilityPredicate.screenChanged
        let elementExpression = AccessibilityPredicate.elementsChanged
        let screenPredicate = ExpectationResult(
            try resolvedPredicate(screenExpression).evaluate(in: screenEvidence),
            predicate: screenExpression
        )
        let elementPredicateAgainstScreen = ExpectationResult(
            try resolvedPredicate(elementExpression).evaluate(in: screenEvidence),
            predicate: elementExpression
        )
        XCTAssertTrue(screenPredicate.met)
        XCTAssertTrue(elementPredicateAgainstScreen.met)

        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let elementCurrentEvent = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let elementEvidence = try XCTUnwrap(AccessibilityTraceEvidence(
            trace: elementCurrentEvent.trace,
            completeness: .complete
        ))

        let elementPredicate = ExpectationResult(
            try resolvedPredicate(elementExpression).evaluate(in: elementEvidence),
            predicate: elementExpression
        )
        let screenPredicateAgainstElement = ExpectationResult(
            try resolvedPredicate(screenExpression).evaluate(in: elementEvidence),
            predicate: screenExpression
        )
        XCTAssertTrue(elementPredicate.met)
        XCTAssertFalse(screenPredicateAgainstElement.met)
    }

}

#endif
