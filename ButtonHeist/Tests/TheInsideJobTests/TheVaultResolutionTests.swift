#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheVaultResolutionTests: XCTestCase {

    private var bagman: TheVault!

    override func setUp() async throws {
        bagman = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        bagman.semanticObservationStream.stop()
        bagman = nil
    }

    // MARK: - Helpers

    private var nextElementYOffset: CGFloat = 0

    private func element(
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
    private func register(_ element: AccessibilityElement, heistId: HeistId, index: Int) {
        hierarchyNodes.append(.element(element, traversalIndex: index))
        registeredEntries.append((element, heistId, true))
        rebuildObservation()
    }

    /// Element registration that only adds the leaf to the heistId→entry map
    /// without putting it in the live hierarchy. Known entries return nil from
    /// visible-scoped accessors but still participate in semantic target
    /// resolution.
    private func registerOffScreen(_ element: AccessibilityElement, heistId: HeistId) {
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

    private func installMatchingScreen() {
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

    private func resolvedTarget(_ authored: AccessibilityTarget) throws -> ResolvedAccessibilityTarget {
        try authored.resolve(in: .empty)
    }

    private func resolvedPredicate(_ authored: AccessibilityTarget) throws -> ElementPredicate {
        guard case .predicate(let predicate, ordinal: nil) = try resolvedTarget(authored) else {
            return try XCTUnwrap(nil as ElementPredicate?, "Expected an unqualified element predicate")
        }
        return predicate
    }

    // MARK: - Settled Semantic Observation

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

        let outcome = SettleSession.Outcome(
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

    func testAccessibilityNotificationObjectIdentityRequiresLivePayload() {
        var payloadObject: NSObject? = NSObject()
        let identity = AccessibilityNotificationObjectIdentity(
            object: payloadObject!,
            className: "NSObject",
            summary: nil
        )
        payloadObject = nil

        let screenObject = NSObject()
        let observation = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": screenObject]
        )
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(identity),
            associatedElement: .none,
            provenance: .scoped
        )

        let evidence = bagman.resolveAccessibilityNotificationEvidence([event], in: observation)

        XCTAssertEqual(
            evidence.first?.notificationData,
            .unresolvedObject(AccessibilityNotificationObjectPayload(className: "NSObject", summary: nil))
        )
    }

    func testAccessibilityNotificationObjectIdentityResolvesIntoReferenceScreen() {
        let payloadObject = NSObject()
        let source = InterfaceObservation.makeForTests([
            .init(element(label: "Old", traits: .button), heistId: "old"),
            .init(element(label: "A acid", traits: .button), heistId: "a_acid", object: payloadObject),
        ])
        let reference = InterfaceObservation.makeForTests(elements: [
            (element(label: "Section A", traits: .header), "section_a_header"),
            (element(label: "A acid", traits: .button), "a_acid"),
        ])
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(AccessibilityNotificationObjectIdentity(
                object: payloadObject,
                className: "NSObject",
                summary: nil
            )),
            associatedElement: .none,
            provenance: .scoped
        )

        let evidence = bagman.resolveAccessibilityNotificationEvidence(
            [event],
            identityObservation: source,
            referenceObservation: reference
        )

        guard case .element(let reference)? = evidence.first?.notificationData else {
            return XCTFail("Expected notification object to resolve into reference observation")
        }
        XCTAssertEqual(reference.path, TreePath([1]))
        XCTAssertEqual(reference.traversalIndex, 1)
    }

    func testAccessibilityNotificationReferenceUsesNestedSemanticGraphPath() {
        let payloadObject = NSObject()
        let target = element(label: "Pay", traits: .button)
        let source = InterfaceObservation.makeForTests([
            .init(target, heistId: "pay", object: payloadObject),
        ])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: nil, value: nil),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let reference = InterfaceObservation.makeForTests(
            elements: [
                "pay": InterfaceTree.Element(heistId: "pay", scrollMembership: nil, element: target),
            ],
            hierarchy: [.container(container, children: [.element(target, traversalIndex: 0)])],
            heistIdsByPath: [TreePath([0, 0]): "pay"],
            firstResponderHeistId: nil
        )
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(AccessibilityNotificationObjectIdentity(
                object: payloadObject,
                className: "NSObject",
                summary: nil
            )),
            associatedElement: .none,
            provenance: .scoped
        )

        let evidence = bagman.resolveAccessibilityNotificationEvidence(
            [event],
            identityObservation: source,
            referenceObservation: reference
        )

        guard case .element(let resolved)? = evidence.first?.notificationData else {
            return XCTFail("Expected nested notification element reference")
        }
        XCTAssertEqual(resolved.path, TreePath([0, 0]))
        XCTAssertEqual(resolved.traversalIndex, 0)
    }

    func testScreenChangedAfterActionBatchCaptureInvalidatesCommittedObservation() async throws {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Checkout"), "checkout")])
        let action = bagman.accessibilityNotifications.beginActionWindow()
        let batch = try XCTUnwrap(action.capture())
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )

        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation, notificationBatch: batch)
        action.cancel()

        let served = await bagman.semanticObservationStream.settledEvent(
            scope: .visible,
            after: nil,
            timeout: 0
        )
        XCTAssertNil(served)
    }

    func testDiscoveryObservationHonorsExplicitCursorWhenNextEventAlreadyExists() async throws {
        let baseline = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Baseline"), "baseline")])
        )
        let current = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Current"), "current")])
        )

        let served = await bagman.semanticObservationStream.settledEvent(
            scope: .discovery,
            after: baseline.sequence,
            timeout: 0.1
        )

        XCTAssertEqual(try XCTUnwrap(served).sequence, current.sequence)
    }

    func testNotificationOverflowIsExplicitInCommittedTrace() async throws {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let action = bagman.accessibilityNotifications.beginActionWindow()
        for _ in 0..<65 {
            bagman.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: .none,
                associatedElement: .none
            )
        }
        let batch = try XCTUnwrap(action.capture())

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(
            observation,
            notificationBatch: batch
        )
        action.cancel()

        XCTAssertEqual(
            event.trace.captures.last?.transition.accessibilityNotificationGap,
            AccessibilityNotificationGap(droppedThroughSequence: 1)
        )
    }

    func testCommittedTraceRetainsFirstResponderAsDurableTarget() {
        let observation = InterfaceObservation.makeForTests(
            [
                .init(label: "Email", heistId: "email", traits: .textEntry),
                .init(label: "Continue", heistId: "continue", traits: .button),
            ],
            firstResponderHeistId: "email"
        )

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertNotNil(event.trace.captures.last?.context.firstResponder)
        XCTAssertEqual(event.settledObservation.observation.liveCapture.firstResponderHeistId, "email")
    }

    func testFailedSettlePreservesScreenChangedForNextIdenticalCommit() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)
        let firstHeist = bagman.accessibilityNotifications.beginHeistScope()
        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        _ = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome,
            notificationWindow: action
        )
        firstHeist.cancel()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )

        XCTAssertEqual(
            bagman.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .all
            ).events.map(\.provenance),
            [.scoped, .ambient]
        )

        let secondHeist = bagman.accessibilityNotifications.beginHeistScope()
        defer { secondHeist.cancel() }
        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertNotEqual(secondEvent.generation, firstEvent.generation)
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.sequence),
            [1]
        )
        XCTAssertEqual(
            secondEvent.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testAmbientScreenChangedBetweenHeistScopesDoesNotStartGeneration() {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)
        let firstHeist = bagman.accessibilityNotifications.beginHeistScope()
        firstHeist.cancel()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let secondHeist = bagman.accessibilityNotifications.beginHeistScope()
        defer { secondHeist.cancel() }

        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertEqual(secondEvent.generation, firstEvent.generation)
        XCTAssertTrue(secondEvent.trace.captures.last?.transition.accessibilityNotifications.isEmpty == true)
        XCTAssertTrue(secondEvent.trace.changeFacts.isEmpty)
    }

    func testCleanPostActionSettleRequiresActionWindowToClaimAccessibilityNotifications() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.recordParsedObservedEvidence(observation)
        bagman.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let outcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )

        guard case .committed(let event) = result.result else {
            return XCTFail("Expected clean settle to commit")
        }
        XCTAssertEqual(event.trace.captures.last?.transition.accessibilityNotifications, [])
        XCTAssertEqual(
            bagman.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .all
            ).events.map(\.kind),
            [.announcement]
        )
    }

    func testCleanSettleProofCarriesTheExactSettledObservation() throws {
        let stableElement = element(label: "Stable")
        let settled = InterfaceObservation.makeForTests(elements: [(stableElement, "stable")])
        let finalObservation = SettleSessionFinalObservation(observation: settled)
        let outcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: finalObservation,
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )
        bagman.recordParsedObservedEvidence(settled)

        let replacement = InterfaceObservation.makeForTests(elements: [(stableElement, "stable")])
        XCTAssertEqual(replacement.tree, settled.tree)
        XCTAssertEqual(replacement.liveCapture.snapshot, settled.liveCapture.snapshot)
        XCTAssertNotEqual(replacement.captureToken, settled.captureToken)
        bagman.recordParsedObservedEvidence(replacement)

        let proof = try XCTUnwrap(InterfaceObservationProof.settled(outcome))
        XCTAssertEqual(proof.observation.captureToken, settled.captureToken)
        XCTAssertNotEqual(proof.observation.captureToken, replacement.captureToken)
    }

    func testViewportMovementLineageRequiresDedicatedProofConstructor() throws {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.recordParsedObservedEvidence(observation)
        let outcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        let ordinary = try XCTUnwrap(InterfaceObservationProof.settled(outcome))
        let afterMovement = try XCTUnwrap(
            InterfaceObservationProof.settled(
                outcome,
                lineageEvidence: .viewportMovement
            )
        )

        XCTAssertNil(ordinary.lineageEvidence)
        XCTAssertEqual(afterMovement.lineageEvidence, .viewportMovement)
    }

    func testRecaptureOnlyValueChangedNotificationProducesNotificationFact() async throws {
        let observation = InterfaceObservation.makeForTests(elements: [
            (element(label: "Volume", value: "50%", traits: .adjustable), "volume"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: SettleSession.Outcome(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: observation),
                elementsByKey: [:],
                tripwireSignal: bagman.tripwire.tripwireSignal()
            ),
            notificationWindow: action
        )

        guard case .committed(let event) = result.result else {
            return XCTFail("Expected clean settle to commit")
        }
        XCTAssertEqual(
            event.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.elementChanged(.value)]
        )
        XCTAssertEqual(event.trace.changeFacts.count, 1)
        guard case .elementsChanged(let fact)? = event.trace.changeFacts.first else {
            return XCTFail("Expected notification-only elementsChanged fact")
        }
        XCTAssertTrue(fact.isNotificationOnly)
        XCTAssertEqual(fact.metadata.accessibilityNotifications.map(\.kind), [.elementChanged(.value)])
    }

    func testValueChangedNotificationRequiresAccessibilityValueChangeForElementDelta() async throws {
        let before = InterfaceObservation.makeForTests(elements: [
            (element(label: "Volume", value: "50%", traits: .adjustable), "volume"),
        ])
        let after = InterfaceObservation.makeForTests(elements: [
            (element(label: "Volume", value: "75%", traits: .adjustable), "volume"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(before)
        bagman.recordParsedObservedEvidence(after)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: SettleSession.Outcome(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: after),
                elementsByKey: [:],
                tripwireSignal: bagman.tripwire.tripwireSignal()
            ),
            notificationWindow: action
        )

        guard case .committed(let event) = result.result else {
            return XCTFail("Expected clean settle to commit")
        }
        XCTAssertEqual(
            event.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.elementChanged(.value)]
        )
        XCTAssertEqual(event.trace.changeFacts.count, 1)
        guard case .elementsChanged(let fact)? = event.trace.changeFacts.first else {
            return XCTFail("Expected value edit to drive elementsChanged")
        }
        XCTAssertEqual(fact.metadata.accessibilityNotifications.map(\.kind), [.elementChanged(.value)])
        let change = try XCTUnwrap(fact.updated.first?.changes.first)
        XCTAssertEqual(change.property, .value)
        XCTAssertEqual(change.oldDisplayText, "50%")
        XCTAssertEqual(change.newDisplayText, "75%")
    }

    func testAnnouncementNotificationIsPreservedOutsideInterfaceChangeFacts() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Saved" as NSString),
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: SettleSession.Outcome(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: observation),
                elementsByKey: [:],
                tripwireSignal: bagman.tripwire.tripwireSignal()
            ),
            notificationWindow: action
        )

        guard case .committed(let event) = result.result else {
            return XCTFail("Expected clean settle to commit")
        }
        XCTAssertEqual(event.trace.capturedAnnouncements.map(\.text), ["Saved"])
        XCTAssertEqual(event.trace.captures.last?.transition.accessibilityNotifications.map(\.kind), [.announcement])
        XCTAssertTrue(event.trace.changeFacts.isEmpty)
    }

    func testScreenChangedNotificationStartsGenerationAndPreservesBoundaryFacts() throws {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "Menu", traits: .header), "menu")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let action = bagman.accessibilityNotifications.beginActionWindow()
        defer { action.cancel() }
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let notificationBatch = try XCTUnwrap(action.capture())
        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Checkout", traits: .header), "checkout")])

        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(
            second,
            notificationBatch: notificationBatch
        )

        XCTAssertNotEqual(secondEvent.generation, firstEvent.generation)
        XCTAssertEqual(secondEvent.previous?.sequence, firstEvent.sequence)
        XCTAssertEqual(secondEvent.previousCursor, firstEvent.cursor)
        XCTAssertEqual(secondEvent.trace.captures.count, 2)

        let baseline = try XCTUnwrap(firstEvent.settledCapture)
        let window = try XCTUnwrap(bagman.semanticObservationStream.observationWindow(
            from: baseline,
            through: secondEvent
        ))
        XCTAssertEqual(window.completeness, .complete)
        XCTAssertEqual(
            window.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testDiscoveryCommitClassifiesAgainstLatestVisibleWithoutCrossScopeLineage() {
        let visible = InterfaceObservation.makeForTests(elements: [
            (element(label: "Menu", traits: .header), "menu"),
        ])
        let visibleEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(visible)
        let discoveryHeader = element(label: "Checkout", traits: .header)
        let discovery = InterfaceObservation.makeForTests(elements: [(discoveryHeader, "checkout")])

        let discoveryEvent = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        XCTAssertNotEqual(discoveryEvent.generation, visibleEvent.generation)
        XCTAssertNil(discoveryEvent.previous)
    }

    func testPostActionFailedSettlePreservesPendingAccessibilityNotificationsDuringHeistScope() async {
        let heist = bagman.accessibilityNotifications.beginHeistScope()
        defer { heist.cancel() }

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Unstable"), "unstable")])
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        _ = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome,
            notificationWindow: action
        )

        XCTAssertEqual(
            bagman.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .all
            ).events.map(\.kind),
            [.announcement],
            "Action attribution must not consume retained notification history."
        )
    }

    func testPostActionFailedSettleReturnsObservedUnsettledEvidenceInsteadOfBaseline() async {
        let object = NSObject()
        let observation = InterfaceObservation.makeForTests([
            .init(element(label: "Unstable"), heistId: "unstable", object: object),
        ])
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )

        guard case .observedUnsettled(let observedTree, _) = result.result else {
            return XCTFail("Expected observed unsettled settle evidence")
        }
        XCTAssertEqual(observedTree.orderedElements.first?.element.label, "Unstable")
        XCTAssertEqual(
            bagman.latestFailedSettleDiagnosticEvidence?.tree.orderedElements.first?.element.label,
            "Unstable"
        )
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence?.liveCapture.object(for: "unstable"))
        XCTAssertTrue(bagman.semanticObservationStream.latestSettledObservationInvalidated)
    }

    func testPublicInterfaceReadsSettledTruthNotFailedSettleDiagnosticEvidence() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(bagman.interface().projectedElements.compactMap(\.label), ["Settled"])
        XCTAssertEqual(bagman.semanticInterface().projectedElements.compactMap(\.label), ["Settled"])
        XCTAssertNil(bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Timeout"))).resolvedElement)
    }

    func testRejectedSettleDiagnosticDoesNotReplaceNewerParsedObservation() async {
        let objectA = NSObject()
        let objectB = NSObject()
        let screenA = InterfaceObservation.makeForTests([
            .init(element(label: "A"), heistId: "a", object: objectA),
        ])
        let screenB = InterfaceObservation.makeForTests([
            .init(element(label: "B"), heistId: "b", object: objectB),
        ])
        let rejectedOutcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: screenA),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )
        bagman.recordParsedObservedEvidence(screenA)
        bagman.recordParsedObservedEvidence(screenB)

        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: rejectedOutcome
        )

        guard case .unavailable = result.result else {
            return XCTFail("Expected stale settle proof to be rejected")
        }
        XCTAssertEqual(bagman.latestObservation.captureToken, screenB.captureToken)
        XCTAssertTrue(bagman.latestObservation.liveCapture.object(for: "b") === objectB)
        XCTAssertNil(bagman.latestObservation.liveCapture.object(for: "a"))
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.tree, screenA.tree)
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence?.liveCapture.object(for: "a"))
    }
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

    func testPublicInterfaceProjectionStaysVisibleWhileSemanticProjectionIncludesKnownElements() throws {
        let visible = element(label: "Visible", traits: .button)
        let known = element(label: "Known", traits: .button)
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 800)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 400))
        )
        let observation = InterfaceObservation.makeForTests(
            elements: [
                "visible": InterfaceTree.Element(heistId: "visible", scrollMembership: nil, element: visible),
                "known": InterfaceTree.Element(heistId: "known", scrollMembership: nil, element: known),
            ],
            hierarchy: [.container(container, children: [.element(visible, traversalIndex: 0)])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            heistIdsByPath: [TreePath([0, 0]): "visible"],
            firstResponderHeistId: nil,
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(observation)

        let publicInterface = bagman.interface()
        let semanticInterface = bagman.semanticInterface()

        XCTAssertEqual(publicInterface.projectedElements.map(\.label), ["Visible"])
        XCTAssertEqual(semanticInterface.projectedElements.compactMap(\.label).sorted(), ["Known", "Visible"])
        guard case .container(_, let children) = publicInterface.tree.first else {
            return XCTFail("Expected public interface to preserve visible container hierarchy")
        }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(publicInterface.annotations.containers.first?.containerName, "main_scroll")
        XCTAssertEqual(semanticInterface.annotations.containers.first?.containerName, "main_scroll")
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

    func testContainerTargetResolutionUsesCommittedSemanticContainers() throws {
        let path = TreePath([0, 1])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(CGRect(x: 0, y: 900, width: 240, height: 80)),
            customActions: [.init(name: "Archive")]
        )
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    path: .init(
                        container: container,
                        path: path,
                        containerName: "semantic_actions__actions",
                        contentFrame: CGRect(x: 0, y: 900, width: 240, height: 80)
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests()
        ))

        let result = bagman.resolveTarget(try resolvedTarget(
            .container(.identifier("actions"))
        ))
        switch result {
        case .resolved(.container(let resolved)):
            XCTAssertEqual(resolved.path, path)
            XCTAssertEqual(resolved.containerName, "semantic_actions__actions")
            XCTAssertEqual(resolved.contentFrame?.origin.y, 900)
        case .resolved(.element), .notFound, .ambiguous:
            XCTFail("Expected semantic container resolution, got \(result.diagnostics)")
        }
    }

    func testContainerTargetResolutionReportsStructuredFacts() throws {
        let primaryPath = TreePath([0, 1])
        let secondaryPath = TreePath([0, 2])
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    primaryPath: .init(
                        container: AccessibilityContainer(
                            type: .semanticGroup(label: "Actions", value: nil), identifier: "primary",
                            frame: AccessibilityRect(CGRect(x: 0, y: 120, width: 240, height: 80))
                        ),
                        path: primaryPath,
                        containerName: "actions_primary",
                        contentFrame: CGRect(x: 0, y: 120, width: 240, height: 80)
                    ),
                    secondaryPath: .init(
                        container: AccessibilityContainer(
                            type: .semanticGroup(label: "Actions", value: nil), identifier: "secondary",
                            frame: AccessibilityRect(CGRect(x: 0, y: 240, width: 240, height: 80))
                        ),
                        path: secondaryPath,
                        containerName: "actions_secondary",
                        contentFrame: CGRect(x: 0, y: 240, width: 240, height: 80)
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests()
        ))

        let predicate = ContainerPredicate.matching(
            .type(.semanticGroup),
            .semantic(.label("Actions"))
        )
        let ambiguous = bagman.resolveTarget(try resolvedTarget(
            .container(predicate)
        ))
        guard case .ambiguous(let facts) = ambiguous else {
            XCTFail("Expected structured ambiguity, got \(ambiguous)")
            return
        }
        XCTAssertEqual(facts.matchedCount, 2)
        XCTAssertEqual(facts.resolutionScope, .interface)
        let ambiguousMatches = try XCTUnwrap(facts.containerMatches)
        XCTAssertEqual(
            ambiguousMatches.exactMatches.map { $0.container.containerPredicateFacts.identifier },
            ["primary", "secondary"]
        )
        XCTAssertEqual(ambiguousMatches.exactMatches.map(\.containerName), ["actions_primary", "actions_secondary"])
        XCTAssertTrue(ambiguous.diagnostics.contains("container target is ambiguous across 2 containers"))
        XCTAssertFalse(ambiguous.diagnostics.contains("containerName"))

        let outOfRange = bagman.resolveTarget(try resolvedTarget(
            .container(predicate, ordinal: 3)
        ))
        guard case .notFound(let notFoundFacts) = outOfRange else {
            XCTFail("Expected structured ordinal miss, got \(outOfRange)")
            return
        }
        XCTAssertEqual(notFoundFacts.reason, .ordinalOutOfRange(requested: 3, matchCount: 2))
        XCTAssertEqual(notFoundFacts.resolutionScope, .interface)
        XCTAssertEqual(notFoundFacts.containerMatches?.exactMatches.map(\.path), [primaryPath, secondaryPath])
        XCTAssertTrue(outOfRange.diagnostics.contains("container target ordinal 3"))
        XCTAssertTrue(outOfRange.diagnostics.contains("target an element inside the intended region"))
    }

    func testGeneratedConcreteTargetUsesMinimumPredicateSelector() throws {
        let selected = element(label: "Mode", value: "A", traits: [.button, .selected])
        let other = element(label: "Mode", value: "B", traits: [.button, .selected])
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (selected, "mode_a"),
            (other, "mode_b"),
        ]))

        let treeElement = try XCTUnwrap(bagman.interfaceElement(heistId: "mode_a"))

        XCTAssertEqual(
            bagman.minimumUniqueTarget(for: treeElement),
            AccessibilityTarget.element(
                .label("Mode"),
                .traits([.button]),
                .value("A")
            )
        )
    }

    // MARK: - Live Geometry Replay

    func testMatcherTargetAcquiresFreshLiveGeometry() throws {
        let sourceFrame = CGRect(x: 10, y: 20, width: 80, height: 44)
        let sourcePoint = CGPoint(x: 50, y: 42)
        let freshFrame = CGRect(x: 120, y: 240, width: 80, height: 44)
        let freshPoint = CGPoint(x: 160, y: 262)
        let currentElement = AccessibilityElement.make(
            label: "Quantity",
            value: "1",
            identifier: "quantity_stepper",
            traits: .adjustable,
            shape: .frame(AccessibilityRect(freshFrame)),
            activationPoint: freshPoint
        )
        let object = UIAccessibilityElement(accessibilityContainer: NSObject())
        object.accessibilityFrame = sourceFrame
        object.accessibilityActivationPoint = sourcePoint
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [(currentElement, "quantity_1")],
            objects: ["quantity_1": object]
        ))

        let executableTarget = AccessibilityTarget.element(.identifier("quantity_stepper"))

        guard case .predicate(let matcher, let ordinal) = executableTarget else {
            XCTFail("Expected semantic replay target to carry matcher identity, got \(executableTarget)")
            return
        }
        XCTAssertEqual(matcher.checks, [.identifier(.exact("quantity_stepper"))])
        XCTAssertNil(ordinal)

        guard let resolved = bagman.resolveTarget(try resolvedTarget(executableTarget)).resolvedElement else {
            XCTFail("Expected semantic replay selector to resolve against current observation")
            return
        }
        XCTAssertEqual(resolved.heistId, "quantity_1")

        guard case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Expected current accessibility capture to provide action geometry")
            return
        }
        XCTAssertEqual(liveTarget.frame, freshFrame)
        XCTAssertEqual(liveTarget.activationPoint, freshPoint)
        XCTAssertNotEqual(liveTarget.frame, object.accessibilityFrame)
        XCTAssertNotEqual(liveTarget.activationPoint, object.accessibilityActivationPoint)
        XCTAssertNotEqual(liveTarget.frame, sourceFrame)
        XCTAssertNotEqual(liveTarget.activationPoint, sourcePoint)
    }

    func testVisibleResolutionKeepsSettledSemanticsWhileLiveTargetUsesFreshGeometry() throws {
        let staleFrame = CGRect(x: 32, y: 865, width: 240, height: 44)
        let stalePoint = CGPoint(x: staleFrame.midX, y: staleFrame.midY)
        let settledElement = AccessibilityElement.make(
            label: "Rotor Host",
            identifier: "rotor_host",
            traits: .staticText,
            shape: .frame(AccessibilityRect(staleFrame)),
            activationPoint: stalePoint,
            customRotors: [.init(name: "Errors")]
        )
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        liveObject.accessibilityFrame = staleFrame
        liveObject.accessibilityActivationPoint = stalePoint
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [(settledElement, "rotor_host")],
            objects: ["rotor_host": liveObject]
        ))

        let freshFrame = CGRect(x: 32, y: 320, width: 240, height: 44)
        let freshPoint = CGPoint(x: freshFrame.midX, y: freshFrame.midY)
        let freshElement = AccessibilityElement.make(
            label: "Rotor Host",
            identifier: "rotor_host",
            traits: .staticText,
            shape: .frame(AccessibilityRect(freshFrame)),
            activationPoint: freshPoint,
            customRotors: [.init(name: "Errors")]
        )
        bagman.recordParsedObservedEvidence(InterfaceObservation.makeForTests(
            elements: [(freshElement, "rotor_host")],
            objects: ["rotor_host": liveObject]
        ))

        let target = literalTarget(ElementPredicate.identifier("rotor_host"))
        let settled = try XCTUnwrap(bagman.resolveTarget(target).resolvedElement)
        XCTAssertEqual(settled.element.shape.frame, staleFrame)
        XCTAssertEqual(settled.element.bhResolvedActivationPoint, stalePoint)

        let visible = try XCTUnwrap(bagman.resolveVisibleTarget(target).resolvedElement)
        XCTAssertEqual(visible.element.shape.frame, staleFrame)
        XCTAssertEqual(visible.element.bhResolvedActivationPoint, stalePoint)

        guard case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: settled) else {
            return XCTFail("Expected fresh live action target")
        }
        XCTAssertEqual(liveTarget.frame, freshFrame)
        XCTAssertEqual(liveTarget.activationPoint, freshPoint)
        XCTAssertNotEqual(liveTarget.frame, liveObject.accessibilityFrame)
        XCTAssertNotEqual(liveTarget.activationPoint, liveObject.accessibilityActivationPoint)
    }

    func testRawEvidenceRequiresCommittedHeistIdForLiveObjectAndGeometry() throws {
        let committedId: HeistId = "committed_control"
        let rawId: HeistId = "raw_control"
        let settledFrame = CGRect(x: 20, y: 40, width: 120, height: 44)
        let settledElement = AccessibilityElement.make(
            label: "Shared Control",
            traits: .adjustable,
            frame: settledFrame
        )
        bagman.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(settledElement, committedId)])
        )
        let target = try resolvedTarget(
            AccessibilityTarget.element(.label("Shared Control"), traits: [.adjustable])
        )
        let semanticTarget = try XCTUnwrap(bagman.resolveVisibleTarget(target).resolvedElement)

        let rawObject = NSObject()
        let rawFrame = CGRect(x: 80, y: 160, width: 180, height: 52)
        let rawElement = AccessibilityElement.make(
            label: "Shared Control",
            traits: .adjustable,
            frame: rawFrame
        )
        bagman.recordParsedObservedEvidence(InterfaceObservation.makeForTests(
            elements: [(rawElement, rawId)],
            objects: [rawId: rawObject]
        ))

        XCTAssertNil(bagman.interfaceElement(heistId: rawId))
        XCTAssertEqual(bagman.resolveVisibleTarget(target).resolvedElement?.heistId, committedId)
        XCTAssertNil(bagman.liveInterfaceElement(heistId: committedId))
        guard case .objectUnavailable = bagman.resolveLiveActionTarget(for: semanticTarget) else {
            return XCTFail("Expected different-HeistId raw evidence to remain non-dispatchable")
        }

        bagman.recordParsedObservedEvidence(InterfaceObservation.makeForTests(
            elements: [(rawElement, committedId)],
            objects: [committedId: rawObject]
        ))

        guard case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: semanticTarget) else {
            return XCTFail("Expected committed identity to admit raw live evidence")
        }
        XCTAssertTrue(liveTarget.object === rawObject)
        XCTAssertEqual(liveTarget.treeElement.heistId, committedId)
        XCTAssertEqual(liveTarget.frame, rawFrame)
    }

    func testVisibleSettleCommitStripsLiveHandlesFromSettledProjection() {
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        liveObject.accessibilityFrame = CGRect(x: 10, y: 10, width: 100, height: 44)
        let observation = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertNotNil(bagman.liveObject(for: "save"))
        XCTAssertNil(LiveCapture.makeForTests(snapshot: bagman.interfaceTree.viewportCapture).object(for: "save"))
    }

    func testLiveContainerTargetAcquiresFreshGeometryFromLatestLiveCapture() throws {
        let path = TreePath([0])
        let staleFrame = CGRect(x: 0, y: 800, width: 240, height: 80)
        let freshFrame = CGRect(x: 0, y: 120, width: 240, height: 80)
        let staleContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(staleFrame)
        )
        let freshContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(freshFrame)
        )
        let liveObject = NSObject()
        let settledObservationScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    path: .init(
                        container: staleContainer,
                        path: path,
                        containerName: "actions",
                        contentFrame: staleFrame
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(staleContainer, children: [])],
                containerNamesByPath: [path: "actions"],
                elementRefs: [:],
                containerRefsByPath: [:],
                containerContentFramesByPath: [path: ContentRect(staleFrame)],
                firstResponderHeistId: nil,
            )
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(settledObservationScreen)
        let liveScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    path: .init(
                        container: freshContainer,
                        path: path,
                        containerName: "actions",
                        contentFrame: freshFrame
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(freshContainer, children: [])],
                containerNamesByPath: [path: "actions"],
                elementRefs: [:],
                containerRefsByPath: [path: .init(object: liveObject)],
                containerContentFramesByPath: [path: ContentRect(freshFrame)],
                firstResponderHeistId: nil,
            )
        )
        bagman.recordParsedObservedEvidence(liveScreen)

        let resolved = bagman.resolveTarget(try resolvedTarget(
            .container(.identifier("actions"))
        ))
        guard case .resolved(.container(let semanticTarget)) = resolved else {
            return XCTFail("Expected semantic container, got \(resolved.diagnostics)")
        }
        guard case .resolved(let liveTarget) = bagman.resolveLiveContainerTarget(for: semanticTarget) else {
            return XCTFail("Expected fresh live container target")
        }

        XCTAssertTrue(liveTarget.object === liveObject)
        XCTAssertEqual(liveTarget.containerTarget.container.frame.cgRect, staleFrame)
        XCTAssertEqual(liveTarget.frame, freshFrame)
        XCTAssertEqual(liveTarget.activationPoint, CGPoint(x: freshFrame.midX, y: freshFrame.midY))
    }

    func testViewportUpdatePreservesKnownDiscoveryUnionWhenRefreshingSameScreen() throws {
        let controls = element(label: "Controls Demo", traits: .button)
        let customRotors = element(label: "Custom Rotors", traits: .button)
        let discovery = InterfaceObservation.makeForTests(
            elements: [(customRotors, "custom_rotors")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    controls,
                    heistId: "controls_demo",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let refreshedBottom = InterfaceObservation.makeForTests(elements: [(customRotors, "custom_rotors")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(refreshedBottom)

        XCTAssertEqual(bagman.viewportElementIDs, ["custom_rotors"])
        XCTAssertEqual(bagman.interfaceElementIDs, ["controls_demo", "custom_rotors"])
        XCTAssertEqual(
            bagman.resolveTarget(try resolvedTarget(
                AccessibilityTarget.element(.label("Controls Demo"), traits: [.button])
            )).resolvedElement?.heistId,
            "controls_demo"
        )
    }

    func testViewportUpdateDoesNotPreserveOffViewportMemoryForDisjointCommittedViewport() {
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
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let freshVisible = element(label: "Fresh Row", traits: .button)
        let refreshedTop = InterfaceObservation.makeForTests(elements: [(freshVisible, "shared_row")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(refreshedTop)

        XCTAssertEqual(bagman.viewportElementIDs, ["shared_row"])
        XCTAssertEqual(bagman.interfaceElementIDs, ["shared_row"])
        XCTAssertEqual(bagman.interfaceElement(heistId: "shared_row")?.element.label, "Fresh Row")
        XCTAssertNil(bagman.interfaceElement(heistId: "bottom_row"))
    }

    func testViewportUpdateDropsDiscoveryMemoryWhenScreenIdChangesDespiteSharedVisibleElement() {
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

        XCTAssertEqual(bagman.viewportElementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertEqual(bagman.interfaceElementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertNil(bagman.interfaceElement(heistId: "controls_demo"))
        XCTAssertNil(bagman.interfaceElement(heistId: "stale_offscreen"))
    }

    // MARK: - Matcher Resolution

    func testMatcherResolvesUniqueElement() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard let resolved = result.resolvedElement else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save")
    }

    func testPredicateTargetResolvesExactScreenElement() {
        let save = element(label: "Save", traits: .button)
        let cancel = element(label: "Cancel", traits: .button)
        register(save, heistId: "button_save", index: 0)
        register(cancel, heistId: "button_cancel", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Cancel")))
        guard let resolved = result.resolvedElement else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.heistId, "button_cancel")
        XCTAssertEqual(resolved.element.label, "Cancel")
    }

    func testNestedScopedTargetResolvesDescendantOfContainerLabels() throws {
        let checkoutContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Checkout", value: nil), identifier: nil,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let cartContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Cart", value: nil), identifier: nil,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let checkoutActions = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "checkout_actions",
            frame: .zero
        )
        let cartActions = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "cart_actions",
            frame: .zero
        )
        let checkoutPay = element(label: "Pay", traits: .button)
        let cartPay = element(label: "Pay", traits: .button)
        let checkoutPath = TreePath([0, 0, 0])
        let cartPath = TreePath([1, 0, 0])
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [
                "checkout_pay": InterfaceTree.Element(
                    heistId: "checkout_pay",
                    path: checkoutPath,
                    scrollMembership: nil,
                    element: checkoutPay
                ),
                "cart_pay": InterfaceTree.Element(
                    heistId: "cart_pay",
                    path: cartPath,
                    scrollMembership: nil,
                    element: cartPay
                ),
            ],
            hierarchy: [
                .container(checkoutContainer, children: [
                    .container(checkoutActions, children: [.element(checkoutPay, traversalIndex: 0)]),
                ]),
                .container(cartContainer, children: [
                    .container(cartActions, children: [.element(cartPay, traversalIndex: 1)]),
                ]),
            ],
            heistIdsByPath: [
                checkoutPath: "checkout_pay",
                cartPath: "cart_pay",
            ],
            firstResponderHeistId: nil
        ))

        let result = bagman.resolveTarget(try resolvedTarget(
            .within(
                container: .label("Checkout"),
                .within(container: .identifier("checkout_actions"), .label("Pay"))
            )
        ))

        XCTAssertEqual(result.resolvedElement?.heistId, "checkout_pay")
    }

    func testScopedTargetResolutionUsesInterfaceTreeScrollMembership() throws {
        let containerPath = TreePath([30])
        let staleElementPath = TreePath([2])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Order Entry", value: nil), identifier: "order_entry_container",
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let reviewSale = element(label: "Review Sale", identifier: "review_sale", traits: .button)
        let observation = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "review_sale": InterfaceTree.Element(
                        heistId: "review_sale",
                        path: staleElementPath,
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: 0),
                        element: reviewSale
                    ),
                ],
                containers: [
                    containerPath: InterfaceTree.Container(
                        container: container,
                        path: containerPath,
                        containerName: "order_entry_container",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests()
        )
        bagman.installObservationForTesting(observation)
        let target = AccessibilityTarget.within(
            container: .identifier("order_entry_container"),
            .identifier("review_sale")
        )
        let resolvedTarget = try resolvedTarget(target)

        XCTAssertEqual(bagman.resolveTarget(resolvedTarget).resolvedElement?.heistId, "review_sale")
    }

    func testMatcherAmbiguousReturnsCandidates() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let matches = try? XCTUnwrap(facts.elementMatches)
        let candidates = matches?.candidateDescriptions ?? []
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.matchedCount, 2)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testMatcherAmbiguousCandidatesIncludeDetails() {
        let save1 = element(label: "Save", value: "draft", identifier: "save1")
        let save2 = element(label: "Save", value: "final", identifier: "save2")
        register(save1, heistId: "save1", index: 0)
        register(save2, heistId: "save2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let matches = try? XCTUnwrap(facts.elementMatches)
        let candidates = matches?.candidateDescriptions ?? []
        XCTAssertEqual(matches?.exactMatches[0].element.identifier, "save1")
        XCTAssertEqual(matches?.exactMatches[1].element.identifier, "save2")
        XCTAssertTrue(candidates[0].contains("id=save1"))
        XCTAssertTrue(candidates[1].contains("id=save2"))
        // Candidates are described by their predicate fields (label/identifier/value),
        // not by an agent-facing heistId — that concept was removed.
        XCTAssertTrue(candidates[0].contains("\"Save\""))
        XCTAssertTrue(candidates[0].contains("value=draft"))
        XCTAssertTrue(candidates[0].contains("visible"))
    }

    func testMatcherNoMatchReturnsNotFound() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Cancel")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("No match for"))
        XCTAssertTrue(diagnostics.contains("Next:"))
        XCTAssertTrue(diagnostics.contains("exact label"))
    }

    func testMatcherNearMissDiagnostics() throws {
        let element = element(label: "Save", value: "draft")
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(try resolvedTarget(
            AccessibilityTarget.label("Save").and(.value("final"))
        ))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("near miss"), "Should show near-miss: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("value"), "Should identify value as divergent field")
    }

    func testMatcherNearMissIncludesOffscreenKnownElement() {
        let visible = element(label: "Visible", traits: .button)
        let offscreen = element(label: "Long List", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        registerOffScreen(offscreen, heistId: "long_list_button")

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Long")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("Long List"), "Should suggest off-viewport candidate: \(diagnostics)")
        // The near-miss names the candidate by its label predicate, not by an
        // agent-facing heistId — that concept was removed.
        XCTAssertTrue(diagnostics.contains("label=\"Long List\""), "Should describe candidate by label predicate: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("offscreen"))
        XCTAssertTrue(diagnostics.contains("unreachable"))
    }

    // MARK: - TargetResolution Algebra

    func testMissingTargetIsNotFound() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("nope")))
        guard case .notFound = result else {
            return XCTFail("Expected .notFound, got \(result)")
        }
    }

    func testDuplicateTargetsAreAmbiguous() {
        let save1 = element(label: "Save")
        let save2 = element(label: "Save")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous = result else {
            return XCTFail("Expected .ambiguous, got \(result)")
        }
    }

    func testDiagnosticsEmptyForResolved() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("OK")))
        XCTAssertEqual(result.diagnostics, "")
    }

    // MARK: - Ambiguous Matcher Diagnostics

    func testAmbiguousMatcherReturnsDiagnostics() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        XCTAssertTrue(result.diagnostics.contains("2 elements match"), "Should return ambiguous message: \(result.diagnostics)")
    }

    func testEmptyScreenReturnsCompactSummary() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Anything")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("interface hierarchy is empty"))
        XCTAssertTrue(diagnostics.contains("Next:"))
    }

    // MARK: - Ordinal Selection

    func testOrdinalSelectsNthMatch() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        let save3 = element(label: "Save", value: "archive")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)
        register(save3, heistId: "button_save_3", index: 2)

        let result0 = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 0))
        XCTAssertEqual(result0.resolvedElement?.element.value, "draft")

        let result1 = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 1))
        XCTAssertEqual(result1.resolvedElement?.element.value, "final")

        let result2 = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 2))
        XCTAssertEqual(result2.resolvedElement?.element.value, "archive")
    }

    func testOrdinalOutOfBoundsReturnsNotFound() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 5))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 5, matchCount: 2))
        XCTAssertTrue(diagnostics.contains("ordinal 5 requested"))
        XCTAssertTrue(diagnostics.contains("2 matches"))
        XCTAssertTrue(diagnostics.contains("Next:"))
        XCTAssertTrue(diagnostics.contains("ordinal 0...1"))
    }

    func testOrdinalNilPreservesAmbiguousBehavior() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.matchedCount, 2)
        XCTAssertTrue(diagnostics.contains("2 elements match"))
        XCTAssertTrue(diagnostics.contains("ordinal"), "Should hint about ordinal usage")
    }

    func testAmbiguousMatchedCountIsExactBeyondDisplayedCandidateLimit() {
        for index in 0..<12 {
            register(
                element(label: "Duplicate", value: "\(index)"),
                heistId: HeistId(rawValue: "duplicate_\(index)"),
                index: index
            )
        }

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Duplicate")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        XCTAssertEqual(facts.matchedCount, 12)
        XCTAssertEqual(facts.elementMatches?.exactMatches.count, 12)
        XCTAssertTrue(result.diagnostics.contains("10+ elements match"))
        XCTAssertTrue(result.diagnostics.contains("... and more"))
    }

    func testOrdinalZeroOnSingleMatchSucceeds() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 0))
        XCTAssertNotNil(result.resolvedElement)
        XCTAssertEqual(result.resolvedElement?.element.label, "Save")
    }

    func testOrdinalZeroOnNoMatchReturnsNotFound() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Nonexistent"), ordinal: 0))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 0, matchCount: 0))
        XCTAssertTrue(diagnostics.contains("ordinal 0 requested"))
        XCTAssertTrue(diagnostics.contains("0 matches"))
        XCTAssertTrue(diagnostics.contains("Next:"))
    }

    // MARK: - Known Semantic State

    /// Matcher-based resolution reads the committed semantic state. Viewport
    /// reachability is handled later by action execution.
    func testMatcherResolvesKnownEntryOutsideLiveHierarchy() throws {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        register(onScreen, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "long_list_button")

        let result = bagman.resolveTarget(try resolvedTarget(
            AccessibilityTarget.element(.label("Long List"), traits: [.button])
        ))
        guard case .resolved(.element(let target)) = result else {
            XCTFail("Expected interface-tree match, got \(result)")
            return
        }
        XCTAssertEqual(target.heistId, "long_list_button")
    }

    func testScopedHeistIdsSeparateVisibleFromKnownUnion() {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        register(onScreen, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "long_list_button")

        XCTAssertEqual(bagman.ids(in: .viewport), ["button_visible"])
        XCTAssertEqual(bagman.ids(in: .interface), ["button_visible", "long_list_button"])
        XCTAssertEqual(bagman.viewportElementIDs, bagman.ids(in: .viewport))
        XCTAssertEqual(bagman.interfaceElementIDs, bagman.ids(in: .interface))
    }

    func testScopedInterfaceElementRequiresViewportScopeForCurrentCapture() {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        register(onScreen, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "long_list_button")

        XCTAssertNotNil(bagman.treeElement(heistId: "button_visible", in: .viewport))
        XCTAssertNil(bagman.treeElement(heistId: "long_list_button", in: .viewport))
        XCTAssertNotNil(bagman.treeElement(heistId: "long_list_button", in: .interface))
    }

    func testResolveVisibleTargetFailsClosedForAmbiguousMatcher() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Save")))

        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected visible ambiguity, got \(result)")
            return
        }
        XCTAssertEqual(facts.elementMatches?.exactMatches.count, 2)
        XCTAssertEqual(facts.resolutionScope, .viewport)
        let diagnostics = result.diagnostics
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testResolveVisibleTargetPreservesExplicitOrdinalOutOfRange() {
        let save = element(label: "Save", traits: .button)
        register(save, heistId: "button_save", index: 0)

        let result = bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 4))

        guard case .notFound(let facts) = result else {
            XCTFail("Expected ordinal miss, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 4, matchCount: 1))
        XCTAssertEqual(facts.resolutionScope, .viewport)
        XCTAssertTrue(diagnostics.contains("ordinal 4 requested"))
        XCTAssertTrue(diagnostics.contains("1 match"))
    }

    func testResolveVisibleTargetRequiresLiveHierarchy() {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Below Fold", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "below_fold_button")

        let knownResult = bagman.resolveTarget(literalTarget(ElementPredicate.label("Below Fold")))
        XCTAssertEqual(knownResult.resolvedElement?.heistId, "below_fold_button")

        let visibleResult = bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Below Fold")))
        guard case .notFound(let facts) = visibleResult else {
            XCTFail("Expected visible miss, got \(visibleResult)")
            return
        }
        let diagnostics = visibleResult.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertEqual(facts.resolutionScope, .viewport)
        XCTAssertTrue(diagnostics.contains("No match for"))
        XCTAssertTrue(diagnostics.contains("scope: viewport"), "Should identify failed resolution scope: \(diagnostics)")
    }

    func testOffViewportEntryWithStaleObjectIsNotDispatchableUntilInViewport() {
        let offScreen = element(label: "Below Fold", traits: .button)
        let object = UIAccessibilityElement(accessibilityContainer: NSObject())
        object.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 44)
        object.accessibilityActivationPoint = CGPoint(x: 50, y: 22)
        let scrollView = UIScrollView()
        let containerPath = TreePath([0])
        let elementPath = TreePath([0, 0])
        let scrollContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )
        let entry = InterfaceTree.Element(
            heistId: "below_fold_button",
            path: elementPath,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: nil),
            element: offScreen
        )

        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.container(scrollContainer, children: [])],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(literalTarget(ElementPredicate.label("Below Fold"))).resolvedElement else {
            XCTFail("Off-viewport entry should still resolve")
            return
        }
        XCTAssertEqual(resolved.heistId, "below_fold_button")
        XCTAssertNil(bagman.treeElement(heistId: "below_fold_button", in: .viewport))
        guard case .objectUnavailable = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Off-viewport target should not have a live action target")
            return
        }

        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.container(scrollContainer, children: [.element(offScreen, traversalIndex: 0)])],
            heistIdsByPath: [elementPath: entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        let refreshed = bagman.resolveTarget(literalTarget(ElementPredicate.label("Below Fold"))).resolvedElement
        XCTAssertNotNil(bagman.treeElement(heistId: "below_fold_button", in: .viewport))
        guard let refreshed,
              case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: refreshed) else {
            XCTFail("Expected refreshed visible target to have live action geometry")
            return
        }
        XCTAssertTrue(AccessibilityActionDispatcher().increment(liveTarget))
    }

    func testLiveGeometryRejectsUnusableAccessibilityCaptureFrame() {
        let visible = AccessibilityElement.make(
            label: "Visible",
            traits: .button,
            shape: .frame(.zero),
            activationPoint: CGPoint(x: 50, y: 22)
        )
        let object = UIAccessibilityElement(accessibilityContainer: NSObject())
        object.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 44)
        object.accessibilityActivationPoint = CGPoint(x: 50, y: 22)
        let scrollView = UIScrollView()
        let entry = InterfaceTree.Element(
            heistId: "button_visible",
            scrollMembership: nil,
            element: visible
        )
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(visible, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(literalTarget(ElementPredicate.label("Visible"))).resolvedElement else {
            XCTFail("Expected visible target to resolve")
            return
        }
        guard case .geometryUnavailable = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Expected unusable accessibility capture frame to be rejected as missing live geometry")
            return
        }
    }

    func testResolveTargetFindsKnownMatcherOutsideLiveHierarchy() {
        let offScreen = element(label: "Below Fold", traits: .button)
        registerOffScreen(offScreen, heistId: "below_fold_button")

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Below Fold"))).resolvedElement)
    }

    func testResolveTargetFindsLivePredicateInViewport() {
        let element = element(label: "Visible", traits: .button)
        register(element, heistId: "visible_button", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Visible"))).resolvedElement)
    }

    func testResolveTargetHonorsExplicitOrdinal() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 1)).resolvedElement)
        guard case .notFound = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 2)) else {
            XCTFail("Expected out-of-range ordinal to fail closed")
            return
        }
    }

    func testRegisteredElementResolvesWithoutMarkPresented() {
        let element = element(label: "Combobox", traits: .button)
        register(element, heistId: "button_combobox", index: 0)

        // Element resolves immediately — no markPresented gate
        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Combobox")))
        XCTAssertNotNil(result.resolvedElement)
    }

    // MARK: - Direct InterfaceTree Resolution

    func testDirectInterfaceTreeResolutionPreservesOrdinalsAndDiagnostics() throws {
        installMatchingScreen()

        enum ExpectedResolution {
            case resolved(HeistId)
            case ambiguous([HeistId])
            case notFound
            case ordinalOutOfRange(requested: Int, matches: [HeistId])
        }

        struct ResolutionCase {
            let name: String
            let target: ResolvedAccessibilityTarget
            let expected: ExpectedResolution
        }

        let cases = [
            ResolutionCase(
                name: "unique",
                target: literalTarget(ElementPredicate.label("Done")),
                expected: .resolved("done_button")
            ),
            ResolutionCase(
                name: "ambiguous",
                target: literalTarget(ElementPredicate.label("Delete")),
                expected: .ambiguous(["delete_first", "delete_second"])
            ),
            ResolutionCase(
                name: "not found",
                target: literalTarget(ElementPredicate.label("Missing")),
                expected: .notFound
            ),
            ResolutionCase(
                name: "ordinal select",
                target: literalTarget(ElementPredicate.label("Delete"), ordinal: 1),
                expected: .resolved("delete_second")
            ),
            ResolutionCase(
                name: "ordinal out of range",
                target: literalTarget(ElementPredicate.label("Delete"), ordinal: 2),
                expected: .ordinalOutOfRange(
                    requested: 2,
                    matches: ["delete_first", "delete_second"]
                )
            ),
        ]

        for testCase in cases {
            let resolution = bagman.resolveTarget(testCase.target)

            switch testCase.expected {
            case .resolved(let expectedId):
                let resolved = try XCTUnwrap(resolution.resolvedElement, testCase.name)
                XCTAssertEqual(resolved.heistId, expectedId, testCase.name)
            case .ambiguous(let expectedIds):
                guard case .ambiguous(let facts) = resolution else {
                    return XCTFail("Expected ambiguous for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.matchedCount, expectedIds.count, testCase.name)
                XCTAssertEqual(facts.elementMatches?.exactMatches.map(\.heistId), expectedIds, testCase.name)
            case .notFound:
                guard case .notFound(let facts) = resolution else {
                    return XCTFail("Expected notFound for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.reason, .noMatches, testCase.name)
                XCTAssertTrue(facts.elementMatches?.exactMatches.isEmpty == true, testCase.name)
            case .ordinalOutOfRange(let requested, let expectedMatches):
                guard case .notFound(let facts) = resolution else {
                    return XCTFail("Expected notFound for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(
                    facts.reason,
                    .ordinalOutOfRange(requested: requested, matchCount: expectedMatches.count),
                    testCase.name
                )
                XCTAssertEqual(facts.elementMatches?.exactMatches.map(\.heistId), expectedMatches, testCase.name)
            }
        }
    }

    // MARK: - Exact Default and Explicit Broad Matches

    /// A partial label must return `.notFound`; broad matching is explicit.
    func testSubstringPartialLabelReturnsNotFound() {
        let save = element(label: "Save Draft", traits: .button)
        register(save, heistId: "button_save_draft", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .notFound(let facts) = result else {
            XCTFail("Substring partial must not auto-resolve to exact-or-miss; got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("Save Draft"),
                      "Diagnostic should surface the available interface evidence: \(diagnostics)")
        XCTAssertFalse(diagnostics.contains("contains-match suggestion"), diagnostics)
    }

    /// A contains predicate is an authored broad match, useful for migrating
    /// KIF `usingLabelContaining` call sites without weakening exact literals.
    func testExplicitContainsLabelResolves() throws {
        let save = element(label: "Save Draft", traits: .button)
        register(save, heistId: "button_save_draft", index: 0)

        let result = bagman.resolveTarget(try resolvedTarget(.label(.contains("Save"))))
        guard let resolved = result.resolvedElement else {
            XCTFail("Explicit contains predicate should resolve, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save Draft")
    }

    /// Exact equality (after case-insensitive comparison) still resolves.
    func testExactLabelCaseInsensitiveResolves() {
        let save = element(label: "Save", traits: .button)
        register(save, heistId: "button_save", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"))).resolvedElement)
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("save"))).resolvedElement)
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("SAVE"))).resolvedElement)
    }

    /// Typography folding still works under exact-or-miss: a label with a smart
    /// apostrophe resolves against an ASCII apostrophe matcher.
    func testTypographyFoldingPreservedUnderExactSemantics() {
        let dontSkip = element(label: "Don\u{2019}t skip", traits: .button)
        register(dontSkip, heistId: "button_dont_skip", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Don't skip"))).resolvedElement)
    }

    /// When two labels share a partial substring, exact must win outright
    /// (no ambiguity). This was Finding 5's regression case.
    func testExactMatchWinsOverPartialSiblings() {
        let save = element(label: "Save")
        let saveDraft = element(label: "Save Draft")
        register(save, heistId: "button_save", index: 0)
        register(saveDraft, heistId: "button_save_draft", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard let resolved = result.resolvedElement else {
            XCTFail("Exact match should resolve uniquely, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save")
    }

    /// Near-miss surface for absent semantics: a substring-only match must not
    /// be considered present.
    func testResolveTargetReportsAbsentForSubstringOnlyMatch() {
        let save = element(label: "Save Draft", traits: .button)
        register(save, heistId: "button_save_draft", index: 0)

        // "Save" is a substring of "Save Draft" but not equal, so semantic
        // resolution must not report it as present.
        guard case .notFound = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"))) else {
            XCTFail("Expected substring-only matcher to miss")
            return
        }
        // Exact label still resolves to present.
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate.label("Save Draft"))).resolvedElement)
    }

    /// Server-side and client-side matchers must agree on the same input.
    /// Regression for Finding 4 (matcher contract drift).
    func testServerAndClientMatchersAgreeOnSameInput() throws {
        let element = element(label: "Save Draft", value: "x", identifier: "save_btn", traits: .button)
        let matcher = try resolvedPredicate(
            AccessibilityTarget.element(.label("Save Draft"), traits: [.button])
        )

        let serverHit = matcher.matches(element)

        // Client-side: HeistElement.matches uses the same StringMatch configuration.
        let heistElement = HeistElement(
            description: "Save Draft",
            label: "Save Draft",
            value: "x",
            identifier: "save_btn",
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )
        let clientHit = heistElement.matches(matcher)

        XCTAssertEqual(serverHit, clientHit, "Server and client must agree on the same matcher input")
        XCTAssertTrue(serverHit, "Both sides must hit on exact label+trait match")

        // Substring partial should miss on BOTH sides now.
        let partial = ElementPredicate.label("Save")
        XCTAssertFalse(partial.matches(element))
        XCTAssertFalse(heistElement.matches(partial))
    }

    /// Smart-quote labels must produce the same answer on both sides
    /// (Finding 4's typography divergence).
    func testServerAndClientAgreeOnSmartQuoteLabel() {
        let smart = element(label: "Don\u{2019}t skip")
        let heist = HeistElement(
            description: "x",
            label: "Don\u{2019}t skip",
            value: nil,
            identifier: nil,
            traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )
        let asciiMatcher = ElementPredicate.label("Don't skip")

        XCTAssertTrue(asciiMatcher.matches(smart))
        XCTAssertTrue(heist.matches(asciiMatcher),
                      "Client-side must fold typography just like server-side")
    }
}

private extension TheVault.TargetAmbiguityFacts {
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

private extension TheVault.TargetNotFoundFacts {
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

private extension TheVault.TargetElementMatches {
    var candidateDescriptions: [String] {
        exactMatches.map {
            TargetResolutionDiagnostics.elementCandidateDescription(
                $0,
                visibleHeistIds: visibleHeistIds
            )
        }
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
