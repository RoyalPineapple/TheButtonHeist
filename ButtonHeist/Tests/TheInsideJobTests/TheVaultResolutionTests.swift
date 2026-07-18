#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheVaultResolutionTests: XCTestCase {

    var bagman: TheVault!

    override func setUp() async throws {
        bagman = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        bagman.semanticObservationStream.stop()
        bagman = nil
    }

    // MARK: - Helpers

    private var nextElementYOffset: CGFloat = 0

    func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        // Every constructed element gets a unique frame so duplicates are
        // distinguishable at the AccessibilityElement (Hashable) level — the
        // tests rely on registering multiple "same-label" elements that the
        // current InterfaceObservation value treats as distinct.
        let frame = CGRect(x: 0, y: nextElementYOffset, width: 100, height: 44)
        nextElementYOffset += 50
        return .make(
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            shape: .frame(AccessibilityRect(frame))
        )
    }

    /// Accumulated live hierarchy nodes for visible-scoped lookups.
    private var hierarchyNodes: [AccessibilityHierarchy] = []
    /// Accumulated elements (in registration order).
    private var registeredEntries: [(element: AccessibilityElement, heistId: HeistId, isLive: Bool)] = []

    /// Register an element into the current InterfaceObservation. Rebuilds the observation value
    /// on every call so individual tests don't have to think about the
    /// memberwise init. `InterfaceObservation.heistIdsByPath` is the live matcher lookup.
    func register(_ element: AccessibilityElement, heistId: HeistId, index: Int) {
        hierarchyNodes.append(.element(element, traversalIndex: index))
        registeredEntries.append((element, heistId, true))
        rebuildObservation()
    }

    /// Element registration that only adds the leaf to the heistId→entry map
    /// without putting it in the live hierarchy. Known entries return nil from
    /// visible-scoped accessors but still participate in semantic target
    /// resolution.
    func registerOffScreen(_ element: AccessibilityElement, heistId: HeistId) {
        registeredEntries.append((element, heistId, false))
        rebuildObservation()
    }

    private func rebuildObservation() {
        var elements: [HeistId: InterfaceTree.Element] = [:]
        var heistIdsByPath: [TreePath: HeistId] = [:]
        var liveIndex = 0
        for entry in registeredEntries where entry.isLive {
            heistIdsByPath[TreePath([liveIndex])] = entry.heistId
            liveIndex += 1
        }
        for entry in registeredEntries {
            let treeElement = InterfaceTree.Element(
                heistId: entry.heistId,
                scrollMembership: nil,
                element: entry.element
            )
            elements[entry.heistId] = treeElement
        }
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: elements,
            hierarchy: hierarchyNodes,
            heistIdsByPath: heistIdsByPath,
            firstResponderHeistId: nil,
        ))
    }

    func installMatchingScreen() {
        nextElementYOffset = 0
        let observation = InterfaceObservation.makeForTests(elements: [
            (
                element(label: "Save", value: "Draft", identifier: "save_button", traits: .button),
                HeistId(rawValue: "save_button")
            ),
            (
                element(label: "Save Draft", value: "Draft", identifier: "save_draft_button", traits: .button),
                HeistId(rawValue: "save_draft_button")
            ),
            (
                element(label: "Search Items", value: "milk", identifier: "search_field", traits: .searchField),
                HeistId(rawValue: "search_field")
            ),
            (
                element(label: "Settings", identifier: "settings_header", traits: .header),
                HeistId(rawValue: "settings_header")
            ),
            (
                element(label: "Delete", value: "First", identifier: "delete_first", traits: .button),
                HeistId(rawValue: "delete_first")
            ),
            (
                element(label: "Delete", value: "Second", identifier: "delete_second", traits: [.button, .notEnabled]),
                HeistId(rawValue: "delete_second")
            ),
            (
                element(label: "Done", value: "Complete", identifier: "done_button", traits: [.button, .selected]),
                HeistId(rawValue: "done_button")
            ),
        ])
        bagman.installObservationForTesting(observation)
    }

    func resolvedTarget(_ authored: AccessibilityTarget) throws -> ResolvedAccessibilityTarget {
        try authored.resolve(in: .empty)
    }

    func resolvedPredicate(_ authored: AccessibilityTarget) throws -> ElementPredicate {
        guard case .predicate(let predicate, ordinal: nil) = try resolvedTarget(authored) else {
            return try XCTUnwrap(nil as ElementPredicate?, "Expected an unqualified element predicate")
        }
        return predicate
    }

}

