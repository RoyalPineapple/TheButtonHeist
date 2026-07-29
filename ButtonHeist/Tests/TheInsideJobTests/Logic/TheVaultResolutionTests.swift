#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheVaultResolutionTests: XCTestCase {

    var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
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
    func register(_ element: AccessibilityElement, heistId: HeistId, index: Int) async {
        hierarchyNodes.append(.element(element, traversalIndex: index))
        registeredEntries.append((element, heistId, true))
        await rebuildObservation()
    }

    /// Element registration that only adds the leaf to the heistId→entry map
    /// without putting it in the live hierarchy. Known entries return nil from
    /// visible-scoped accessors but still participate in semantic target
    /// resolution.
    func registerOffScreen(_ element: AccessibilityElement, heistId: HeistId) async {
        registeredEntries.append((element, heistId, false))
        await rebuildObservation()
    }

    private func rebuildObservation() async {
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
                geometry: testGeometry(
                    for: entry.element,
                    ownerPath: .root,
                    screen: entry.isLive
                        ? TheVault.onscreenSpace(for: entry.element)
                        : .offscreen
                ),
                element: entry.element
            )
            elements[entry.heistId] = treeElement
        }
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: elements,
            hierarchy: hierarchyNodes,
            heistIdsByPath: heistIdsByPath,
            firstResponderHeistId: nil,
        ))
    }

    func installMatchingScreen() async {
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
        await vault.installObservationForTesting(observation)
    }

    func resolvedTarget(_ authored: AccessibilityTarget) throws -> ResolvedAccessibilityTarget {
        try authored.resolve(in: .empty)
    }

    func resolvedPredicate(_ authored: AccessibilityTarget) throws -> ResolvedElementPredicate {
        guard case .predicate(let predicate, ordinal: nil) = try resolvedTarget(authored) else {
            return try XCTUnwrap(nil as ResolvedElementPredicate?, "Expected an unqualified element predicate")
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

    func testSemanticObservationSubscriptionsCoalesceToWidestScope() async {
        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)

        let visible = vault.semanticObservationStream.subscribe(scope: .visible)
        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)

        do {
            let discovery = vault.semanticObservationStream.subscribe(scope: .discovery)
            XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .discovery)
            _ = discovery
        }

        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)
        _ = visible
    }

    func testActiveObservationDemandChangesCadenceWithoutWideningScope() async {
        XCTAssertFalse(vault.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(vault.semanticObservationStream.activeObservationDemandCount, 0)
        XCTAssertEqual(vault.semanticObservationStream.activeObservationDemandState, .idle)
        XCTAssertEqual(vault.semanticObservationStream.tickDemand, .ambient)
        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)

        let demand = vault.semanticObservationStream.beginActiveObservationDemand()
        XCTAssertTrue(vault.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(vault.semanticObservationStream.activeObservationDemandCount, 1)
        XCTAssertEqual(vault.semanticObservationStream.activeObservationDemandState, .active)
        XCTAssertEqual(vault.semanticObservationStream.tickDemand, .immediate)
        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)

        do {
            let discovery = vault.semanticObservationStream.subscribe(scope: .discovery)
            XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .discovery)
            _ = discovery
        }

        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)

        demand.cancel()

        XCTAssertFalse(vault.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(vault.semanticObservationStream.activeObservationDemandCount, 0)
        XCTAssertEqual(vault.semanticObservationStream.activeObservationDemandState, .idle)
        XCTAssertEqual(vault.semanticObservationStream.tickDemand, .ambient)
        XCTAssertEqual(vault.semanticObservationStream.subscribedObservationScope(), .visible)
    }

    func testInterfaceTreeKeepsLiveEvidenceOutOfTreeState() async {
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        let observation = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        let tree = InterfaceTree.empty.updatingViewport(with: observation.tree)

        XCTAssertTrue(observation.liveCapture.object(for: "save") === liveObject)
        XCTAssertNil(LiveCapture.makeForTests(snapshot: tree.viewportCapture).object(for: "save"))
        XCTAssertEqual(tree.findElement(heistId: "save")?.element.label, "Save")
    }

    func testInterfaceTreeViewportUpdateDropsDiscoveryMemoryAfterNavigation() async {
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
        let updated = tree.updatingViewport(with: refreshedTop.tree)

        XCTAssertEqual(updated.viewportElementIDs, ["shared_row"])
        XCTAssertEqual(updated.elementIDs, ["shared_row"])
        XCTAssertEqual(updated.findElement(heistId: "shared_row")?.element.label, "Fresh Row")
        XCTAssertNil(updated.findElement(heistId: "bottom_row"))
    }

    func testInterfaceTreeViewportUpdateKeepsDiscoveryMemoryWhenViewportIdentityPairsWithNewId() async {
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
            with: InterfaceObservation.makeForTests(elements: [(currentVisible, "counter_new")]).tree
        )

        XCTAssertEqual(updated.viewportElementIDs, ["counter_new"])
        XCTAssertEqual(updated.elementIDs, ["counter_new", "details"])
        XCTAssertNil(updated.findElement(heistId: "counter_old"))
        XCTAssertEqual(updated.findElement(heistId: "details")?.element.label, "Details")
    }

}

