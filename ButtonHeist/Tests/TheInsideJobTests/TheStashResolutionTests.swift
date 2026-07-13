#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheStashResolutionTests: XCTestCase {

    private var bagman: TheStash!

    override func setUp() async throws {
        bagman = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        bagman.stopPassiveSemanticObservation()
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

    /// Register an element into the current InterfaceObservation. Rebuilds the screen value
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
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: elements,
            hierarchy: hierarchyNodes,
            heistIdsByPath: heistIdsByPath,
            firstResponderHeistId: nil,
        ))
    }

    private func installMatcherParityScreen() -> InterfaceObservation {
        nextElementYOffset = 0
        let screen = InterfaceObservation.makeForTests(elements: [
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
        bagman.installScreenForTesting(screen)
        return screen
    }

    private func matchSignature(_ element: AccessibilityElement) -> String {
        matchSignature(TheStash.WireConversion.convert(element))
    }

    private func matchSignature(_ element: HeistElement) -> String {
        let traits = element.traits.map(\.rawValue).sorted().joined(separator: ",")
        return [
            element.label ?? "",
            element.identifier ?? "",
            element.value ?? "",
            traits,
        ].joined(separator: "|")
    }

    // MARK: - Settled Semantic Observation

    func testSemanticObservationSubscriptionsCoalesceToWidestScope() {
        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)

        let visible = bagman.subscribeSemanticObservation(scope: .visible)
        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)

        do {
            let discovery = bagman.subscribeSemanticObservation(scope: .discovery)
            XCTAssertEqual(bagman.subscribedObservationScope(), .discovery)
            _ = discovery
        }

        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)
        _ = visible
    }

    func testActiveObservationDemandCoalescesWithSubscribersAndDropsWhenCancelled() {
        XCTAssertFalse(bagman.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 0)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .idle)
        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)

        let demand = bagman.beginSemanticObservationDemand(scope: .visible)
        XCTAssertTrue(bagman.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 1)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .active)
        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)

        do {
            let discovery = bagman.subscribeSemanticObservation(scope: .discovery)
            XCTAssertEqual(bagman.subscribedObservationScope(), .discovery)
            _ = discovery
        }

        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)

        demand.cancel()

        XCTAssertFalse(bagman.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 0)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .idle)
        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)
    }

    func testActiveObservationDemandCancelRemovesScopePressureOnEarlyExit() {
        func beginDemandAndReturnEarly() {
            let demand = bagman.beginSemanticObservationDemand(scope: .discovery)
            defer { demand.cancel() }

            XCTAssertTrue(bagman.semanticObservationStream.hasActiveObservationDemand)
            XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 1)
            XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .active)
            XCTAssertEqual(bagman.subscribedObservationScope(), .discovery)
            return
        }

        beginDemandAndReturnEarly()

        XCTAssertFalse(bagman.semanticObservationStream.hasActiveObservationDemand)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandCount, 0)
        XCTAssertEqual(bagman.semanticObservationStream.activeObservationDemandState, .idle)
        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)
    }

    func testInterfaceTreeKeepsLiveEvidenceOutOfTreeState() {
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        let screen = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        let tree = InterfaceTree.empty.updatingViewport(with: screen)

        XCTAssertTrue(screen.liveCapture.object(for: "save") === liveObject)
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

        XCTAssertEqual(baseline.elementIDs, ["words_header"])
        XCTAssertEqual(baseline.viewportElementIDs, ["words_header"])
        XCTAssertNil(baseline.findElement(heistId: "home_button"))
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
        XCTAssertEqual(previousDiscovery.id, "controls_demo")
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(previousDiscovery)

        let currentHeader = element(label: "ButtonHeist Demo", traits: .header)
        let sharedCurrentAction = element(label: "Shared Action", traits: .button)
        let currentVisible = InterfaceObservation.makeForTests(elements: [
            (currentHeader, "buttonheist_demo"),
            (sharedCurrentAction, "shared_action"),
        ])
        XCTAssertEqual(currentVisible.id, "buttonheist_demo")
        bagman.recordParsedObservedEvidence(currentVisible)

        let baseline = bagman.actionDiscoveryBaseline()

        XCTAssertEqual(baseline.id, "buttonheist_demo")
        XCTAssertEqual(baseline.viewportElementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertEqual(baseline.elementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertNil(baseline.findElement(heistId: "controls_demo"))
        XCTAssertNil(baseline.findElement(heistId: "stale_offscreen"))
    }

    func testLatestSettledSemanticObservationAdvancesMonotonically() {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstObservation = bagman.latestSettledSemanticObservation

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)
        let secondObservation = bagman.latestSettledSemanticObservation

        XCTAssertNotNil(firstObservation)
        XCTAssertNotNil(secondObservation)
        XCTAssertEqual(firstObservation?.sequence, 1)
        XCTAssertEqual(secondObservation?.sequence, 2)
        XCTAssertEqual(secondObservation?.screen.orderedElements.first?.element.label, "Second")
    }

    func testSettledSemanticObservationRetainsFirstResponderWithoutLiveObjectReferences() throws {
        let object = NSObject()
        let screen = InterfaceObservation.makeForTests(
            [
                InterfaceObservation.TestEntry(
                    element(label: "Email"),
                    heistId: "email",
                    object: object
                ),
            ],
            firstResponderHeistId: "email"
        )

        bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let settledScreen = try XCTUnwrap(bagman.latestSettledSemanticObservation?.screen)
        XCTAssertEqual(settledScreen.liveCapture.firstResponderHeistId, "email")
        XCTAssertNil(settledScreen.liveCapture.object(for: "email"))
    }

    func testSettledSemanticObservationEventContainsNoLiveTripwireIdentity() {
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Home"), "home")])

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

        XCTAssertFalse(containsLiveTripwireIdentity(event))
    }

    func testCleanVisibleSettleCommitUpdatesSettledSemanticTruth() {
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])

        bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertFalse(bagman.latestSettledSemanticObservationInvalidated)
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence)
    }

    func testSettledSemanticObservationEventCarriesPreviousTraceAndFacts() throws {
        let first = InterfaceObservation.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstEvent = try XCTUnwrap(bagman.latestSettledSemanticObservationEvent)

        XCTAssertEqual(firstEvent.sequence, 1)
        XCTAssertNil(firstEvent.previous)
        XCTAssertEqual(firstEvent.trace.captures.count, 1)
        XCTAssertTrue(firstEvent.trace.changeFacts.isEmpty)

        let second = InterfaceObservation.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
            (element(label: "Toast"), "toast"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)
        let secondEvent = try XCTUnwrap(bagman.latestSettledSemanticObservationEvent)

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

    func testVisibleObservationTraceExcludesDiscoveryOnlyElements() throws {
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

        let event = try XCTUnwrap(bagman.latestSettledSemanticObservationEvent)
        XCTAssertEqual(event.scope, .visible)
        XCTAssertEqual(bagman.interfaceElementIDs, ["buttonheist_demo", "custom_rotors"])

        let labels = try XCTUnwrap(event.trace.captures.last)
            .interface
            .projectedElements
            .compactMap(\.label)
        XCTAssertEqual(labels, ["Custom Rotors"])
        XCTAssertFalse(labels.contains("ButtonHeist Demo"))
    }

    func testDiagnosticEvidenceInvalidatesLatestSettledObservationWithoutReplacingIt() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)
        let sequence = bagman.latestSettledSemanticObservation?.sequence

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(bagman.latestSettledSemanticObservation?.sequence, sequence)
        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label, "Timeout")
        XCTAssertTrue(bagman.latestSettledSemanticObservationInvalidated)
        XCTAssertNil(bagman.resolveVisibleTarget(literalTarget(ElementPredicate(label: "Timeout"))).resolved)
        XCTAssertEqual(
            bagman.resolveVisibleTarget(literalTarget(ElementPredicate(label: "Settled"))).resolved?.element.label,
            "Settled"
        )
    }

    func testObservedEvidenceUpdatesVisibleWorldWithoutReplacingSettledTruth() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let observed = InterfaceObservation.makeForTests(elements: [(element(label: "Observed"), "observed")])
        bagman.recordParsedObservedEvidence(observed)

        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertEqual(bagman.latestObservation.orderedElements.first?.element.label, "Observed")
        XCTAssertNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Observed"))).resolved)
        XCTAssertNil(bagman.resolveVisibleTarget(literalTarget(ElementPredicate(label: "Observed"))).resolved)
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

        XCTAssertEqual(bagman.latestObservation.findElement(heistId: "row")?.scrollMembership?.index, 500)
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

        XCTAssertNil(bagman.latestObservation.findElement(heistId: "row")?.scrollMembership)
        XCTAssertNil(try XCTUnwrap(bagman.liveInterfaceElement(heistId: "row")).scrollMembership)
    }

    func testCancelledNoScreenSettleDoesNotPublishSettledTruth() async {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)
        let sequence = bagman.latestSettledSemanticObservation?.sequence

        let outcome = SettleSession.Outcome(
            outcome: .cancelled(timeMs: 1),
            events: [],
            finalObservation: nil,
            elementsByKey: [:]
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )

        XCTAssertEqual(result.settle.outcome, .cancelled(timeMs: 1))
        guard case .unavailable = result.result else {
            return XCTFail("Expected cancelled settle to return unavailable evidence")
        }
        XCTAssertEqual(bagman.latestSettledSemanticObservation?.sequence, sequence)
        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled")
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence)
        XCTAssertTrue(bagman.latestSettledSemanticObservationInvalidated)
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
        let screen = InterfaceObservation.makeForTests(
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

        let evidence = bagman.resolveAccessibilityNotificationEvidence([event], in: screen)

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
            identityScreen: source,
            referenceScreen: reference
        )

        guard case .element(let reference)? = evidence.first?.notificationData else {
            return XCTFail("Expected notification object to resolve into reference screen")
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
            identityScreen: source,
            referenceScreen: reference
        )

        guard case .element(let resolved)? = evidence.first?.notificationData else {
            return XCTFail("Expected nested notification element reference")
        }
        XCTAssertEqual(resolved.path, TreePath([0, 0]))
        XCTAssertEqual(resolved.traversalIndex, 0)
    }

    func testScreenChangedAfterActionBatchCaptureInvalidatesCommittedObservation() async throws {
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Checkout"), "checkout")])
        let action = bagman.accessibilityNotifications.beginActionWindow()
        let batch = try XCTUnwrap(action.capture())
        bagman.accessibilityNotifications.record(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )

        bagman.semanticObservationStream.commitVisibleObservationForTesting(screen, notificationBatch: batch)
        action.cancel()

        let served = await bagman.semanticObservationStream.settledEvent(
            scope: .visible,
            after: nil,
            timeout: 0
        )
        XCTAssertNil(served)
    }

    func testNotificationOverflowIsExplicitInCommittedTrace() async throws {
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let action = bagman.accessibilityNotifications.beginActionWindow()
        for _ in 0..<65 {
            bagman.accessibilityNotifications.record(
                code: 1008,
                notificationData: .none,
                associatedElement: .none
            )
        }
        let batch = try XCTUnwrap(action.capture())

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(
            screen,
            notificationBatch: batch
        )
        action.cancel()

        XCTAssertEqual(
            event.trace.captures.last?.transition.accessibilityNotificationGap,
            AccessibilityNotificationGap(droppedThroughSequence: 1)
        )
    }

    func testCommittedTraceRetainsFirstResponderAsDurableTarget() {
        let screen = InterfaceObservation.makeForTests(
            [
                .init(label: "Email", heistId: "email", traits: .textEntry),
                .init(label: "Continue", heistId: "continue", traits: .button),
            ],
            firstResponderHeistId: "email"
        )

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

        XCTAssertNotNil(event.trace.captures.last?.context.firstResponder)
        XCTAssertEqual(event.observation.screen.liveCapture.firstResponderHeistId, "email")
    }

    func testFailedSettlePreservesScreenChangedForNextIdenticalCommit() async {
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let firstHeist = bagman.accessibilityNotifications.beginHeistScope()
        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.record(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(screen: screen),
            elementsByKey: [:]
        )

        _ = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome,
            notificationWindow: action
        )
        firstHeist.cancel()
        bagman.accessibilityNotifications.record(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )

        XCTAssertEqual(
            bagman.accessibilityNotifications.pendingEvents().map(\.provenance),
            [.scoped, .ambient]
        )

        let secondHeist = bagman.accessibilityNotifications.beginHeistScope()
        defer { secondHeist.cancel() }
        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

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
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let firstHeist = bagman.accessibilityNotifications.beginHeistScope()
        firstHeist.cancel()
        bagman.accessibilityNotifications.record(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let secondHeist = bagman.accessibilityNotifications.beginHeistScope()
        defer { secondHeist.cancel() }

        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

        XCTAssertEqual(secondEvent.generation, firstEvent.generation)
        XCTAssertTrue(secondEvent.trace.captures.last?.transition.accessibilityNotifications.isEmpty == true)
        XCTAssertTrue(secondEvent.trace.changeFacts.isEmpty)
    }

    func testCleanPostActionSettleRequiresActionWindowToClaimAccessibilityNotifications() async {
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.recordParsedObservedEvidence(screen)
        bagman.accessibilityNotifications.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let outcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(screen: screen),
            elementsByKey: [:]
        )

        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )

        guard case .committed(let event) = result.result else {
            return XCTFail("Expected clean settle to commit")
        }
        XCTAssertEqual(event.trace.captures.last?.transition.accessibilityNotifications, [])
        XCTAssertEqual(bagman.accessibilityNotifications.pendingEvents().map(\.kind), [.announcement])
    }

    func testCleanSettleProofRequiresCurrentCaptureTokenAndFingerprint() {
        let stableElement = element(label: "Stable")
        let settled = InterfaceObservation.makeForTests(elements: [(stableElement, "stable")])
        let finalObservation = SettleSessionFinalObservation(screen: settled)
        let outcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: finalObservation,
            elementsByKey: [:]
        )
        bagman.recordParsedObservedEvidence(settled)

        XCTAssertNotNil(InterfaceObservationProof.settled(outcome, stash: bagman))

        let replacement = InterfaceObservation.makeForTests(elements: [(stableElement, "stable")])
        XCTAssertEqual(replacement, settled)
        XCTAssertNotEqual(replacement.captureToken, settled.captureToken)
        bagman.recordParsedObservedEvidence(replacement)
        XCTAssertNil(InterfaceObservationProof.settled(outcome, stash: bagman))

        bagman.recordParsedObservedEvidence(settled)
        let wrongFingerprint = finalObservation.fingerprint == 0 ? 1 : 0
        let mismatchedOutcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(
                screen: settled,
                fingerprint: wrongFingerprint
            ),
            elementsByKey: [:]
        )
        XCTAssertNil(InterfaceObservationProof.settled(mismatchedOutcome, stash: bagman))
    }

    func testRecaptureOnlyValueChangedNotificationProducesNotificationFact() async throws {
        let screen = InterfaceObservation.makeForTests(elements: [
            (element(label: "Volume", value: "50%", traits: .adjustable), "volume"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.record(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: SettleSession.Outcome(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(screen: screen),
                elementsByKey: [:]
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
        bagman.accessibilityNotifications.record(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: SettleSession.Outcome(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(screen: after),
                elementsByKey: [:]
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
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Saved" as NSString),
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: SettleSession.Outcome(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(screen: screen),
                elementsByKey: [:]
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
        bagman.accessibilityNotifications.record(
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

    func testDiscoveryCommitClassifiesGenerationAgainstLatestVisibleObservation() {
        let visible = InterfaceObservation.makeForTests(elements: [
            (element(label: "Menu", traits: .header), "menu"),
        ])
        let visibleEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(visible)
        let discoveryHeader = element(label: "Checkout", traits: .header)
        let discovery = InterfaceObservation.makeForTests(elements: [(discoveryHeader, "checkout")])

        let discoveryEvent = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        XCTAssertNotEqual(discoveryEvent.generation, visibleEvent.generation)
        XCTAssertEqual(discoveryEvent.previous?.sequence, visibleEvent.sequence)
    }

    func testPostActionFailedSettlePreservesPendingAccessibilityNotificationsDuringHeistScope() async {
        let heist = bagman.accessibilityNotifications.beginHeistScope()
        defer { heist.cancel() }

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Unstable"), "unstable")])
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(screen: screen),
            elementsByKey: [:]
        )

        _ = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome,
            notificationWindow: action
        )

        XCTAssertEqual(
            bagman.accessibilityNotifications.pendingEvents().map(\.kind),
            [.announcement],
            "The action window may claim attribution, but the heist owns the stream lifetime."
        )
    }

    func testPostActionFailedSettleReturnsObservedUnsettledEvidenceInsteadOfBaseline() async {
        let object = NSObject()
        let screen = InterfaceObservation.makeForTests([
            .init(element(label: "Unstable"), heistId: "unstable", object: object),
        ])
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(screen: screen),
            elementsByKey: [:]
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
            bagman.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label,
            "Unstable"
        )
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence?.liveCapture.object(for: "unstable"))
        XCTAssertTrue(bagman.latestSettledSemanticObservationInvalidated)
    }

    func testPublicInterfaceReadsSettledTruthNotFailedSettleDiagnosticEvidence() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(bagman.interface().projectedElements.compactMap(\.label), ["Settled"])
        XCTAssertEqual(bagman.semanticInterface().projectedElements.compactMap(\.label), ["Settled"])
        XCTAssertNil(bagman.resolveVisibleTarget(literalTarget(ElementPredicate(label: "Timeout"))).resolved)
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
            finalObservation: SettleSessionFinalObservation(screen: screenA),
            elementsByKey: [:]
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

    func testExploredAdmissionRejectsStaleSourceAndAcceptsCurrentSourceMerge() {
        let objectA = NSObject()
        let objectB = NSObject()
        let screenA = InterfaceObservation.makeForTests([
            .init(label: "Catalog", heistId: "header", traits: .header),
            .init(label: "Old", heistId: "old", object: objectA),
        ])
        let screenB = InterfaceObservation.makeForTests([
            .init(label: "Catalog", heistId: "header", traits: .header),
            .init(label: "Current", heistId: "current", object: objectB),
        ])
        bagman.recordParsedObservedEvidence(screenA)
        let staleExploration = Navigation.ExploredScreen(
            screen: screenA,
            manifest: .init(),
            generationDisposition: .preservesGeneration,
            discoveryCommitPolicy: .mergeIntoInterface
        )
        bagman.recordParsedObservedEvidence(screenB)

        XCTAssertNil(bagman.semanticObservationStream.commitExploredDiscoveryObservation(staleExploration))

        var currentExploration = Navigation.SemanticExploration(baseline: .interfaceMemory(screenA))
        currentExploration.absorb(screenB)
        let currentScreen = currentExploration.screen
        let currentResult = bagman.semanticObservationStream.commitExploredDiscoveryObservation(
            Navigation.ExploredScreen(
                screen: currentScreen,
                manifest: currentExploration.manifest,
                generationDisposition: currentExploration.generationDisposition,
                discoveryCommitPolicy: currentExploration.discoveryCommitPolicy
            )
        )

        XCTAssertEqual(currentScreen.captureToken, screenB.captureToken)
        XCTAssertTrue(currentScreen.liveCapture.object(for: "current") === objectB)
        XCTAssertNotNil(currentScreen.findElement(heistId: "old"))
        XCTAssertNotNil(currentScreen.findElement(heistId: "current"))
        XCTAssertNotNil(currentResult)
    }

    func testSettledSemanticObservationWaiterCompletesOnLaterObservation() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let waiter = Task {
            await bagman.observeSettledSemanticObservation(scope: .visible, after: firstSequence, timeout: 1)
        }

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Second")
    }

    func testUnbaselinedSettledObservationWaiterRequiresNextObservation() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)

        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(scope: .visible, after: nil, timeout: 1)
        }

        for _ in 0..<10 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Second")
    }

    func testInvalidatedSettledObservationIsNotReturnedAsCleanTruth() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(scope: .visible, after: nil, timeout: 1)
        }

        for _ in 0..<10 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Second")
    }

    func testTargetResolutionAfterTimeoutUsesSettledWorldNotDiagnosticEvidence() {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled Action"), "settled_action")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout Action"), "timeout_action")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Settled Action"))).resolved)
        XCTAssertNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Timeout Action"))).resolved)
        XCTAssertEqual(
            bagman.matchScreenElements(ElementPredicate(label: "Timeout Action"), limit: 1),
            []
        )
        XCTAssertEqual(bagman.interfaceTree.orderedElements.first?.element.label, "Settled Action")
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label, "Timeout Action")
    }

    func testDiscoveryWaiterIgnoresVisibleObservation() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(
                scope: .discovery,
                after: firstSequence,
                timeout: nil
            )
        }

        for _ in 0..<10 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let visible = InterfaceObservation.makeForTests(elements: [(element(label: "Visible"), "visible")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(visible)
        XCTAssertEqual(bagman.latestSettledSemanticObservation?.sequence, 2)
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let discovery = InterfaceObservation.makeForTests(elements: [(element(label: "Discovery"), "discovery")])
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let observation = await waiter.value
        XCTAssertEqual(observation?.scope, .discovery)
        XCTAssertEqual(observation?.sequence, 3)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Discovery")
    }

    func testVisibleWaiterCompletesWithVisibleProjectionFromDiscoveryObservation() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(
                scope: .visible,
                after: firstSequence,
                timeout: nil
            )
        }

        for _ in 0..<10 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let visibleDiscovery = element(label: "Visible Discovery")
        let knownDiscovery = element(label: "Known Discovery")
        let discovery = InterfaceObservation.makeForTests(
            elements: [(visibleDiscovery, "visible_discovery")],
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
            observation?.observation.screen.orderedElements.compactMap(\.element.label),
            ["Visible Discovery"]
        )
        XCTAssertEqual(
            observation?.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible Discovery"]
        )
        XCTAssertEqual(bagman.latestSettledSemanticObservation?.scope, .discovery)
        XCTAssertEqual(bagman.interfaceElementIDs, ["first", "known_discovery", "visible_discovery"])
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 0)
    }

    func testCleanVisibleEventAfterDiscoveryReturnsVisibleProjection() async {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let visibleDiscovery = element(label: "Visible Discovery")
        let knownDiscovery = element(label: "Known Discovery")
        let discovery = InterfaceObservation.makeForTests(
            elements: [(visibleDiscovery, "visible_discovery")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    knownDiscovery,
                    heistId: "known_discovery",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let observation = await bagman.observeSettledSemanticObservation(
            scope: .visible,
            after: firstSequence,
            timeout: nil
        )

        XCTAssertEqual(observation?.scope, .visible)
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(
            observation?.observation.screen.orderedElements.compactMap(\.element.label),
            ["Visible Discovery"]
        )
        XCTAssertEqual(
            observation?.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible Discovery"]
        )
    }

    func testObservationCycleFulfillmentUsesScopeFulfillmentRule() async {
        let cycles = SemanticObservationCycles()

        let visibleWaiter = Task { @MainActor in
            await cycles.waitForNextCycle(scope: .visible, after: cycles.cursor())
        }
        for _ in 0..<10 where cycles.waiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(cycles.waiterCount, 1)

        let discoveryCycle = startedCycle(cycles.beginCycle(scope: .discovery))
        cycles.finishCycle(token: discoveryCycle, didObserve: true)
        await visibleWaiter.value
        XCTAssertEqual(cycles.waiterCount, 0)

        let discoveryWaiter = Task { @MainActor in
            await cycles.waitForNextCycle(scope: .discovery, after: cycles.cursor())
        }
        for _ in 0..<10 where cycles.waiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(cycles.waiterCount, 1)

        let visibleCycle = startedCycle(cycles.beginCycle(scope: .visible))
        cycles.finishCycle(token: visibleCycle, didObserve: true)
        XCTAssertEqual(cycles.waiterCount, 1)

        let fulfillingDiscoveryCycle = startedCycle(cycles.beginCycle(scope: .discovery))
        cycles.finishCycle(token: fulfillingDiscoveryCycle, didObserve: true)
        await discoveryWaiter.value
        XCTAssertEqual(cycles.waiterCount, 0)
    }

    func testObservationCycleCancellationAllowsReplacementAndIgnoresStaleFinish() {
        let cycles = SemanticObservationCycles()
        let staleCycle = startedCycle(cycles.beginCycle(scope: .visible))

        cycles.cancelRunningCycle()

        let replacementCycle = startedCycle(cycles.beginCycle(scope: .visible))
        XCTAssertEqual(cycles.finishCycle(token: staleCycle, didObserve: true), .ignoredStaleToken)
        XCTAssertEqual(cycles.finishCycle(token: replacementCycle, didObserve: true), .completed)
        XCTAssertEqual(cycles.cursor(), replacementCycle.cursor)
    }

    func testObservationCycleWithoutObservationCannotReuseStaleToken() {
        let cycles = SemanticObservationCycles()
        let staleCycle = startedCycle(cycles.beginCycle(scope: .visible))
        XCTAssertEqual(cycles.finishCycle(token: staleCycle, didObserve: false), .completed)

        let replacementCycle = startedCycle(cycles.beginCycle(scope: .visible))

        XCTAssertNotEqual(replacementCycle.cursor, staleCycle.cursor)
        XCTAssertEqual(cycles.finishCycle(token: staleCycle, didObserve: true), .ignoredStaleToken)
        XCTAssertEqual(cycles.finishCycle(token: replacementCycle, didObserve: true), .completed)
    }

    func testObservationCycleCompletedBeforeWaitRegistrationIsNotLost() async {
        let cycles = SemanticObservationCycles()
        let cursor = cycles.cursor()
        let cycle = startedCycle(cycles.beginCycle(scope: .discovery))
        cycles.finishCycle(token: cycle, didObserve: true)

        await cycles.waitForNextCycle(scope: .visible, after: cursor)

        XCTAssertEqual(cycles.waiterCount, 0)
    }

    func testSettledEventAvailableDuringWaitRegistrationIsNotLost() async {
        let screen = InterfaceObservation.makeForTests(elements: [(element(label: "Current"), "current")])
        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let waiters = SemanticObservationSettledWaiters()

        let result = await waiters.wait(
            scope: .visible,
            afterSequence: 0,
            timeout: nil,
            currentEvent: { event }
        )

        XCTAssertEqual(result?.sequence, event.sequence)
        XCTAssertEqual(waiters.count, 0)
    }

    func testDiscoveryProjectionMaintainsFullTrace() throws {
        let firstVisible = element(label: "First Visible")
        let firstKnown = element(label: "First Known")
        let first = InterfaceObservation.makeForTests(
            elements: [(firstVisible, "first_visible")],
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
            elements: [(secondVisible, "second_visible")],
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
            ["First Known", "First Visible"]
        )
        XCTAssertEqual(
            try XCTUnwrap(event.trace.captures.last).interface.projectedElements.compactMap(\.label).sorted(),
            ["First Known", "First Visible", "Second Known", "Second Visible"]
        )
        XCTAssertEqual(
            bagman.interfaceElementIDs,
            ["first_known", "first_visible", "second_known", "second_visible"]
        )
    }

    func testPublicInterfaceProjectionStaysVisibleWhileSemanticProjectionIncludesKnownElements() throws {
        let visible = element(label: "Visible", traits: .button)
        let known = element(label: "Known", traits: .button)
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 800)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 400))
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [
                "visible": InterfaceTree.Element(heistId: "visible", scrollMembership: nil, element: visible),
                "known": InterfaceTree.Element(heistId: "known", scrollMembership: nil, element: known),
            ],
            hierarchy: [.container(container, children: [.element(visible, traversalIndex: 0)])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            heistIdsByPath: [TreePath([0, 0]): "visible"],
            firstResponderHeistId: nil,
        )
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

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
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
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
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Second"), "second")])
        var discoveryCount = 0
        bagman.startPassiveSemanticObservation {
            discoveryCount += 1
            self.bagman.recordParsedObservedEvidence(second)
            return Navigation.ExploredScreen(
                screen: second,
                manifest: .init(),
                generationDisposition: .preservesGeneration,
                discoveryCommitPolicy: .mergeIntoInterface
            )
        }

        let observation = await bagman.observeSettledSemanticObservation(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertGreaterThanOrEqual(discoveryCount, 1)
        XCTAssertGreaterThan(observation?.sequence ?? 0, firstSequence ?? 0)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Second")
    }

    func testPassiveObservationLeaseDoesNotRunDiscoveryWithoutDiscoveryDemand() async {
        let discovery = InterfaceObservation.makeForTests(elements: [(element(label: "Discovery"), "discovery")])
        var discoveryCount = 0
        bagman.startPassiveSemanticObservation {
            discoveryCount += 1
            self.bagman.recordParsedObservedEvidence(discovery)
            return Navigation.ExploredScreen(
                screen: discovery,
                manifest: .init(),
                generationDisposition: .preservesGeneration,
                discoveryCommitPolicy: .mergeIntoInterface
            )
        }

        XCTAssertEqual(bagman.subscribedObservationScope(), .visible)
        await Task.yield()
        let discoveryCountBeforeDemand = discoveryCount
        XCTAssertEqual(discoveryCountBeforeDemand, 0)

        let observation = await bagman.observeSettledSemanticObservation(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertGreaterThanOrEqual(discoveryCount, discoveryCountBeforeDemand + 1)
        XCTAssertEqual(observation?.scope, .discovery)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Discovery")
    }

    func testTimeoutZeroDoesNotInvokeDiscoveryWithoutPassiveObserver() async {
        let observation = await bagman.observeSettledSemanticObservation(
            scope: .discovery,
            after: nil,
            timeout: 0
        )

        XCTAssertNil(observation)
    }

    func testStopPassiveSemanticObservationCancelsWaiters() async {
        let waiter = Task {
            await bagman.observeSettledSemanticObservation(scope: .visible, after: nil, timeout: 10)
        }

        for _ in 0..<20 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        bagman.stopPassiveSemanticObservation()

        let observation = await waiter.value
        XCTAssertNil(observation)
    }

    func testCancelledSettledObservationWaiterUnregisters() async {
        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(scope: .visible, after: nil, timeout: 10)
        }

        for _ in 0..<20 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        waiter.cancel()
        for _ in 0..<20 where bagman.semanticObservationStream.settledWaiterCount != 0 {
            await Task.yield()
        }

        let observation = await waiter.value
        XCTAssertNil(observation)
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 0)

        let late = InterfaceObservation.makeForTests(elements: [(element(label: "Late"), "late")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(late)
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 0)
    }

    func testCancelledObservationCycleWaiterUnregisters() async {
        var discoveryContinuation: CheckedContinuation<Void, Never>?
        var discoveryScreen: InterfaceObservation?
        func resumeDiscovery(returning screen: InterfaceObservation?) {
            discoveryScreen = screen
            let continuation = discoveryContinuation
            discoveryContinuation = nil
            continuation?.resume()
        }

        bagman.startPassiveSemanticObservation {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                discoveryContinuation = continuation
            }
            let screen = discoveryScreen
            discoveryScreen = nil
            return screen.map {
                self.bagman.recordParsedObservedEvidence($0)
                return Navigation.ExploredScreen(
                    screen: $0,
                    manifest: .init(),
                    generationDisposition: .preservesGeneration,
                    discoveryCommitPolicy: .mergeIntoInterface
                )
            }
        }
        defer { resumeDiscovery(returning: nil) }

        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(scope: .discovery, after: nil, timeout: 0)
        }

        for _ in 0..<20 where bagman.semanticObservationStream.cycleWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.cycleWaiterCount, 1)

        waiter.cancel()
        for _ in 0..<20 where bagman.semanticObservationStream.cycleWaiterCount != 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.cycleWaiterCount, 0)

        resumeDiscovery(returning: InterfaceObservation.makeForTests(elements: [(element(label: "Discovery"), "discovery")]))
        let observation = await waiter.value
        XCTAssertNil(observation)
        XCTAssertEqual(bagman.semanticObservationStream.cycleWaiterCount, 0)
    }

    func testContainerTargetResolutionUsesCommittedSemanticContainers() {
        let path = TreePath([0, 1])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(CGRect(x: 0, y: 900, width: 240, height: 80)),
            customActions: [.init(name: "Archive")]
        )
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
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

        let result = bagman.resolveContainerTarget(
            .identifier("actions"),
            ordinal: nil
        )
        switch result {
        case .resolved(let resolved):
            XCTAssertEqual(resolved.path, path)
            XCTAssertEqual(resolved.containerName, "semantic_actions__actions")
            XCTAssertEqual(resolved.contentFrame?.origin.y, 900)
        case .notFound, .ambiguous:
            XCTFail("Expected semantic container resolution, got \(result.diagnostics)")
        }
    }

    func testContainerTargetResolutionReportsStructuredFacts() {
        let primaryPath = TreePath([0, 1])
        let secondaryPath = TreePath([0, 2])
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
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

        let ambiguous = bagman.resolveContainerTarget(
            .matching(.type(.semanticGroup), .semantic(.label("Actions"))),
            ordinal: nil
        )
        guard case .ambiguous(let facts) = ambiguous else {
            XCTFail("Expected structured ambiguity, got \(ambiguous)")
            return
        }
        XCTAssertEqual(facts.matchedCount, 2)
        XCTAssertEqual(facts.resolutionScope, .interface)
        XCTAssertEqual(
            facts.candidates.map { $0.container.containerPredicateFacts.identifier },
            ["primary", "secondary"]
        )
        XCTAssertEqual(facts.candidates.map(\.containerName), ["actions_primary", "actions_secondary"])
        XCTAssertTrue(ambiguous.diagnostics.contains("container target is ambiguous across 2 containers"))
        XCTAssertFalse(ambiguous.diagnostics.contains("containerName"))

        let outOfRange = bagman.resolveContainerTarget(
            .matching(.type(.semanticGroup), .semantic(.label("Actions"))),
            ordinal: 3
        )
        guard case .notFound(let notFoundFacts) = outOfRange else {
            XCTFail("Expected structured ordinal miss, got \(outOfRange)")
            return
        }
        XCTAssertEqual(notFoundFacts.reason, .ordinalOutOfRange(requested: 3, matchCount: 2))
        XCTAssertEqual(notFoundFacts.resolutionScope, .interface)
        XCTAssertTrue(outOfRange.diagnostics.contains("container target ordinal 3"))
        XCTAssertTrue(outOfRange.diagnostics.contains("target an element inside the intended region"))
    }

    func testGeneratedConcreteTargetUsesMinimumPredicateSelector() throws {
        let selected = element(label: "Mode", value: "A", traits: [.button, .selected])
        let other = element(label: "Mode", value: "B", traits: [.button, .selected])
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(elements: [
            (selected, "mode_a"),
            (other, "mode_b"),
        ]))

        let treeElement = try XCTUnwrap(bagman.interfaceElement(heistId: "mode_a"))

        XCTAssertEqual(
            bagman.minimumUniqueTarget(for: treeElement),
            literalTarget(ElementPredicate([
                .label("Mode"),
                .traits([.button]),
                .value("A"),
            ]))
        )
    }

    // MARK: - Live Geometry Replay

    func testMatcherTargetAcquiresFreshLiveGeometry() throws {
        let sourceFrame = CGRect(x: 10, y: 20, width: 80, height: 44)
        let sourcePoint = CGPoint(x: 50, y: 42)
        let sourceElement = AccessibilityElement.make(
            label: "Quantity",
            value: "0",
            identifier: "quantity_stepper",
            traits: .adjustable,
            shape: .frame(AccessibilityRect(sourceFrame)),
            activationPoint: sourcePoint
        )
        let sourceScreen = InterfaceObservation.makeForTests(elements: [(sourceElement, "quantity_0")])

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
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [(currentElement, "quantity_1")],
            objects: ["quantity_1": object]
        ))

        let sourceScreenElement = try XCTUnwrap(sourceScreen.orderedElements.first {
            $0.element.identifier == "quantity_stepper"
        })
        let sourceElements = sourceScreen.orderedElements.map {
            PredicateSelectionSubjectElement(id: $0.heistId.predicateSelectionElementId, element: $0.element)
        }
        let executableTarget = try XCTUnwrap(
            MinimumPredicateSelector.minimumUniquePredicate(
                for: sourceScreenElement.heistId.predicateSelectionElementId,
                in: sourceElements
            )
        ).target

        guard case .predicate(let matcher, let ordinal) = executableTarget else {
            XCTFail("Expected semantic replay target to carry matcher identity, got \(executableTarget)")
            return
        }
        XCTAssertEqual(matcher.checks, [.identifier(.exact("quantity_stepper"))])
        XCTAssertNil(ordinal)

        guard let resolved = bagman.resolveTarget(executableTarget).resolved else {
            XCTFail("Expected semantic replay selector to resolve against current screen")
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
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
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

        let target = literalTarget(ElementPredicate(identifier: "rotor_host"))
        let settled = try XCTUnwrap(bagman.resolveTarget(target).resolved)
        XCTAssertEqual(settled.element.shape.frame, staleFrame)
        XCTAssertEqual(settled.element.bhResolvedActivationPoint, stalePoint)

        let visible = try XCTUnwrap(bagman.resolveVisibleTarget(target).resolved)
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
        let target = literalTarget(ElementPredicate(label: .exact("Shared Control"), traits: [.adjustable]))
        let semanticTarget = try XCTUnwrap(bagman.resolveVisibleTarget(target).resolved)

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
        XCTAssertEqual(bagman.resolveVisibleTarget(target).resolved?.heistId, committedId)
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
        let screen = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        bagman.semanticObservationStream.commitVisibleObservationForTesting(screen)

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

        let resolved = bagman.resolveContainerTarget(.identifier("actions"), ordinal: nil)
        guard case .resolved(let semanticTarget) = resolved else {
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

    func testViewportUpdatePreservesKnownDiscoveryUnionWhenRefreshingSameScreen() {
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
            bagman.resolveTarget(literalTarget(ElementPredicate(label: "Controls Demo", traits: [.button]))).resolved?.heistId,
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
        XCTAssertEqual(previousDiscovery.id, "controls_demo")
        bagman.semanticObservationStream.commitDiscoveryObservationForTesting(previousDiscovery)

        let currentHeader = element(label: "ButtonHeist Demo", traits: .header)
        let sharedCurrentAction = element(label: "Shared Action", traits: .button)
        let currentVisible = InterfaceObservation.makeForTests(elements: [
            (currentHeader, "buttonheist_demo"),
            (sharedCurrentAction, "shared_action"),
        ])
        XCTAssertEqual(currentVisible.id, "buttonheist_demo")
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

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
        guard let resolved = result.resolved else {
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

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Cancel")))
        guard let resolved = result.resolved else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.heistId, "button_cancel")
        XCTAssertEqual(resolved.element.label, "Cancel")
    }

    func testScopedTargetResolvesDescendantOfContainerLabel() {
        let checkoutContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Checkout", value: nil), identifier: nil,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let cartContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Cart", value: nil), identifier: nil,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let checkoutPay = element(label: "Pay", traits: .button)
        let cartPay = element(label: "Pay", traits: .button)
        let checkoutPath = TreePath([0, 0])
        let cartPath = TreePath([1, 0])
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
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
                .container(checkoutContainer, children: [.element(checkoutPay, traversalIndex: 0)]),
                .container(cartContainer, children: [.element(cartPay, traversalIndex: 1)]),
            ],
            heistIdsByPath: [
                checkoutPath: "checkout_pay",
                cartPath: "cart_pay",
            ],
            firstResponderHeistId: nil
        ))

        let result = bagman.resolveTarget(.within(
            container: .label("Checkout"),
            target: .label("Pay")
        ))

        XCTAssertEqual(result.resolved?.heistId, "checkout_pay")
    }

    func testScopedTargetResolutionUsesRepairedSemanticInterfaceProjection() {
        let containerPath = TreePath([30])
        let staleElementPath = TreePath([2])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Order Entry", value: nil), identifier: "order_entry_container",
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let reviewSale = element(label: "Review Sale", identifier: "review_sale", traits: .button)
        let screen = InterfaceObservation.makeForTests(
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
        bagman.installScreenForTesting(screen)
        let target = AccessibilityTarget.within(
            container: .identifier("order_entry_container"),
            target: literalTarget(ElementPredicate(identifier: "review_sale"))
        )

        let interfaceMatches = ElementMatchGraph(interface: TheStash.WireConversion.toSemanticInterface(from: screen.tree))
            .resolve(target)
            .elements

        XCTAssertEqual(interfaceMatches.elements.map(\.identifier), ["review_sale"])
        XCTAssertEqual(bagman.resolveTarget(target).resolved?.heistId, "review_sale")
    }

    func testMatcherAmbiguousReturnsCandidates() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let candidates = result.candidates
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

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let candidates = result.candidates
        XCTAssertEqual(facts.candidates[0].identifier, "save1")
        XCTAssertEqual(facts.candidates[1].identifier, "save2")
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

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Cancel")))
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

    func testMatcherNearMissDiagnostics() {
        let element = element(label: "Save", value: "draft")
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save", value: "final")))
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

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Long")))
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

    func testEmptyMatcherMissIncludesNextTargetingMove() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate()))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("<empty predicate>"))
        XCTAssertTrue(diagnostics.contains("Next:"))
        XCTAssertTrue(diagnostics.contains("exact label"))
    }

    // MARK: - TargetResolution Convenience Properties

    func testResolvedPropertyReturnsNilForNotFound() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "nope")))
        XCTAssertNil(result.resolved)
    }

    func testResolvedPropertyReturnsNilForAmbiguous() {
        let save1 = element(label: "Save")
        let save2 = element(label: "Save")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
        XCTAssertNil(result.resolved)
    }

    func testDiagnosticsEmptyForResolved() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "OK")))
        XCTAssertEqual(result.diagnostics, "")
    }

    // MARK: - Ambiguous Matcher Diagnostics

    func testAmbiguousMatcherReturnsDiagnostics() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
        XCTAssertTrue(result.diagnostics.contains("2 elements match"), "Should return ambiguous message: \(result.diagnostics)")
    }

    func testEmptyScreenReturnsCompactSummary() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Anything")))
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

        let result0 = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 0))
        XCTAssertEqual(result0.resolved?.element.value, "draft")

        let result1 = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 1))
        XCTAssertEqual(result1.resolved?.element.value, "final")

        let result2 = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 2))
        XCTAssertEqual(result2.resolved?.element.value, "archive")
    }

    func testOrdinalOutOfBoundsReturnsNotFound() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 5))
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

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
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

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Duplicate")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        XCTAssertEqual(facts.matchedCount, 12)
        XCTAssertEqual(facts.candidates.count, 10)
        XCTAssertTrue(result.diagnostics.contains("10+ elements match"))
        XCTAssertTrue(result.diagnostics.contains("... and more"))
    }

    func testOrdinalZeroOnSingleMatchSucceeds() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 0))
        XCTAssertNotNil(result.resolved)
        XCTAssertEqual(result.resolved?.element.label, "Save")
    }

    func testNegativeOrdinalReturnsNotFound() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: -1))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalNegative(-1))
        XCTAssertTrue(diagnostics.contains("non-negative"))
        XCTAssertTrue(diagnostics.contains("Next:"))
    }

    func testOrdinalZeroOnNoMatchReturnsNotFound() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Nonexistent"), ordinal: 0))
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

    // MARK: - Early-Exit Matching

    func testMatchesWithLimitStopsEarly() {
        let elements = (0..<10).map { index in
            element(label: "Item", value: "\(index)")
        }
        for (index, element) in elements.enumerated() {
            register(element, heistId: HeistId(rawValue: "item_\(index)"), index: index)
        }

        let limit3 = bagman.latestObservedLiveHierarchy.matches(ElementPredicate(label: "Item"), limit: 3)
        XCTAssertEqual(limit3.count, 3)
        XCTAssertEqual(limit3[0].value, "0")
        XCTAssertEqual(limit3[1].value, "1")
        XCTAssertEqual(limit3[2].value, "2")
    }

    func testMatchesWithLimitExceedingCountReturnsAll() {
        let element1 = element(label: "Save", value: "one")
        let element2 = element(label: "Save", value: "two")
        register(element1, heistId: "save_1", index: 0)
        register(element2, heistId: "save_2", index: 1)

        let results = bagman.latestObservedLiveHierarchy.matches(ElementPredicate(label: "Save"), limit: 10)
        XCTAssertEqual(results.count, 2)
    }

    func testMatchesWithLimitZeroReturnsEmpty() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let results = bagman.latestObservedLiveHierarchy.matches(ElementPredicate(label: "Save"), limit: 0)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Select + Mark Presented Tracking

    func testSelectElementsReturnsSortedByTraversalOrder() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.selectElements()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].heistId, "button_save")
    }

    // MARK: - Known Semantic State

    /// Matcher-based resolution reads the committed semantic state. Viewport
    /// reachability is handled later by action execution.
    func testMatcherResolvesKnownEntryOutsideLiveHierarchy() {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        register(onScreen, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "long_list_button")

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Long List", traits: [.button])))
        guard case .resolved(let target) = result else {
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

        let result = bagman.resolveVisibleTarget(literalTarget(ElementPredicate(label: "Save")))

        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected visible ambiguity, got \(result)")
            return
        }
        XCTAssertEqual(facts.candidates.count, 2)
        XCTAssertEqual(facts.resolutionScope, .viewport)
        let diagnostics = result.diagnostics
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testResolveVisibleTargetPreservesExplicitOrdinalOutOfRange() {
        let save = element(label: "Save", traits: .button)
        register(save, heistId: "button_save", index: 0)

        let result = bagman.resolveVisibleTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 4))

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

        let knownResult = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Below Fold")))
        XCTAssertEqual(knownResult.resolved?.heistId, "below_fold_button")

        let visibleResult = bagman.resolveVisibleTarget(literalTarget(ElementPredicate(label: "Below Fold")))
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

    func testResolveFirstViewportMatchIgnoresOffViewportEntry() {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Below Fold", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "below_fold_button")

        XCTAssertNil(bagman.resolveFirstVisibleMatch(literalTarget(ElementPredicate(label: "Below Fold"))))
        XCTAssertEqual(
            bagman.resolveFirstVisibleMatch(literalTarget(ElementPredicate(label: "Visible")))?.heistId,
            "button_visible"
        )
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

        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.container(scrollContainer, children: [])],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Below Fold"))).resolved else {
            XCTFail("Off-viewport entry should still resolve")
            return
        }
        XCTAssertEqual(resolved.heistId, "below_fold_button")
        XCTAssertNil(bagman.treeElement(heistId: "below_fold_button", in: .viewport))
        guard case .objectUnavailable = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Off-viewport target should not have a live action target")
            return
        }

        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.container(scrollContainer, children: [.element(offScreen, traversalIndex: 0)])],
            heistIdsByPath: [elementPath: entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        let refreshed = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Below Fold"))).resolved
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
        bagman.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(visible, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Visible"))).resolved else {
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

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Below Fold"))).resolved)
    }

    func testResolveTargetFindsLivePredicateInViewport() {
        let element = element(label: "Visible", traits: .button)
        register(element, heistId: "visible_button", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Visible"))).resolved)
    }

    func testResolveTargetHonorsExplicitOrdinal() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 1)).resolved)
        guard case .notFound = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"), ordinal: 2)) else {
            XCTFail("Expected out-of-range ordinal to fail closed")
            return
        }
    }

    func testRegisteredElementResolvesWithoutMarkPresented() {
        let element = element(label: "Combobox", traits: .button)
        register(element, heistId: "button_combobox", index: 0)

        // Element resolves immediately — no markPresented gate
        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Combobox")))
        XCTAssertNotNil(result.resolved)
    }

    // MARK: - ElementMatchSet Parity

    func testElementMatchSetMatchesStashCountAndOrder() {
        let screen = installMatcherParityScreen()
        let projectedElements = screen.orderedElements.map { TheStash.WireConversion.convert($0.element) }
        let matchGraph = ElementMatchGraph(elements: projectedElements)

        struct MatchCase {
            let name: String
            let predicate: ElementPredicate
            let expectedIds: [HeistId]
        }

        let cases = [
            MatchCase(
                name: "exact substring miss",
                predicate: ElementPredicate(label: "Draft"),
                expectedIds: []
            ),
            MatchCase(
                name: "exact excludes partial sibling",
                predicate: ElementPredicate(label: "Save"),
                expectedIds: ["save_button"]
            ),
            MatchCase(
                name: "contains",
                predicate: ElementPredicate(label: .contains("Save")),
                expectedIds: ["save_button", "save_draft_button"]
            ),
            MatchCase(
                name: "prefix",
                predicate: ElementPredicate(label: .prefix("Save")),
                expectedIds: ["save_button", "save_draft_button"]
            ),
            MatchCase(
                name: "suffix",
                predicate: ElementPredicate(label: .suffix("Draft")),
                expectedIds: ["save_draft_button"]
            ),
            MatchCase(
                name: "identifier",
                predicate: ElementPredicate(identifier: "search_field"),
                expectedIds: ["search_field"]
            ),
            MatchCase(
                name: "value",
                predicate: ElementPredicate(value: "Complete"),
                expectedIds: ["done_button"]
            ),
            MatchCase(
                name: "traits",
                predicate: ElementPredicate(traits: [.selected]),
                expectedIds: ["done_button"]
            ),
            MatchCase(
                name: "exclude traits",
                predicate: ElementPredicate.element(
                    .label("Delete"),
                    .exclude(.traits([.notEnabled]))
                ),
                expectedIds: ["delete_first"]
            ),
            MatchCase(
                name: "compound checks",
                predicate: ElementPredicate.element(
                    .label(.exact("Done")),
                    .identifier(.exact("done_button")),
                    .value(.exact("Complete")),
                    .exclude(.traits([.notEnabled])),
                    traits: [.button, .selected]
                ),
                expectedIds: ["done_button"]
            ),
            MatchCase(
                name: "empty predicate",
                predicate: ElementPredicate(),
                expectedIds: []
            ),
            MatchCase(
                name: "duplicate labels",
                predicate: ElementPredicate(label: "Delete"),
                expectedIds: ["delete_first", "delete_second"]
            ),
        ]

        for testCase in cases {
            let stashMatches = bagman.matchScreenElements(testCase.predicate, limit: 100)
            let setMatches = matchGraph.resolve(testCase.predicate).elements

            XCTAssertEqual(stashMatches.map(\.heistId), testCase.expectedIds, testCase.name)
            XCTAssertEqual(
                setMatches.map(matchSignature),
                stashMatches.map { matchSignature($0.element) },
                testCase.name
            )
        }
    }

    func testElementMatchSetMatchesResolveTargetBehavior() throws {
        let screen = installMatcherParityScreen()
        let projectedElements = screen.orderedElements.map { TheStash.WireConversion.convert($0.element) }
        let matchGraph = ElementMatchGraph(elements: projectedElements)

        enum ExpectedResolution {
            case resolved(HeistId)
            case ambiguous(Int)
            case notFound
            case ordinalOutOfRange(requested: Int, matchCount: Int)
        }

        struct ResolutionCase {
            let name: String
            let target: AccessibilityTarget
            let expected: ExpectedResolution
        }

        let cases = [
            ResolutionCase(
                name: "unique",
                target: literalTarget(ElementPredicate(label: "Done")),
                expected: .resolved("done_button")
            ),
            ResolutionCase(
                name: "ambiguous",
                target: literalTarget(ElementPredicate(label: "Delete")),
                expected: .ambiguous(2)
            ),
            ResolutionCase(
                name: "not found",
                target: literalTarget(ElementPredicate(label: "Missing")),
                expected: .notFound
            ),
            ResolutionCase(
                name: "ordinal select",
                target: literalTarget(ElementPredicate(label: "Delete"), ordinal: 1),
                expected: .resolved("delete_second")
            ),
            ResolutionCase(
                name: "ordinal out of range",
                target: literalTarget(ElementPredicate(label: "Delete"), ordinal: 2),
                expected: .ordinalOutOfRange(requested: 2, matchCount: 2)
            ),
        ]

        for testCase in cases {
            let setMatches = matchGraph.resolve(testCase.target)
            let resolution = bagman.resolveTarget(testCase.target)

            switch testCase.expected {
            case .resolved(let expectedId):
                let expectedElement = try XCTUnwrap(screen.findElement(heistId: expectedId)?.element, testCase.name)
                let resolved = try XCTUnwrap(resolution.resolved, testCase.name)
                XCTAssertEqual(resolved.heistId, expectedId, testCase.name)
                XCTAssertEqual(setMatches.elements.count, 1, testCase.name)
                XCTAssertEqual(
                    setMatches.elements.elements.map(matchSignature),
                    [matchSignature(expectedElement)],
                    testCase.name
                )
            case .ambiguous(let expectedCount):
                guard case .ambiguous(let facts) = resolution else {
                    return XCTFail("Expected ambiguous for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.matchedCount, expectedCount, testCase.name)
                XCTAssertEqual(setMatches.elements.count, expectedCount, testCase.name)
            case .notFound:
                guard case .notFound(let facts) = resolution else {
                    return XCTFail("Expected notFound for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.reason, .noMatches, testCase.name)
                XCTAssertTrue(setMatches.isEmpty, testCase.name)
            case .ordinalOutOfRange(let requested, let matchCount):
                guard case .notFound(let facts) = resolution else {
                    return XCTFail("Expected notFound for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: requested, matchCount: matchCount), testCase.name)
                XCTAssertTrue(setMatches.isEmpty, testCase.name)
            }
        }
    }

    // MARK: - Exact Default and Explicit Broad Matches

    /// A partial label must return `.notFound`; broad matching is explicit.
    func testSubstringPartialLabelReturnsNotFound() {
        let save = element(label: "Save Draft", traits: .button)
        register(save, heistId: "button_save_draft", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
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
    func testExplicitContainsLabelResolves() {
        let save = element(label: "Save Draft", traits: .button)
        register(save, heistId: "button_save_draft", index: 0)

        let result = bagman.resolveTarget(.predicate(.label(.contains("Save"))))
        guard let resolved = result.resolved else {
            XCTFail("Explicit contains predicate should resolve, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save Draft")
    }

    /// Exact equality (after case-insensitive comparison) still resolves.
    func testExactLabelCaseInsensitiveResolves() {
        let save = element(label: "Save", traits: .button)
        register(save, heistId: "button_save", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"))).resolved)
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "save"))).resolved)
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "SAVE"))).resolved)
    }

    /// Typography folding still works under exact-or-miss: a label with a smart
    /// apostrophe resolves against an ASCII apostrophe matcher.
    func testTypographyFoldingPreservedUnderExactSemantics() {
        let dontSkip = element(label: "Don\u{2019}t skip", traits: .button)
        register(dontSkip, heistId: "button_dont_skip", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Don't skip"))).resolved)
    }

    /// When two labels share a partial substring, exact must win outright
    /// (no ambiguity). This was Finding 5's regression case.
    func testExactMatchWinsOverPartialSiblings() {
        let save = element(label: "Save")
        let saveDraft = element(label: "Save Draft")
        register(save, heistId: "button_save", index: 0)
        register(saveDraft, heistId: "button_save_draft", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save")))
        guard let resolved = result.resolved else {
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
        guard case .notFound = bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save"))) else {
            XCTFail("Expected substring-only matcher to miss")
            return
        }
        // Exact label still resolves to present.
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ElementPredicate(label: "Save Draft"))).resolved)
    }

    /// Server-side and client-side matchers must agree on the same input.
    /// Regression for Finding 4 (matcher contract drift).
    func testServerAndClientMatchersAgreeOnSameInput() {
        let element = element(label: "Save Draft", value: "x", identifier: "save_btn", traits: .button)
        let matcher = ElementPredicate(label: "Save Draft", traits: [.button])

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
        let partial = ElementPredicate(label: "Save")
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
        let asciiMatcher = ElementPredicate(label: "Don't skip")

        XCTAssertTrue(asciiMatcher.matches(smart))
        XCTAssertTrue(heist.matches(asciiMatcher),
                      "Client-side must fold typography just like server-side")
    }
}

private func startedCycle(
    _ admission: SemanticObservationCycles.CycleAdmission,
    file: StaticString = #filePath,
    line: UInt = #line
) -> SemanticObservationCycles.Cycle {
    guard case .started(let cycle) = admission else {
        XCTFail("Expected semantic observation cycle to start", file: file, line: line)
        fatalError("Expected semantic observation cycle to start")
    }
    return cycle
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