extension TheVault.TargetAmbiguityFacts {
    var elementMatches: TheVault.TargetElementMatches? {
        guard case .elements(let matches) = matchSet else {
            return nil
        }
        return matches
    }

    var containerMatches: TheVault.TargetContainerMatches? {
        guard case .containers(let matches) = matchSet else {
            return nil
        }
        return matches
    }
}

extension TheVault.TargetNotFoundFacts {
    var elementMatches: TheVault.TargetElementMatches? {
        guard case .elements(let matches) = matchSet else {
            return nil
        }
        return matches
    }

    var containerMatches: TheVault.TargetContainerMatches? {
        guard case .containers(let matches) = matchSet else {
            return nil
        }
        return matches
    }
}

@MainActor
extension TheVaultResolutionTests {

    func testSemanticObservationSubscriptionsCoalesceToWidestScope() {
        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)

        let visible = bagman.semanticObservationStream.subscribe(scope: .visible)
        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)

        do {
            let discovery = bagman.semanticObservationStream.subscribe(scope: .discovery)
            XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .discovery)
            _ = discovery
        }

        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)
        _ = visible
    }

    func testActiveObservationDemandChangesCadenceWithoutWideningScope() {
        XCTAssertFalse(bagman.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 0)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .idle)
        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)

        let demand = bagman.semanticObservationStream.beginActiveObservationDemand()
        XCTAssertTrue(bagman.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 1)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .active)
        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)

        do {
            let discovery = bagman.semanticObservationStream.subscribe(scope: .discovery)
            XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .discovery)
            _ = discovery
        }

        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)

        demand.cancel()

        XCTAssertFalse(bagman.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 0)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .idle)
        XCTAssertEqual(bagman.semanticObservationStream.subscribedObservationScope(), .visible)
    }

    func testInterfaceTreeKeepsLiveEvidenceOutOfTreeState() {
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        let observation = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        let tree = InterfaceTree.empty.updatingViewport(with: observation)

        XCTAssertTrue(observation.liveCapture.object(for: "save") === liveObject)
        XCTAssertNil(LiveCapture.makeForTests(snapshot: tree.viewportCapture).object(for: "save"))
        XCTAssertEqual(tree.findElement(heistId: "save")?.element.label, "Save")
    }

    func testInterfaceTreeViewportUpdateDropsDiscoveryMemoryAfterNavigation() {
        let bottom = element(label: "Bottom Row", traits: .button)
        let staleOffscreen = element(label: "Stale Row", traits: .button)
        let discovery = InterfaceObservation.makeForTests(
            elements: [(bottom, "bottom_row")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleOffscreen,
                    heistId: "shared_row",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        let tree = discovery.tree

        let freshVisible = element(label: "Fresh Row", traits: .button)
        let refreshedTop = InterfaceObservation.makeForTests(elements: [(freshVisible, "shared_row")])
        let updated = tree.updatingViewport(with: refreshedTop)

        XCTAssertEqual(updated.viewportElementIDs, ["shared_row"])
        XCTAssertEqual(updated.elementIDs, ["shared_row"])
        XCTAssertEqual(updated.findElement(heistId: "shared_row")?.element.label, "Fresh Row")
        XCTAssertNil(updated.findElement(heistId: "bottom_row"))
    }

    func testInterfaceTreeViewportUpdateKeepsDiscoveryMemoryWhenViewportIdentityPairsWithNewId() {
        let previousVisible = element(label: "Counter", value: "1", traits: .button)
        let discoveryOnly = element(label: "Details", traits: .button)
        let discovery = InterfaceObservation.makeForTests(
            elements: [(previousVisible, "counter_old")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    discoveryOnly,
                    heistId: "details",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        let tree = discovery.tree

        let currentVisible = element(label: "Counter", value: "2", traits: .button)
        let updated = tree.updatingViewport(
            with: InterfaceObservation.makeForTests(elements: [(currentVisible, "counter_new")])
        )

        XCTAssertEqual(updated.viewportElementIDs, ["counter_new"])
        XCTAssertEqual(updated.elementIDs, ["counter_new", "details"])
        XCTAssertNil(updated.findElement(heistId: "counter_old"))
        XCTAssertEqual(updated.findElement(heistId: "details")?.element.label, "Details")
    }

    func testVisibleExplorationBaselineDropsStaleDiscoveryEntriesSharingContainerName() {
        let visibleWord = element(label: "Words", traits: .staticText)
        let staleHomeButton = element(label: "Auto-Settle Fixtures", traits: .button)
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let currentVisible = InterfaceObservation.makeForTests(
            elements: [
                "words_header": InterfaceTree.Element(
                    heistId: "words_header",
                    scrollMembership: nil,
                    element: visibleWord
                ),
            ],
            hierarchy: [
                .container(container, children: [
                    .element(visibleWord, traversalIndex: 0),
                ]),
            ],
            containerNamesByPath: [TreePath([0]): "scrollable_0_0_50_109"],
            heistIdsByPath: [TreePath([0, 0]): "words_header"],
            firstResponderHeistId: nil,
        )
        var elements = currentVisible.tree.elements
        elements["home_button"] = InterfaceTree.Element(
            heistId: "home_button",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: staleHomeButton
        )
        let pollutedSettledScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: elements,
                containers: currentVisible.tree.containers
            ),
            liveCapture: currentVisible.liveCapture
        )
        let baseline = bagman.visibleExplorationBaseline(from: pollutedSettledScreen)

        XCTAssertEqual(baseline.tree.elementIDs, ["words_header"])
        XCTAssertEqual(baseline.tree.viewportElementIDs, ["words_header"])
        XCTAssertNil(baseline.tree.findElement(heistId: "home_button"))
        XCTAssertEqual(baseline.liveCapture.hierarchy, currentVisible.liveCapture.hierarchy)
    }

    func testActionDiscoveryBaselineDropsStaleDiscoveryMemoryWhenScreenIdChanges() throws {
        let previousHeader = element(label: "Controls Demo", traits: .header)
        let sharedPreviousAction = element(label: "Shared Action", traits: .button)
        let staleOffscreen = element(label: "Stale Offscreen", traits: .button)
        let previousDiscovery = InterfaceObservation.makeForTests(
            elements: [
                (previousHeader, "controls_demo"),
                (sharedPreviousAction, "shared_action"),
            ],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleOffscreen,
                    heistId: "stale_offscreen",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        XCTAssertEqual(previousDiscovery.tree.id, "controls_demo")
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(previousDiscovery)

        let currentHeader = element(label: "ButtonHeist Demo", traits: .header)
        let sharedCurrentAction = element(label: "Shared Action", traits: .button)
        let currentVisible = InterfaceObservation.makeForTests(elements: [
            (currentHeader, "buttonheist_demo"),
            (sharedCurrentAction, "shared_action"),
        ])
        XCTAssertEqual(currentVisible.tree.id, "buttonheist_demo")
        bagman.semanticObservationStream.commitVisibleObservationForTesting(currentVisible)

        let baseline = bagman.actionDiscoveryBaseline()

        XCTAssertEqual(baseline.tree.id, "buttonheist_demo")
        XCTAssertEqual(baseline.tree.viewportElementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertEqual(baseline.tree.elementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertNil(baseline.tree.findElement(heistId: "controls_demo"))
        XCTAssertNil(baseline.tree.findElement(heistId: "stale_offscreen"))
    }

}

@MainActor
extension TheVaultResolutionTests {

    func testLatestSettledSemanticObservationAdvancesMonotonically() {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstObservation = bagman.semanticObservationStream.latestObservation

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)
        let secondObservation = bagman.semanticObservationStream.latestObservation

        XCTAssertNotNil(firstObservation)
        XCTAssertNotNil(secondObservation)
        XCTAssertEqual(firstObservation?.sequence, 1)
        XCTAssertEqual(secondObservation?.sequence, 2)
        XCTAssertEqual(secondObservation?.observation.tree.orderedElements.first?.element.label, "Second")
    }

    func testSettledSemanticObservationRetainsFirstResponderWithoutLiveObjectReferences() throws {
        let object = NSObject()
        let observation = InterfaceObservation.makeForTests(
            [
                InterfaceObservation.TestEntry(
                    element(label: "Email"),
                    heistId: "email",
                    object: object
                ),
            ],
            firstResponderHeistId: "email"
        )

        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        let settledObservation = try XCTUnwrap(
            bagman.semanticObservationStream.latestObservation?.observation
        )
        XCTAssertEqual(settledObservation.liveCapture.firstResponderHeistId, "email")
        XCTAssertNil(settledObservation.liveCapture.object(for: "email"))
    }

    func testSettledSemanticObservationEventContainsNoLiveTripwireIdentity() {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Home"), "home")])

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertFalse(containsLiveTripwireIdentity(event))
    }

    func testCleanVisibleSettleCommitUpdatesSettledSemanticTruth() {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])

        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertFalse(bagman.semanticObservationStream.latestSettledObservationInvalidated)
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence)
    }

    func testSettledSemanticObservationEventCarriesPreviousTraceAndFacts() throws {
        let first = InterfaceObservation.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstEvent = try XCTUnwrap(bagman.semanticObservationStream.latestEvent)

        XCTAssertEqual(firstEvent.sequence, 1)
        XCTAssertNil(firstEvent.previous)
        XCTAssertEqual(firstEvent.trace.captures.count, 1)
        XCTAssertTrue(firstEvent.trace.changeFacts.isEmpty)

        let second = InterfaceObservation.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
            (element(label: "Toast"), "toast"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)
        let secondEvent = try XCTUnwrap(bagman.semanticObservationStream.latestEvent)

        XCTAssertEqual(secondEvent.sequence, 2)
        XCTAssertEqual(secondEvent.previous?.sequence, 1)
        XCTAssertEqual(secondEvent.trace.captures.count, 2)
        XCTAssertEqual(secondEvent.trace.captures.first?.hash, firstEvent.trace.captures.last?.hash)

        guard case .elementsChanged(let fact)? = secondEvent.trace.changeFacts.first else {
            return XCTFail("Expected elementsChanged event fact")
        }
        XCTAssertEqual(fact.appeared.compactMap { node in
            guard case .element(let element, _) = node.node else { return nil }
            return element.label
        }, ["Toast"])
    }

    func testVisibleObservationTraceCarriesCanonicalCommittedGraph() throws {
        let visible = element(label: "Custom Rotors", traits: .button)
        let discovered = element(label: "ButtonHeist Demo", traits: .button)
        let discovery = InterfaceObservation.makeForTests(
            elements: [(visible, "custom_rotors")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    discovered,
                    heistId: "buttonheist_demo",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let refreshedVisible = InterfaceObservation.makeForTests(elements: [(visible, "custom_rotors")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(refreshedVisible)

        let event = try XCTUnwrap(bagman.semanticObservationStream.latestEvent)
        XCTAssertEqual(event.scope, .visible)
        XCTAssertEqual(bagman.interfaceElementIDs, ["buttonheist_demo", "custom_rotors"])

        let labels = try XCTUnwrap(event.trace.captures.last)
            .interface
            .projectedElements
            .compactMap(\.label)
        XCTAssertEqual(labels, ["Custom Rotors", "ButtonHeist Demo"])
    }

    func testDiagnosticEvidenceInvalidatesLatestSettledObservationWithoutReplacingIt() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)
        let sequence = bagman.semanticObservationStream.latestObservation?.sequence

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(bagman.semanticObservationStream.latestObservation?.sequence, sequence)
        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.tree.orderedElements.first?.element.label, "Timeout")
        XCTAssertTrue(bagman.semanticObservationStream.latestSettledObservationInvalidated)
        XCTAssertNil(bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Timeout"))).resolvedElement)
        XCTAssertEqual(
            bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Settled"))).resolvedElement?.element.label,
            "Settled"
        )
    }

    func testObservedEvidenceUpdatesVisibleWorldWithoutReplacingSettledTruth() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let observed = InterfaceObservation.makeForTests(elements: [(element(label: "Observed"), "observed")])
        bagman.recordParsedObservedEvidence(observed)

        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertEqual(bagman.latestObservation.tree.orderedElements.first?.element.label, "Observed")
        XCTAssertNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Observed"))).resolvedElement)
        XCTAssertNil(bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Observed"))).resolvedElement)
        XCTAssertEqual(bagman.viewportElementIDs, ["observed"])
    }

    func testLiveVisibleEntriesUseFreshObservedRevealMetadataOverSettledCache() throws {
        let row = element(label: "Row", traits: .button)
        let containerPath = TreePath([0])
        let rowPath = TreePath([0, 0])
        let scrollContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )
        let staleEntry = InterfaceTree.Element(
            heistId: "row",
            path: rowPath,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: 100),
            element: row
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(InterfaceObservation.makeForTests(
            elements: ["row": staleEntry],
            hierarchy: [.container(scrollContainer, children: [])],
            firstResponderHeistId: nil,
        ))

        let freshEntry = InterfaceTree.Element(
            heistId: "row",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: 500),
            element: row
        )
        bagman.recordParsedObservedEvidence(InterfaceObservation.makeForTests(
            elements: ["row": freshEntry],
            hierarchy: [.container(scrollContainer, children: [.element(row, traversalIndex: 0)])],
            heistIdsByPath: [rowPath: "row"],
            firstResponderHeistId: nil,
        ))

        XCTAssertEqual(bagman.latestObservation.tree.findElement(heistId: "row")?.scrollMembership?.index, 500)
        XCTAssertEqual(try XCTUnwrap(bagman.liveInterfaceElement(heistId: "row")).scrollMembership?.index, 500)
    }

    func testLiveVisibleEntriesDoNotPreserveSettledRevealMetadataWhenFreshObservationHasNone() throws {
        let row = element(label: "Row", traits: .button)
        let staleEntry = InterfaceTree.Element(
            heistId: "row",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: row
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(InterfaceObservation.makeForTests(
            elements: ["row": staleEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        ))

        let freshEntry = InterfaceTree.Element(
            heistId: "row",
            scrollMembership: nil,
            element: row
        )
        bagman.recordParsedObservedEvidence(InterfaceObservation.makeForTests(
            elements: ["row": freshEntry],
            hierarchy: [.element(row, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): "row"],
            firstResponderHeistId: nil,
        ))

        XCTAssertNil(bagman.latestObservation.tree.findElement(heistId: "row")?.scrollMembership)
        XCTAssertNil(try XCTUnwrap(bagman.liveInterfaceElement(heistId: "row")).scrollMembership)
    }

    func testCancelledNoScreenSettleDoesNotPublishSettledTruth() async {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)
        let sequence = bagman.semanticObservationStream.latestObservation?.sequence

        let outcome = SettleSession.Result(
            outcome: .cancelled(timeMs: 1),
            events: [],
            finalObservation: nil,
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )

        XCTAssertEqual(result.settle.outcome, .cancelled(timeMs: 1))
        guard case .unavailable = result.result else {
            return XCTFail("Expected cancelled settle to return unavailable evidence")
        }
        XCTAssertEqual(bagman.semanticObservationStream.latestObservation?.sequence, sequence)
        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence)
        XCTAssertTrue(bagman.semanticObservationStream.latestSettledObservationInvalidated)
    }

}

private func containsLiveTripwireIdentity(_ value: Any) -> Bool {
    if value is ObjectIdentifier || value is TheTripwire.TripwireSignal {
        return true
    }
    return Mirror(reflecting: value).children.contains {
        containsLiveTripwireIdentity($0.value)
    }
}

#endif