@MainActor
extension TheVaultResolutionTests {

    func testVisiblePublicationsAdvanceHistoryMonotonically() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        let firstPublication = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(first)

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        let secondPublication = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(second)

        XCTAssertEqual(
            firstPublication.historyRange.upperBound,
            secondPublication.historyRange.lowerBound
        )
        XCTAssertEqual(
            secondPublication.current.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Second"]
        )
    }

    func testSemanticSnapshotRetainsFirstResponderAsAuthoredTarget() async throws {
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

        let publication = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)
        let firstResponder = try XCTUnwrap(publication.current.snapshot.context.firstResponder)

        XCTAssertEqual(firstResponder, AccessibilityTarget.label("Email"))
        XCTAssertFalse(containsLiveTripwireIdentity(publication.current.snapshot))
    }

    func testSemanticPublicationContainsNoLiveTripwireIdentity() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Home"), "home")])

        let publication = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)

        XCTAssertFalse(containsLiveTripwireIdentity(publication))
    }

    func testSettledVisibleCommitUpdatesSemanticTruth() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])

        await vault.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertEqual(vault.interfaceTree.orderedElements.first?.element.label, "Settled")
    }

    func testObservationEvidenceCarriesBaselineCurrentAndOrderedEvents() async {
        let first = InterfaceObservation.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
        ])
        let firstPublication = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(first)
        let boundary = await vault.semanticObservationStream.stateOwner
            .observationBoundary(scope: .visible)

        let second = InterfaceObservation.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
            (element(label: "Toast"), "toast"),
        ])
        let secondPublication = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(second)
        let evidence = await vault.semanticObservationStream.stateOwner
            .evidence(after: boundary)

        XCTAssertEqual(evidence.baseline, firstPublication.current.snapshot)
        XCTAssertEqual(evidence.current, secondPublication.current.snapshot)
        XCTAssertEqual(evidence.events, secondPublication.events)
        XCTAssertEqual(evidence.completeness, .complete)
        XCTAssertEqual(
            evidence.baseline?.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Home"]
        )
        XCTAssertEqual(
            evidence.current?.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Home", "Toast"]
        )
        guard case .elementsChanged(let currentSnapshot)? = evidence.events.last else {
            return XCTFail("Expected the final event to carry current semantic truth")
        }
        XCTAssertEqual(currentSnapshot, evidence.current)
    }

    func testVisiblePublicationCarriesCanonicalCommittedGraph() async {
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
        await vault.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let refreshedVisible = InterfaceObservation.makeForTests(elements: [(visible, "custom_rotors")])
        let publication = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(refreshedVisible)

        XCTAssertEqual(publication.current.scope, .visible)
        XCTAssertEqual(vault.interfaceElementIDs, ["buttonheist_demo", "custom_rotors"])
        XCTAssertEqual(
            publication.current.snapshot.interface.projectedElements
                .compactMap(\.semantics.assertable.label),
            ["Custom Rotors", "ButtonHeist Demo"]
        )
        XCTAssertEqual(publication.events.last, .noChange)
    }

    func testObservedEvidenceUpdatesVisibleWorldWithoutReplacingSettledTruth() async {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        await vault.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let observed = InterfaceObservation.makeForTests(elements: [(element(label: "Observed"), "observed")])
        vault.observeInterface(observed)

        XCTAssertEqual(vault.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertEqual(vault.latestObservation.tree.orderedElements.first?.element.label, "Observed")
        XCTAssertNil(vault.resolveTarget(literalTarget(ResolvedElementPredicate.label("Observed"))).resolvedElement)
        XCTAssertNil(vault.resolveVisibleTarget(literalTarget(ResolvedElementPredicate.label("Observed"))).resolvedElement)
        XCTAssertEqual(vault.viewportElementIDs, ["observed"])
    }

    func testLiveVisibleEntriesUseFreshObservedRevealMetadataOverSettledCache() async throws {
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
            geometry: testGeometry(
                for: row,
                ownerPath: containerPath,
                screen: TheVault.onscreenSpace(for: row)
            ),
            element: row
        )
        await vault.semanticObservationStream.commitDiscoveryObservationForTesting(InterfaceObservation.makeForTests(
            elements: ["row": staleEntry],
            hierarchy: [.container(scrollContainer, children: [])],
            firstResponderHeistId: nil,
        ))

        let freshEntry = InterfaceTree.Element(
            heistId: "row",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: 500),
            geometry: testGeometry(
                for: row,
                ownerPath: containerPath,
                screen: TheVault.onscreenSpace(for: row)
            ),
            element: row
        )
        vault.observeInterface(InterfaceObservation.makeForTests(
            elements: ["row": freshEntry],
            hierarchy: [.container(scrollContainer, children: [.element(row, traversalIndex: 0)])],
            heistIdsByPath: [rowPath: "row"],
            firstResponderHeistId: nil,
        ))

        XCTAssertEqual(vault.latestObservation.tree.findElement(heistId: "row")?.scrollMembership?.index, 500)
        XCTAssertEqual(try XCTUnwrap(vault.liveInterfaceElement(heistId: "row")).scrollMembership?.index, 500)
    }

    func testLiveVisibleEntriesDoNotPreserveSettledRevealMetadataWhenFreshObservationHasNone() async throws {
        let row = element(label: "Row", traits: .button)
        let staleEntry = InterfaceTree.Element(
            heistId: "row",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: nil),
            geometry: testGeometry(
                for: row,
                ownerPath: TreePath([0]),
                screen: TheVault.onscreenSpace(for: row)
            ),
            element: row
        )
        await vault.semanticObservationStream.commitDiscoveryObservationForTesting(InterfaceObservation.makeForTests(
            elements: ["row": staleEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        ))

        let freshEntry = InterfaceTree.Element(
            heistId: "row",
            scrollMembership: nil,
            geometry: testGeometry(
                for: row,
                ownerPath: .root,
                screen: TheVault.onscreenSpace(for: row)
            ),
            element: row
        )
        vault.observeInterface(InterfaceObservation.makeForTests(
            elements: ["row": freshEntry],
            hierarchy: [.element(row, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): "row"],
            firstResponderHeistId: nil,
        ))

        XCTAssertNil(vault.latestObservation.tree.findElement(heistId: "row")?.scrollMembership)
        XCTAssertNil(try XCTUnwrap(vault.liveInterfaceElement(heistId: "row")).scrollMembership)
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
