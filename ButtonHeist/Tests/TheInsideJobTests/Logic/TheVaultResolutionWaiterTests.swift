#if canImport(UIKit)
import UIKit
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheVaultResolutionTests {

    func testVisibleWaiterCompletesWithLaterPublication() async {
        let first = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        )
        let waiter = Task { @MainActor in
            await vault.semanticObservationStream.waitForObservation(
                after: first.historyRange.upperBound,
                scope: .visible,
                deadline: nil
            )
        }
        await waitForObservationWaiterCount(1)

        let second = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        )
        let result = await waiter.value

        XCTAssertEqual(result, .observation(second.current))
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testInvalidatedCurrentTruthRequiresLaterPublication() async {
        let first = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        )
        await vault.semanticObservationStream.invalidateCurrentAdmission()

        let admittedObservation = await vault.semanticObservationStream.admittedObservation(
            scope: .visible,
            after: nil
        )
        XCTAssertNil(admittedObservation)
        XCTAssertEqual(vault.interfaceTree.findElement(heistId: "first")?.heistId, "first")

        let waiter = Task { @MainActor in
            await vault.semanticObservationStream.waitForObservation(
                after: first.historyRange.upperBound,
                scope: .visible,
                deadline: nil
            )
        }
        await waitForObservationWaiterCount(1)

        let second = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        )
        let result = await waiter.value

        XCTAssertEqual(result, .observation(second.current))
    }

    func testDiscoveryWaiterIgnoresVisiblePublication() async {
        let first = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        )
        let waiter = Task { @MainActor in
            await vault.semanticObservationStream.waitForObservation(
                after: first.historyRange.upperBound,
                scope: .discovery,
                deadline: nil
            )
        }
        await waitForObservationWaiterCount(1)

        _ = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Visible"), "visible")])
        )
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 1)

        let discovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Discovery"), "discovery")])
        )
        let result = await waiter.value

        XCTAssertEqual(result, .observation(discovery.current))
        XCTAssertEqual(discovery.current.scope, .discovery)
    }

    func testVisibleWaiterReceivesCanonicalGraphFromDiscoveryPublication() async {
        let sharedHeader = element(label: "Catalog", traits: .header)
        let first = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [
                (sharedHeader, "catalog"),
                (element(label: "First"), "first"),
            ])
        )
        let waiter = Task { @MainActor in
            await vault.semanticObservationStream.waitForObservation(
                after: first.historyRange.upperBound,
                scope: .visible,
                deadline: nil
            )
        }
        await waitForObservationWaiterCount(1)

        let discovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(
                elements: [
                    (sharedHeader, "catalog"),
                    (element(label: "Visible Discovery"), "visible_discovery"),
                ],
                offViewport: [
                    InterfaceObservation.OffViewportEntry(
                        element(label: "Known Discovery"),
                        heistId: "known_discovery",
                        scrollContainerPath: TreePath([0])
                    ),
                ]
            )
        )
        let result = await waiter.value

        XCTAssertEqual(result, .observation(discovery.current))
        XCTAssertEqual(
            discovery.current.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Catalog", "Visible Discovery", "First", "Known Discovery"]
        )
        XCTAssertEqual(
            vault.interfaceElementIDs,
            ["catalog", "first", "known_discovery", "visible_discovery"]
        )
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testDiscoveryPublicationsRetainOrderedHistoryAndAccumulatedGraph() async {
        let start = await vault.semanticObservationStream.stateOwner.historyEndIndex()
        let sharedHeader = element(label: "Catalog", traits: .header)
        let first = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(
                elements: [
                    (sharedHeader, "catalog"),
                    (element(label: "First Visible"), "first_visible"),
                ],
                offViewport: [
                    InterfaceObservation.OffViewportEntry(
                        element(label: "First Known"),
                        heistId: "first_known",
                        scrollContainerPath: TreePath([0])
                    ),
                ]
            )
        )
        let second = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(
                elements: [
                    (sharedHeader, "catalog"),
                    (element(label: "Second Visible"), "second_visible"),
                ],
                offViewport: [
                    InterfaceObservation.OffViewportEntry(
                        element(label: "Second Known"),
                        heistId: "second_known",
                        scrollContainerPath: TreePath([0])
                    ),
                ]
            )
        )

        XCTAssertEqual(
            first.current.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label).sorted(),
            ["Catalog", "First Known", "First Visible"]
        )
        XCTAssertEqual(
            second.current.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label).sorted(),
            ["Catalog", "First Known", "First Visible", "Second Known", "Second Visible"]
        )
        guard case .success(let events) =
            await vault.semanticObservationStream.stateOwner.events(after: start)
        else {
            return XCTFail("Expected retained discovery history")
        }
        XCTAssertEqual(events, first.events + second.events)
        XCTAssertFalse(events.contains { event in
            if case .screenChanged = event { return true }
            return false
        })
        XCTAssertEqual(
            vault.interfaceElementIDs,
            ["catalog", "first_known", "first_visible", "second_known", "second_visible"]
        )
    }

    func testKnownScrollMembershipsAreKeyedByHeistIdForEqualElements() async {
        let repeated = AccessibilityElement.make(
            label: "Repeat",
            traits: .button,
            frame: CGRect(x: 0, y: 0, width: 100, height: 44)
        )
        let containerPath = TreePath([0])
        let repeatedGeometry = testGeometry(
            for: repeated,
            ownerPath: containerPath,
            screen: TheVault.onscreenSpace(for: repeated)
        )
        let scrollContainer = AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [
                "repeat_button_1": InterfaceTree.Element(
                    heistId: "repeat_button_1",
                    scrollMembership: InterfaceTree.ScrollMembership(
                        containerPath: containerPath,
                        index: 100
                    ),
                    geometry: repeatedGeometry,
                    element: repeated
                ),
                "repeat_button_2": InterfaceTree.Element(
                    heistId: "repeat_button_2",
                    scrollMembership: InterfaceTree.ScrollMembership(
                        containerPath: containerPath,
                        index: 500
                    ),
                    geometry: repeatedGeometry,
                    element: repeated
                ),
            ],
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(repeated, traversalIndex: 0),
                    .element(repeated, traversalIndex: 1),
                ]),
            ],
            heistIdsByPath: [
                TreePath([0, 0]): "repeat_button_1",
                TreePath([0, 1]): "repeat_button_2",
            ],
            firstResponderHeistId: nil
        ))

        XCTAssertEqual(
            vault.interfaceTree.findElement(heistId: "repeat_button_1")?.scrollMembership?.index,
            100
        )
        XCTAssertEqual(
            vault.interfaceTree.findElement(heistId: "repeat_button_2")?.scrollMembership?.index,
            500
        )
    }

    func testZeroTimeoutTurnsDiscoveryCycleBeforeReturningCurrentSnapshot() async {
        _ = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        )
        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        var discoveryCount = 0
        await vault.semanticObservationStream.start {
            discoveryCount += 1
            self.vault.observeInterface(second)
            let publication = await self.vault.semanticObservationStream
                .commitDiscoveryObservationForTesting(second)
            return Navigation.InterfaceExplorationResult(
                current: publication.current,
                progress: .init(),
                viewportExit: .restored
            )
        }

        let current = await vault.semanticObservationStream.nextObservation(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertGreaterThanOrEqual(discoveryCount, 1)
        XCTAssertEqual(
            current?.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Second"]
        )
    }

    func testDiscoveryDemandWidensPassiveObservationScopeForOneCycle() async {
        let discovery = InterfaceObservation.makeForTests(
            elements: [(element(label: "Discovery"), "discovery")]
        )
        var discoveryCount = 0
        await vault.semanticObservationStream.start {
            discoveryCount += 1
            self.vault.observeInterface(discovery)
            let publication = await self.vault.semanticObservationStream
                .commitDiscoveryObservationForTesting(discovery)
            return Navigation.InterfaceExplorationResult(
                current: publication.current,
                progress: .init(),
                viewportExit: .restored
            )
        }

        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)
        await Task.yield()
        let countBeforeDemand = discoveryCount
        XCTAssertEqual(countBeforeDemand, 0)

        let current = await vault.semanticObservationStream.nextObservation(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertGreaterThanOrEqual(discoveryCount, countBeforeDemand + 1)
        XCTAssertEqual(current?.scope, .discovery)
        XCTAssertEqual(
            current?.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Discovery"]
        )
    }

    func testZeroTimeoutDoesNotRunDiscoveryOnStoppedStream() async {
        let current = await vault.semanticObservationStream.nextObservation(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertNil(current)
    }

    func testCancelledVisibleWaiterUnregisters() async {
        let start = await vault.semanticObservationStream.stateOwner.historyEndIndex()
        let waiter = Task { @MainActor in
            await vault.semanticObservationStream.waitForObservation(
                after: start,
                scope: .visible,
                deadline: nil
            )
        }
        await waitForObservationWaiterCount(1)

        waiter.cancel()
        let result = await waiter.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
        _ = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Late"), "late")])
        )
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testCancelledDiscoveryWaiterUnregisters() async {
        var discoveryContinuation: CheckedContinuation<Void, Never>?
        await vault.semanticObservationStream.start {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                discoveryContinuation = continuation
            }
            return nil
        }
        defer {
            discoveryContinuation?.resume()
            discoveryContinuation = nil
        }

        let start = await vault.semanticObservationStream.stateOwner.historyEndIndex()
        let waiter = Task { @MainActor in
            await vault.semanticObservationStream.waitForObservation(
                after: start,
                scope: .discovery,
                deadline: nil
            )
        }
        await waitForObservationWaiterCount(1)

        waiter.cancel()
        let result = await waiter.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    private func waitForObservationWaiterCount(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard vault.semanticObservationStream.observationWaiterCount != expectedCount else {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) observation waiters")
    }
}

#endif
