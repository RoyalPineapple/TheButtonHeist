#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheVaultResolutionTests {

    func testSettledSemanticObservationWaiterCompletesOnLaterObservation() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.semanticObservationStream.latestObservation?.sequence

        let waiter = Task {
            await bagman.semanticObservationStream.settledEvent(scope: .visible, after: firstSequence, timeout: 1)
        }

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.settledObservation.observation.tree.orderedElements.first?.element.label, "Second")
    }

    func testUnbaselinedSettledObservationWaiterRequiresNextObservation() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)

        let waiter = Task { @MainActor in
            await bagman.semanticObservationStream.settledEvent(scope: .visible, after: nil, timeout: 1)
        }

        for _ in 0..<10 where bagman.semanticObservationStream.observationWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 1)

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.settledObservation.observation.tree.orderedElements.first?.element.label, "Second")
    }

    func testInvalidatedSettledObservationIsNotReturnedAsCleanTruth() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        let waiter = Task { @MainActor in
            await bagman.semanticObservationStream.settledEvent(scope: .visible, after: nil, timeout: 1)
        }

        for _ in 0..<10 where bagman.semanticObservationStream.observationWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 1)

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.settledObservation.observation.tree.orderedElements.first?.element.label, "Second")
    }

    func testTargetResolutionAfterTimeoutUsesSettledWorldNotDiagnosticEvidence() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled Action"), "settled_action")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout Action"), "timeout_action")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Settled Action"))).resolvedElement)
        XCTAssertNil(
            bagman.resolveTarget(literalTarget(ElementPredicate.label("Timeout Action"), ordinal: 0)).resolvedElement
        )
        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled Action")
        XCTAssertEqual(
            bagman.latestFailedSettleDiagnosticEvidence?.tree.orderedElements.first?.element.label,
            "Timeout Action"
        )
    }

    func testDiscoveryWaiterIgnoresVisibleObservation() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.semanticObservationStream.latestObservation?.sequence

        let waiter = Task { @MainActor in
            await bagman.semanticObservationStream.settledEvent(
                scope: .discovery,
                after: firstSequence,
                timeout: nil
            )
        }

        for _ in 0..<10 where bagman.semanticObservationStream.observationWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 1)

        let visible = InterfaceObservation.makeForTests(elements: [(element(label: "Visible"), "visible")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(visible)
        XCTAssertEqual(bagman.semanticObservationStream.latestObservation?.sequence, 2)
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 1)

        let discovery = InterfaceObservation.makeForTests(elements: [(element(label: "Discovery"), "discovery")])
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let observation = await waiter.value
        XCTAssertEqual(observation?.scope, .discovery)
        XCTAssertEqual(observation?.sequence, 3)
        XCTAssertEqual(observation?.settledObservation.observation.tree.orderedElements.first?.element.label, "Discovery")
    }

    func testVisibleWaiterReceivesCanonicalGraphFromDiscoveryObservation() async {
        let sharedHeader = element(label: "Catalog", traits: .header)
        let first = InterfaceObservation.makeForTests(elements: [
            (sharedHeader, "catalog"),
            (element(label: "First"), "first"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.semanticObservationStream.latestObservation?.sequence

        let waiter = Task { @MainActor in
            await bagman.semanticObservationStream.settledEvent(
                scope: .visible,
                after: firstSequence,
                timeout: nil
            )
        }

        for _ in 0..<10 where bagman.semanticObservationStream.observationWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 1)

        let visibleDiscovery = element(label: "Visible Discovery")
        let knownDiscovery = element(label: "Known Discovery")
        let discovery = InterfaceObservation.makeForTests(
            elements: [
                (sharedHeader, "catalog"),
                (visibleDiscovery, "visible_discovery"),
            ],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    knownDiscovery,
                    heistId: "known_discovery",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let observation = await waiter.value
        XCTAssertEqual(observation?.scope, .visible)
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(
            observation?.settledObservation.observation.tree.orderedElements.compactMap(\.element.label),
            ["Catalog", "Visible Discovery", "First", "Known Discovery"]
        )
        XCTAssertEqual(
            observation?.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Catalog", "Visible Discovery", "First", "Known Discovery"]
        )
        XCTAssertEqual(bagman.semanticObservationStream.latestObservation?.scope, .discovery)
        XCTAssertEqual(
            bagman.interfaceElementIDs,
            ["catalog", "first", "known_discovery", "visible_discovery"]
        )
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 0)
    }

    func testCleanVisibleEventAfterDiscoveryCarriesCanonicalGraph() async {
        let sharedHeader = element(label: "Catalog", traits: .header)
        let first = InterfaceObservation.makeForTests(elements: [
            (sharedHeader, "catalog"),
            (element(label: "First"), "first"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.semanticObservationStream.latestObservation?.sequence

        let visibleDiscovery = element(label: "Visible Discovery")
        let knownDiscovery = element(label: "Known Discovery")
        let discovery = InterfaceObservation.makeForTests(
            elements: [
                (sharedHeader, "catalog"),
                (visibleDiscovery, "visible_discovery"),
            ],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    knownDiscovery,
                    heistId: "known_discovery",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let observation = await bagman.semanticObservationStream.settledEvent(
            scope: .visible,
            after: firstSequence,
            timeout: nil
        )

        XCTAssertEqual(observation?.scope, .visible)
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(
            observation?.settledObservation.observation.tree.orderedElements.compactMap(\.element.label),
            ["Catalog", "Visible Discovery", "First", "Known Discovery"]
        )
        XCTAssertEqual(
            observation?.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Catalog", "Visible Discovery", "First", "Known Discovery"]
        )
    }

    func testDiscoveryProjectionMaintainsFullTrace() throws {
        let sharedHeader = element(label: "Catalog", traits: .header)
        let firstVisible = element(label: "First Visible")
        let firstKnown = element(label: "First Known")
        let first = InterfaceObservation.makeForTests(
            elements: [
                (sharedHeader, "catalog"),
                (firstVisible, "first_visible"),
            ],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    firstKnown,
                    heistId: "first_known",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        let firstEvent = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(first)

        let secondVisible = element(label: "Second Visible")
        let secondKnown = element(label: "Second Known")
        let second = InterfaceObservation.makeForTests(
            elements: [
                (sharedHeader, "catalog"),
                (secondVisible, "second_visible"),
            ],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    secondKnown,
                    heistId: "second_known",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        let event = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(second)

        XCTAssertEqual(event.scope, .discovery)
        XCTAssertEqual(event.generation, firstEvent.generation)
        XCTAssertEqual(event.trace.captures.count, 2)
        XCTAssertEqual(
            try XCTUnwrap(event.trace.captures.first).interface.projectedElements.compactMap(\.label).sorted(),
            ["Catalog", "First Known", "First Visible"]
        )
        XCTAssertEqual(
            try XCTUnwrap(event.trace.captures.last).interface.projectedElements.compactMap(\.label).sorted(),
            ["Catalog", "First Known", "First Visible", "Second Known", "Second Visible"]
        )
        XCTAssertEqual(
            bagman.interfaceElementIDs,
            ["catalog", "first_known", "first_visible", "second_known", "second_visible"]
        )
    }

    func testKnownScrollMembershipsAreKeyedByHeistIdForEqualElements() {
        let repeated = AccessibilityElement.make(
            label: "Repeat",
            traits: .button,
            frame: CGRect(x: 0, y: 0, width: 100, height: 44)
        )
        let containerPath = TreePath([0])
        let scrollContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [
                "repeat_button_1": InterfaceTree.Element(
                    heistId: "repeat_button_1",
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: 100),
                    element: repeated
                ),
                "repeat_button_2": InterfaceTree.Element(
                    heistId: "repeat_button_2",
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: 500),
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
            firstResponderHeistId: nil,
        ))

        XCTAssertEqual(
            bagman.interfaceTree.findElement(heistId: "repeat_button_1")?.scrollMembership?.index,
            100
        )
        XCTAssertEqual(
            bagman.interfaceTree.findElement(heistId: "repeat_button_2")?.scrollMembership?.index,
            500
        )
    }

    func testTimeoutZeroTurnsObservationCycleBeforeReturningCleanLatest() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(first)
        let firstSequence = bagman.semanticObservationStream.latestObservation?.sequence

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        var discoveryCount = 0
        bagman.semanticObservationStream.start {
            discoveryCount += 1
            self.bagman.recordParsedObservedEvidence(second)
            let event = self.bagman.semanticObservationStream
                .commitDiscoveryObservationForTesting(second)
            return Navigation.InterfaceExplorationResult(
                event: event,
                progress: .init()
            )
        }

        let observation = await bagman.semanticObservationStream.settledEvent(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertGreaterThanOrEqual(discoveryCount, 1)
        XCTAssertGreaterThan(observation?.sequence ?? 0, firstSequence ?? 0)
        XCTAssertEqual(observation?.settledObservation.observation.tree.orderedElements.first?.element.label, "Second")
    }

    func testPassiveObservationLeaseDoesNotRunDiscoveryWithoutDiscoveryDemand() async {
        let discovery = InterfaceObservation.makeForTests(elements: [(element(label: "Discovery"), "discovery")])
        var discoveryCount = 0
        bagman.semanticObservationStream.start {
            discoveryCount += 1
            self.bagman.recordParsedObservedEvidence(discovery)
            let event = self.bagman.semanticObservationStream
                .commitDiscoveryObservationForTesting(discovery)
            return Navigation.InterfaceExplorationResult(
                event: event,
                progress: .init()
            )
        }

        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)
        await Task.yield()
        let discoveryCountBeforeDemand = discoveryCount
        XCTAssertEqual(discoveryCountBeforeDemand, 0)

        let observation = await bagman.semanticObservationStream.settledEvent(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertGreaterThanOrEqual(discoveryCount, discoveryCountBeforeDemand + 1)
        XCTAssertEqual(observation?.scope, .discovery)
        XCTAssertEqual(observation?.settledObservation.observation.tree.orderedElements.first?.element.label, "Discovery")
    }

    func testTimeoutZeroDoesNotInvokeDiscoveryWithoutPassiveObserver() async {
        let observation = await bagman.semanticObservationStream.settledEvent(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertNil(observation)
    }

    func testCancelledSettledObservationWaiterUnregisters() async {
        let waiter = Task { @MainActor in
            await bagman.semanticObservationStream.settledEvent(scope: .visible, after: nil, timeout: 10)
        }

        for _ in 0..<20 where bagman.semanticObservationStream.observationWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 1)

        waiter.cancel()
        for _ in 0..<20 where bagman.semanticObservationStream.observationWaiterCount != 0 {
            await Task.yield()
        }

        let observation = await waiter.value
        XCTAssertNil(observation)
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 0)

        let late = InterfaceObservation.makeForTests(elements: [(element(label: "Late"), "late")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(late)
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 0)
    }

    func testCancelledDiscoveryObservationWaiterUnregisters() async {
        var discoveryContinuation: CheckedContinuation<Void, Never>?
        var discoveryObservation: InterfaceObservation?
        func resumeDiscovery(returning observation: InterfaceObservation?) {
            discoveryObservation = observation
            let continuation = discoveryContinuation
            discoveryContinuation = nil
            continuation?.resume()
        }

        bagman.semanticObservationStream.start {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                discoveryContinuation = continuation
            }
            let observation = discoveryObservation
            discoveryObservation = nil
            return observation.map {
                self.bagman.recordParsedObservedEvidence($0)
                let event = self.bagman.semanticObservationStream
                    .commitDiscoveryObservationForTesting($0)
                return Navigation.InterfaceExplorationResult(
                    event: event,
                    progress: .init()
                )
            }
        }
        defer { resumeDiscovery(returning: nil) }

        let waiter = Task { @MainActor in
            await bagman.semanticObservationStream.settledEvent(scope: .discovery, after: nil, timeout: 0)
        }

        for _ in 0..<20 where bagman.semanticObservationStream.observationWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 1)

        waiter.cancel()
        for _ in 0..<20 where bagman.semanticObservationStream.observationWaiterCount != 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 0)

        resumeDiscovery(returning: InterfaceObservation.makeForTests(elements: [(element(label: "Discovery"), "discovery")]))
        let observation = await waiter.value
        XCTAssertNil(observation)
        XCTAssertEqual(bagman.semanticObservationStream.observationWaiterCount, 0)
    }

}

#endif
