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

    func testScopedScreenChangedPublishesBoundaryThenActualState() async {
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )
        let boundary = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertEqual(
            boundary.events.map(\.testKind),
            [.screenChanged, .elementsChanged]
        )
        guard case .screenChanged(let screen) = boundary.events[0],
              case .elementsChanged(let arrival) = boundary.events[1] else {
            return XCTFail("Expected screen boundary and actual state")
        }
        XCTAssertEqual(screen.idAfter, "Checkout")
        XCTAssertEqual(arrival, boundary.current.snapshot)

        let next = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertEqual(next.events, [.noChange])
    }

    func testPassiveCommitConsumesScopedScreenChangedSinceLastCommit() async {
        let notifications = brains.vault.accessibilityNotifications
        let heistScope = notifications.beginHeistScope()
        defer { heistScope.cancel() }
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        notifications.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")])
        )

        XCTAssertEqual(
            after.events.map(\.testKind),
            [.screenChanged, .elementsChanged]
        )
    }

    func testPassiveCommitIgnoresAmbientScreenChangedBetweenHeistScopes() async {
        let notifications = brains.vault.accessibilityNotifications
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
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

        XCTAssertEqual(after.events, [.noChange])
    }

    func testLayoutChangedNotificationDoesNotSuppressSnapshotScreenClassification() async {
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .layoutChanged)
        )

        XCTAssertEqual(
            after.events.map(\.testKind),
            [.screenChanged, .elementsChanged]
        )
    }

    func testNotificationGapStillClassifiesSnapshotScreenBoundary() async {
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let boundary = await brains.vault.semanticObservationStream.stateOwner
            .observationBoundary(scope: .discovery)
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(
                kind: .layoutChanged,
                gap: AccessibilityNotificationGap(droppedThroughSequence: 1)
            )
        )

        XCTAssertEqual(
            after.events.map(\.testKind),
            [.screenChanged, .elementsChanged]
        )
        let expectedCoverage = Observation.Coverage.incomplete(
            .notificationIngress(
                .init(afterSequence: 0, throughSequence: 1),
                additional: []
            )
        )
        let evidence = await brains.vault.semanticObservationStream.stateOwner
            .evidence(after: boundary)
        XCTAssertEqual(after.coverage, expectedCoverage)
        XCTAssertEqual(evidence.coverage, expectedCoverage)
    }

    func testScreenChangedReplacesDiscoveryOnlyTargetableTruthBeforePublication() async {
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old offscreen row", .staticText, "old_offscreen_row"),
            ])
        )

        _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
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
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [
                ("Checkout", .header, "checkout_header"),
                ("Old discovered row", .staticText, "old_discovered_row"),
            ])
        )

        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
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
        _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Home", .header, "home_header"),
                ("Old control", .button, "old_control"),
            ])
        )

        let boundary = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [
                ("Old control", .button, "old_control"),
                ("Details", .header, "details_header"),
                ("Persistent status", .staticText, "persistent_status"),
            ]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )

        XCTAssertEqual(
            boundary.current.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Old control", "Details", "Persistent status"]
        )
    }

    func testUnknownNotificationUsesSnapshotScreenClassification() async {
        _ = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let after = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .unknown(4_002))
        )

        XCTAssertEqual(
            after.events.map(\.testKind),
            [.screenChanged, .elementsChanged]
        )
    }

    func testChangePredicatesReadScreenAndElementEventsSeparately() async throws {
        let oldScreen = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Menu", .header, "menu_header")])
        )
        let screenBoundary = await brains.vault.semanticObservationStream.stateOwner
            .observationBoundary(scope: .discovery)
        let newScreen = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            makeScreen(elements: [("Checkout", .header, "checkout_header")]),
            notificationBatch: notificationBatch(kind: .screenChanged)
        )
        let screenEvidence = await brains.vault.semanticObservationStream.stateOwner
            .evidence(after: screenBoundary)

        XCTAssertEqual(screenEvidence.baseline, oldScreen.current.snapshot)
        XCTAssertEqual(screenEvidence.current, newScreen.current.snapshot)
        XCTAssertEqual(screenEvidence.events, newScreen.events)
        XCTAssertTrue(
            try resolvedPredicate(.screenChanged).evaluate(in: screenEvidence).met
        )
        XCTAssertTrue(
            try resolvedPredicate(.elementsChanged).evaluate(in: screenEvidence).met
        )

        let oldVolume = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "50%")
        )
        let elementBoundary = await brains.vault.semanticObservationStream.stateOwner
            .observationBoundary(scope: .discovery)
        let newVolume = await brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            volumeScreen(value: "60%")
        )
        let elementEvidence = await brains.vault.semanticObservationStream.stateOwner
            .evidence(after: elementBoundary)

        XCTAssertEqual(elementEvidence.baseline, oldVolume.current.snapshot)
        XCTAssertEqual(elementEvidence.current, newVolume.current.snapshot)
        XCTAssertEqual(elementEvidence.events, newVolume.events)
        XCTAssertTrue(
            try resolvedPredicate(.elementsChanged).evaluate(in: elementEvidence).met
        )
        XCTAssertFalse(
            try resolvedPredicate(.screenChanged).evaluate(in: elementEvidence).met
        )
    }
}

private extension Observation.Event {
    enum TestKind: Equatable {
        case elementsChanged
        case screenChanged
        case notification
        case noChange
    }

    var testKind: TestKind {
        switch self {
        case .elementsChanged:
            .elementsChanged
        case .screenChanged:
            .screenChanged
        case .notification:
            .notification
        case .noChange:
            .noChange
        }
    }
}

#endif
