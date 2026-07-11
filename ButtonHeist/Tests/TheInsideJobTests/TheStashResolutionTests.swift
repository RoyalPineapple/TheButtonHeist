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
        // current Screen value treats as distinct.
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

    /// Register an element into the current Screen. Rebuilds the screen value
    /// on every call so individual tests don't have to think about the
    /// memberwise init. `Screen.heistIdsByPath` is the live matcher lookup.
    private func register(_ element: AccessibilityElement, heistId: HeistId, index: Int) {
        hierarchyNodes.append(.element(element, traversalIndex: index))
        registeredEntries.append((element, heistId, true))
        rebuildScreen()
    }

    /// Element registration that only adds the leaf to the heistId→entry map
    /// without putting it in the live hierarchy. Known entries return nil from
    /// visible-scoped accessors but still participate in semantic target
    /// resolution.
    private func registerOffScreen(_ element: AccessibilityElement, heistId: HeistId) {
        registeredEntries.append((element, heistId, false))
        rebuildScreen()
    }

    private func rebuildScreen() {
        var elements: [HeistId: Screen.ScreenElement] = [:]
        var heistIdsByPath: [TreePath: HeistId] = [:]
        var liveIndex = 0
        for entry in registeredEntries where entry.isLive {
            heistIdsByPath[TreePath([liveIndex])] = entry.heistId
            liveIndex += 1
        }
        for entry in registeredEntries {
            let screenElement = Screen.ScreenElement(
                heistId: entry.heistId,
                scrollMembership: nil,
                element: entry.element
            )
            elements[entry.heistId] = screenElement
        }
        bagman.installScreenForTesting(Screen(
            elements: elements,
            hierarchy: hierarchyNodes,
            heistIdsByPath: heistIdsByPath,
            firstResponderHeistId: nil,
        ))
    }

    private func installMatcherParityScreen() -> Screen {
        nextElementYOffset = 0
        let screen = Screen.makeForTests(elements: [
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

    func testWorldStoreCommitKeepsLiveEvidenceOutOfSettledProjection() {
        var worldStore = WorldStore()
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        let screen = Screen.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        let result = worldStore.commitVisible(screen)

        XCTAssertTrue(result.observedEvidence.liveCapture.object(for: "save") === liveObject)
        XCTAssertNil(result.settledScreen.liveCapture.object(for: "save"))
        XCTAssertNil(worldStore.screen.liveCapture.object(for: "save"))
        XCTAssertEqual(worldStore.element(heistId: "save")?.element.label, "Save")
    }

    func testWorldStoreVisibleCommitDropsDiscoveryMemoryAfterNavigation() {
        var worldStore = WorldStore()
        let bottom = element(label: "Bottom Row", traits: .button)
        let staleOffscreen = element(label: "Stale Row", traits: .button)
        let discovery = Screen.makeForTests(
            elements: [(bottom, "bottom_row")],
            offViewport: [
                Screen.OffViewportEntry(
                    staleOffscreen,
                    heistId: "shared_row",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        worldStore.commitDiscovery(discovery)

        let freshVisible = element(label: "Fresh Row", traits: .button)
        let refreshedTop = Screen.makeForTests(elements: [(freshVisible, "shared_row")])
        let result = worldStore.commitVisible(refreshedTop)

        XCTAssertEqual(result.settledScreen.visibleIds, ["shared_row"])
        XCTAssertEqual(result.settledScreen.knownIds, ["shared_row"])
        XCTAssertEqual(worldStore.element(heistId: "shared_row")?.element.label, "Fresh Row")
        XCTAssertNil(worldStore.element(heistId: "bottom_row"))
    }

    func testWorldStoreVisibleCommitKeepsDiscoveryMemoryWhenVisibleIdentityPairsWithNewId() {
        var worldStore = WorldStore()
        let previousVisible = element(label: "Counter", value: "1", traits: .button)
        let discoveryOnly = element(label: "Details", traits: .button)
        let discovery = Screen.makeForTests(
            elements: [(previousVisible, "counter_old")],
            offViewport: [
                Screen.OffViewportEntry(
                    discoveryOnly,
                    heistId: "details",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        worldStore.commitDiscovery(discovery)

        let currentVisible = element(label: "Counter", value: "2", traits: .button)
        let result = worldStore.commitVisible(Screen.makeForTests(elements: [(currentVisible, "counter_new")]))

        XCTAssertEqual(result.settledScreen.visibleIds, ["counter_new"])
        XCTAssertEqual(result.settledScreen.knownIds, ["counter_new", "details"])
        XCTAssertNil(worldStore.element(heistId: "counter_old"))
        XCTAssertEqual(worldStore.element(heistId: "details")?.element.label, "Details")
    }

    func testVisibleExplorationBaselineDropsStaleDiscoveryEntriesSharingContainerName() {
        let visibleWord = element(label: "Words", traits: .staticText)
        let staleHomeButton = element(label: "Auto-Settle Fixtures", traits: .button)
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let currentVisible = Screen(
            elements: [
                "words_header": Screen.ScreenElement(
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
        var elements = currentVisible.semantic.elements
        elements["home_button"] = Screen.ScreenElement(
            heistId: "home_button",
            scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: staleHomeButton
        )
        let pollutedSettledScreen = Screen(
            semantic: SemanticScreen(
                elements: elements,
                containers: currentVisible.semantic.containers
            ),
            liveCapture: currentVisible.liveCapture
        )
        let baseline = bagman.visibleExplorationBaseline(from: pollutedSettledScreen)

        XCTAssertEqual(baseline.knownIds, ["words_header"])
        XCTAssertEqual(baseline.visibleIds, ["words_header"])
        XCTAssertNil(baseline.findElement(heistId: "home_button"))
        XCTAssertEqual(baseline.liveCapture.hierarchy, currentVisible.liveCapture.hierarchy)
    }

    func testActionDiscoveryBaselineDropsStaleDiscoveryMemoryWhenScreenIdChanges() throws {
        let previousHeader = element(label: "Controls Demo", traits: .header)
        let sharedPreviousAction = element(label: "Shared Action", traits: .button)
        let staleOffscreen = element(label: "Stale Offscreen", traits: .button)
        let previousDiscovery = Screen.makeForTests(
            elements: [
                (previousHeader, "controls_demo"),
                (sharedPreviousAction, "shared_action"),
            ],
            offViewport: [
                Screen.OffViewportEntry(
                    staleOffscreen,
                    heistId: "stale_offscreen",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        XCTAssertEqual(previousDiscovery.id, "controls_demo")
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(previousDiscovery)

        let currentHeader = element(label: "ButtonHeist Demo", traits: .header)
        let sharedCurrentAction = element(label: "Shared Action", traits: .button)
        let currentVisible = Screen.makeForTests(elements: [
            (currentHeader, "buttonheist_demo"),
            (sharedCurrentAction, "shared_action"),
        ])
        XCTAssertEqual(currentVisible.id, "buttonheist_demo")
        bagman.recordParsedObservedEvidence(currentVisible)

        let baseline = bagman.actionDiscoveryBaseline()

        XCTAssertEqual(baseline.id, "buttonheist_demo")
        XCTAssertEqual(baseline.visibleIds, ["buttonheist_demo", "shared_action"])
        XCTAssertEqual(baseline.knownIds, ["buttonheist_demo", "shared_action"])
        XCTAssertNil(baseline.findElement(heistId: "controls_demo"))
        XCTAssertNil(baseline.findElement(heistId: "stale_offscreen"))
    }

    func testLatestSettledSemanticObservationAdvancesMonotonically() {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)
        let firstObservation = bagman.latestSettledSemanticObservation

        let second = Screen.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(second)
        let secondObservation = bagman.latestSettledSemanticObservation

        XCTAssertNotNil(firstObservation)
        XCTAssertNotNil(secondObservation)
        XCTAssertEqual(firstObservation?.sequence, 1)
        XCTAssertEqual(secondObservation?.sequence, 2)
        XCTAssertEqual(secondObservation?.screen.orderedElements.first?.element.label, "Second")
    }

    func testCleanVisibleSettleCommitUpdatesSettledSemanticTruth() {
        let screen = Screen.makeForTests(elements: [(element(label: "Settled"), "settled")])

        bagman.semanticObservationStream.commitSettledVisibleObservation(screen)

        XCTAssertEqual(bagman.settledSemanticScreen.orderedElements.first?.element.label, "Settled")
        XCTAssertFalse(bagman.latestSettledSemanticObservationInvalidated)
        XCTAssertNil(bagman.latestFailedSettleDiagnosticEvidence)
    }

    func testSettledSemanticObservationEventCarriesPreviousTraceAndDelta() throws {
        let first = Screen.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
        ])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)
        let firstEvent = try XCTUnwrap(bagman.latestSettledSemanticObservationEvent)

        XCTAssertEqual(firstEvent.sequence, 1)
        XCTAssertNil(firstEvent.previous)
        XCTAssertEqual(firstEvent.trace.captures.count, 1)
        XCTAssertNil(firstEvent.delta)

        let second = Screen.makeForTests(elements: [
            (element(label: "Home", traits: .header), "home"),
            (element(label: "Toast"), "toast"),
        ])
        bagman.semanticObservationStream.commitSettledVisibleObservation(second)
        let secondEvent = try XCTUnwrap(bagman.latestSettledSemanticObservationEvent)

        XCTAssertEqual(secondEvent.sequence, 2)
        XCTAssertEqual(secondEvent.previous?.sequence, 1)
        XCTAssertEqual(secondEvent.trace.captures.count, 2)
        XCTAssertEqual(secondEvent.trace.captures.first?.hash, firstEvent.trace.captures.last?.hash)

        guard case .elementsChanged(let payload)? = secondEvent.delta else {
            return XCTFail("Expected elementsChanged event delta, got \(String(describing: secondEvent.delta))")
        }
        XCTAssertEqual(payload.edits.added.map(\.label), ["Toast"])
    }

    func testVisibleObservationTraceExcludesDiscoveryOnlyElements() throws {
        let visible = element(label: "Custom Rotors", traits: .button)
        let discovered = element(label: "ButtonHeist Demo", traits: .button)
        let discovery = Screen.makeForTests(
            elements: [(visible, "custom_rotors")],
            offViewport: [
                Screen.OffViewportEntry(
                    discovered,
                    heistId: "buttonheist_demo",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(discovery)

        let refreshedVisible = Screen.makeForTests(elements: [(visible, "custom_rotors")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(refreshedVisible)

        let event = try XCTUnwrap(bagman.latestSettledSemanticObservationEvent)
        XCTAssertEqual(event.scope, .visible)
        XCTAssertEqual(bagman.knownIds, ["buttonheist_demo", "custom_rotors"])

        let labels = try XCTUnwrap(event.trace.captures.last)
            .interface
            .projectedElements
            .compactMap(\.label)
        XCTAssertEqual(labels, ["Custom Rotors"])
        XCTAssertFalse(labels.contains("ButtonHeist Demo"))
    }

    func testDiagnosticEvidenceInvalidatesLatestSettledObservationWithoutReplacingIt() {
        let settled = Screen.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(settled)
        let sequence = bagman.latestSettledSemanticObservation?.sequence

        let diagnostic = Screen.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(bagman.latestSettledSemanticObservation?.sequence, sequence)
        XCTAssertEqual(bagman.settledSemanticScreen.orderedElements.first?.element.label, "Settled")
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label, "Timeout")
        XCTAssertTrue(bagman.latestSettledSemanticObservationInvalidated)
        XCTAssertEqual(
            bagman.resolveVisibleTarget(.predicate(ElementPredicate(label: "Timeout"))).resolved?.element.label,
            "Timeout"
        )
    }

    func testObservedEvidenceUpdatesVisibleWorldWithoutReplacingSettledTruth() {
        let settled = Screen.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(settled)

        let observed = Screen.makeForTests(elements: [(element(label: "Observed"), "observed")])
        bagman.recordParsedObservedEvidence(observed)

        XCTAssertEqual(bagman.settledSemanticScreen.orderedElements.first?.element.label, "Settled")
        XCTAssertNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Observed"))).resolved)
        XCTAssertEqual(
            bagman.resolveVisibleTarget(.predicate(ElementPredicate(label: "Observed"))).resolved?.element.label,
            "Observed"
        )
        XCTAssertEqual(bagman.visibleElementIds, ["observed"])
    }

    func testLiveVisibleEntriesUseFreshObservedRevealMetadataOverSettledCache() throws {
        let row = element(label: "Row", traits: .button)
        let staleEntry = Screen.ScreenElement(
            heistId: "row",
            scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: 100),
            element: row
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(Screen(
            elements: ["row": staleEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        ))

        let freshEntry = Screen.ScreenElement(
            heistId: "row",
            scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: 500),
            element: row
        )
        bagman.recordParsedObservedEvidence(Screen(
            elements: ["row": freshEntry],
            hierarchy: [.element(row, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): "row"],
            firstResponderHeistId: nil,
        ))

        XCTAssertEqual(bagman.liveVisibleScreen.findElement(heistId: "row")?.scrollMembership?.index, 500)
        XCTAssertEqual(try XCTUnwrap(bagman.liveScreenElement(heistId: "row")).scrollMembership?.index, 500)
    }

    func testLiveVisibleEntriesDoNotPreserveSettledRevealMetadataWhenFreshObservationHasNone() throws {
        let row = element(label: "Row", traits: .button)
        let staleEntry = Screen.ScreenElement(
            heistId: "row",
            scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: row
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(Screen(
            elements: ["row": staleEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        ))

        let freshEntry = Screen.ScreenElement(
            heistId: "row",
            scrollMembership: nil,
            element: row
        )
        bagman.recordParsedObservedEvidence(Screen(
            elements: ["row": freshEntry],
            hierarchy: [.element(row, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): "row"],
            firstResponderHeistId: nil,
        ))

        XCTAssertNil(bagman.liveVisibleScreen.findElement(heistId: "row")?.scrollMembership)
        XCTAssertNil(try XCTUnwrap(bagman.liveScreenElement(heistId: "row")).scrollMembership)
    }

    func testCancelledNoScreenSettleDoesNotPublishSettledTruth() async {
        let settled = Screen.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(settled)
        let sequence = bagman.latestSettledSemanticObservation?.sequence

        let outcome = SettleSession.Outcome(
            outcome: .cancelled(timeMs: 1),
            events: [],
            finalScreen: nil,
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
        XCTAssertEqual(bagman.settledSemanticScreen.orderedElements.first?.element.label, "Settled")
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
        let screen = Screen.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": screenObject]
        )
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged,
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(identity),
            associatedElement: .none
        )

        let evidence = bagman.resolveAccessibilityNotificationEvidence([event], in: screen)

        XCTAssertEqual(
            evidence.first?.notificationData,
            .unresolvedObject(AccessibilityNotificationObjectPayload(className: "NSObject", summary: nil))
        )
    }

    func testAccessibilityNotificationObjectIdentityResolvesIntoReferenceScreen() {
        let payloadObject = NSObject()
        let source = Screen.makeForTests([
            .init(element(label: "Old", traits: .button), heistId: "old"),
            .init(element(label: "A acid", traits: .button), heistId: "a_acid", object: payloadObject),
        ])
        let reference = Screen.makeForTests(elements: [
            (element(label: "Section A", traits: .header), "section_a_header"),
            (element(label: "A acid", traits: .button), "a_acid"),
        ])
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged,
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(AccessibilityNotificationObjectIdentity(
                object: payloadObject,
                className: "NSObject",
                summary: nil
            )),
            associatedElement: .none
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

    func testFailedSettleClearsPendingAccessibilityNotifications() async {
        let screen = Screen.makeForTests(elements: [(element(label: "Unstable"), "unstable")])
        bagman.accessibilityNotifications.record(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalScreen: screen,
            elementsByKey: [:]
        )

        _ = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )

        XCTAssertEqual(bagman.accessibilityNotifications.pendingEvents().count, 0)
    }

    func testCleanPostActionSettleRequiresActionWindowToClaimAccessibilityNotifications() async {
        let screen = Screen.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.accessibilityNotifications.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let outcome = SettleSession.Outcome(
            outcome: .settled(timeMs: 1),
            events: [],
            finalScreen: screen,
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

    func testPostActionFailedSettlePreservesPendingAccessibilityNotificationsDuringHeistScope() async {
        let heist = bagman.accessibilityNotifications.beginHeistScope()
        defer { heist.cancel() }

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let screen = Screen.makeForTests(elements: [(element(label: "Unstable"), "unstable")])
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalScreen: screen,
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
        let screen = Screen.makeForTests(elements: [(element(label: "Unstable"), "unstable")])
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalScreen: screen,
            elementsByKey: [:]
        )

        let result = await bagman.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )

        guard case .observedUnsettled(let observedScreen) = result.result else {
            return XCTFail("Expected observed unsettled settle evidence")
        }
        XCTAssertEqual(observedScreen.orderedElements.first?.element.label, "Unstable")
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label, "Unstable")
        XCTAssertTrue(bagman.latestSettledSemanticObservationInvalidated)
    }

    func testPublicInterfaceReadsSettledTruthNotFailedSettleDiagnosticEvidence() {
        let settled = Screen.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(settled)

        let diagnostic = Screen.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(bagman.interface().projectedElements.compactMap(\.label), ["Settled"])
        XCTAssertEqual(bagman.semanticInterface().projectedElements.compactMap(\.label), ["Settled"])
        XCTAssertEqual(
            bagman.resolveVisibleTarget(.predicate(ElementPredicate(label: "Timeout"))).resolved?.element.label,
            "Timeout"
        )
    }

    func testSettledSemanticObservationWaiterCompletesOnLaterObservation() async {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let waiter = Task {
            await bagman.observeSettledSemanticObservation(scope: .visible, after: firstSequence, timeout: 1)
        }

        let second = Screen.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Second")
    }

    func testUnbaselinedSettledObservationWaiterRequiresNextObservation() async {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)

        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(scope: .visible, after: nil, timeout: 1)
        }

        for _ in 0..<10 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let second = Screen.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Second")
    }

    func testInvalidatedSettledObservationIsNotReturnedAsCleanTruth() async {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)

        let diagnostic = Screen.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        let waiter = Task { @MainActor in
            await bagman.observeSettledSemanticObservation(scope: .visible, after: nil, timeout: 1)
        }

        for _ in 0..<10 where bagman.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let second = Screen.makeForTests(elements: [(element(label: "Second"), "second")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(second)

        let observation = await waiter.value
        XCTAssertEqual(observation?.sequence, 2)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Second")
    }

    func testTargetResolutionAfterTimeoutUsesSettledWorldNotDiagnosticEvidence() {
        let settled = Screen.makeForTests(elements: [(element(label: "Settled Action"), "settled_action")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(settled)

        let diagnostic = Screen.makeForTests(elements: [(element(label: "Timeout Action"), "timeout_action")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Settled Action"))).resolved)
        XCTAssertNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Timeout Action"))).resolved)
        XCTAssertEqual(
            bagman.matchScreenElements(ElementPredicate(label: "Timeout Action"), limit: 1),
            []
        )
        XCTAssertEqual(bagman.settledSemanticScreen.orderedElements.first?.element.label, "Settled Action")
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.orderedElements.first?.element.label, "Timeout Action")
    }

    func testDiscoveryWaiterIgnoresVisibleObservation() async {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)
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

        let visible = Screen.makeForTests(elements: [(element(label: "Visible"), "visible")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(visible)
        XCTAssertEqual(bagman.latestSettledSemanticObservation?.sequence, 2)
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 1)

        let discovery = Screen.makeForTests(elements: [(element(label: "Discovery"), "discovery")])
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(discovery)

        let observation = await waiter.value
        XCTAssertEqual(observation?.scope, .discovery)
        XCTAssertEqual(observation?.sequence, 3)
        XCTAssertEqual(observation?.observation.screen.orderedElements.first?.element.label, "Discovery")
    }

    func testVisibleWaiterCompletesWithVisibleProjectionFromDiscoveryObservation() async {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)
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
        let discovery = Screen.makeForTests(
            elements: [(visibleDiscovery, "visible_discovery")],
            offViewport: [
                Screen.OffViewportEntry(
                    knownDiscovery,
                    heistId: "known_discovery",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(discovery)

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
        XCTAssertEqual(bagman.knownIds, ["known_discovery", "visible_discovery"])
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 0)
    }

    func testCleanVisibleEventAfterDiscoveryReturnsVisibleProjection() async {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(first)
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let visibleDiscovery = element(label: "Visible Discovery")
        let knownDiscovery = element(label: "Known Discovery")
        let discovery = Screen.makeForTests(
            elements: [(visibleDiscovery, "visible_discovery")],
            offViewport: [
                Screen.OffViewportEntry(
                    knownDiscovery,
                    heistId: "known_discovery",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(discovery)

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
            await cycles.waitForNextCycle(scope: .visible, after: cycles.baselineCycle())
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
            await cycles.waitForNextCycle(scope: .discovery, after: cycles.baselineCycle())
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
        XCTAssertEqual(cycles.baselineCycle(), 1)
    }

    func testDiscoveryProjectionMaintainsFullTrace() throws {
        let firstVisible = element(label: "First Visible")
        let firstKnown = element(label: "First Known")
        let first = Screen.makeForTests(
            elements: [(firstVisible, "first_visible")],
            offViewport: [
                Screen.OffViewportEntry(
                    firstKnown,
                    heistId: "first_known",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(first)

        let secondVisible = element(label: "Second Visible")
        let secondKnown = element(label: "Second Known")
        let second = Screen.makeForTests(
            elements: [(secondVisible, "second_visible")],
            offViewport: [
                Screen.OffViewportEntry(
                    secondKnown,
                    heistId: "second_known",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        let event = bagman.semanticObservationStream.commitSettledDiscoveryObservation(second)

        XCTAssertEqual(event.scope, .discovery)
        XCTAssertEqual(event.trace.captures.count, 2)
        XCTAssertEqual(
            try XCTUnwrap(event.trace.captures.first).interface.projectedElements.compactMap(\.label).sorted(),
            ["First Known", "First Visible"]
        )
        XCTAssertEqual(
            try XCTUnwrap(event.trace.captures.last).interface.projectedElements.compactMap(\.label).sorted(),
            ["Second Known", "Second Visible"]
        )
    }

    func testPublicInterfaceProjectionStaysVisibleWhileSemanticProjectionIncludesKnownElements() throws {
        let visible = element(label: "Visible", traits: .button)
        let known = element(label: "Known", traits: .button)
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 800)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 400))
        )
        let screen = Screen(
            elements: [
                "visible": Screen.ScreenElement(heistId: "visible", scrollMembership: nil, element: visible),
                "known": Screen.ScreenElement(heistId: "known", scrollMembership: nil, element: known),
            ],
            hierarchy: [.container(container, children: [.element(visible, traversalIndex: 0)])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            heistIdsByPath: [TreePath([0, 0]): "visible"],
            firstResponderHeistId: nil,
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(screen)

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
        bagman.installScreenForTesting(Screen(
            elements: [
                "repeat_button_1": Screen.ScreenElement(
                    heistId: "repeat_button_1",
                    scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: 100),
                    element: repeated
                ),
                "repeat_button_2": Screen.ScreenElement(
                    heistId: "repeat_button_2",
                    scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: 500),
                    element: repeated
                ),
            ],
            hierarchy: [
                .element(repeated, traversalIndex: 0),
                .element(repeated, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): "repeat_button_1",
                TreePath([1]): "repeat_button_2",
            ],
            firstResponderHeistId: nil,
        ))

        XCTAssertEqual(
            bagman.settledSemanticScreen.findElement(heistId: "repeat_button_1")?.scrollMembership?.index,
            100
        )
        XCTAssertEqual(
            bagman.settledSemanticScreen.findElement(heistId: "repeat_button_2")?.scrollMembership?.index,
            500
        )
    }

    func testTimeoutZeroTurnsObservationCycleBeforeReturningCleanLatest() async {
        let first = Screen.makeForTests(elements: [(element(label: "First"), "first")])
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(first)
        let firstSequence = bagman.latestSettledSemanticObservation?.sequence

        let second = Screen.makeForTests(elements: [(element(label: "Second"), "second")])
        var discoveryCount = 0
        bagman.startPassiveSemanticObservation {
            discoveryCount += 1
            return second
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
        let discovery = Screen.makeForTests(elements: [(element(label: "Discovery"), "discovery")])
        var discoveryCount = 0
        bagman.startPassiveSemanticObservation {
            discoveryCount += 1
            return discovery
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

        let late = Screen.makeForTests(elements: [(element(label: "Late"), "late")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(late)
        XCTAssertEqual(bagman.semanticObservationStream.settledWaiterCount, 0)
    }

    func testCancelledObservationCycleWaiterUnregisters() async {
        var discoveryContinuation: CheckedContinuation<Void, Never>?
        var discoveryScreen: Screen?
        func resumeDiscovery(returning screen: Screen?) {
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
            return screen
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

        resumeDiscovery(returning: Screen.makeForTests(elements: [(element(label: "Discovery"), "discovery")]))
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
        bagman.installScreenForTesting(Screen(
            semantic: SemanticScreen(
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
            liveCapture: .empty
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
        bagman.installScreenForTesting(Screen(
            semantic: SemanticScreen(
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
            liveCapture: .empty
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
        XCTAssertEqual(facts.resolutionScope, .known)
        XCTAssertEqual(facts.candidates.map(\.identifier), ["primary", "secondary"])
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
        XCTAssertEqual(notFoundFacts.resolutionScope, .known)
        XCTAssertTrue(outOfRange.diagnostics.contains("container target ordinal 3"))
        XCTAssertTrue(outOfRange.diagnostics.contains("target an element inside the intended region"))
    }

    func testGeneratedConcreteTargetUsesMinimumPredicateSelector() throws {
        let selected = element(label: "Mode", value: "A", traits: [.button, .selected])
        let other = element(label: "Mode", value: "B", traits: [.button, .selected])
        bagman.installScreenForTesting(Screen.makeForTests(elements: [
            (selected, "mode_a"),
            (other, "mode_b"),
        ]))

        let screenElement = try XCTUnwrap(bagman.knownElement(heistId: "mode_a"))

        XCTAssertEqual(
            bagman.minimumUniqueTarget(for: screenElement),
            .predicate(ElementPredicate([
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
        let sourceScreen = Screen.makeForTests(elements: [(sourceElement, "quantity_0")])

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
        bagman.installScreenForTesting(Screen.makeForTests(
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

    func testVisibleResolutionUsesFreshLiveGeometryWithoutReplacingSettledTruth() throws {
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
        bagman.installScreenForTesting(Screen.makeForTests(
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
        bagman.recordParsedObservedEvidence(Screen.makeForTests(
            elements: [(freshElement, "rotor_host")],
            objects: ["rotor_host": liveObject]
        ))

        let target: ElementTarget = .predicate(ElementPredicate(identifier: "rotor_host"))
        let settled = try XCTUnwrap(bagman.resolveTarget(target).resolved)
        XCTAssertEqual(settled.element.shape.frame, staleFrame)
        XCTAssertEqual(settled.element.bhResolvedActivationPoint, stalePoint)

        let visible = try XCTUnwrap(bagman.resolveVisibleTarget(target).resolved)
        XCTAssertEqual(visible.element.shape.frame, freshFrame)
        XCTAssertEqual(visible.element.bhResolvedActivationPoint, freshPoint)

        guard case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: settled) else {
            return XCTFail("Expected fresh live action target")
        }
        XCTAssertEqual(liveTarget.frame, freshFrame)
        XCTAssertEqual(liveTarget.activationPoint, freshPoint)
        XCTAssertNotEqual(liveTarget.frame, liveObject.accessibilityFrame)
        XCTAssertNotEqual(liveTarget.activationPoint, liveObject.accessibilityActivationPoint)
    }

    func testVisibleSettleCommitStripsLiveHandlesFromSettledProjection() {
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        liveObject.accessibilityFrame = CGRect(x: 10, y: 10, width: 100, height: 44)
        let screen = Screen.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        bagman.semanticObservationStream.commitSettledVisibleObservation(screen)

        XCTAssertNotNil(bagman.liveObject(for: "save"))
        XCTAssertNil(bagman.settledSemanticScreen.liveCapture.object(for: "save"))
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
        let settledObservationScreen = Screen(
            semantic: SemanticScreen(
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
            liveCapture: LiveCapture(
                hierarchy: [.container(staleContainer, children: [])],
                containerNamesByPath: [path: "actions"],
                elementRefs: [:],
                containerRefsByPath: [:],
                firstResponderHeistId: nil,
            )
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(settledObservationScreen)
        let liveScreen = Screen(
            semantic: SemanticScreen(
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
            liveCapture: LiveCapture(
                hierarchy: [.container(freshContainer, children: [])],
                containerNamesByPath: [path: "actions"],
                elementRefs: [:],
                containerRefsByPath: [path: .init(object: liveObject)],
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

    func testVisibleCommitPreservesKnownDiscoveryUnionWhenRefreshingSameScreen() {
        let controls = element(label: "Controls Demo", traits: .button)
        let customRotors = element(label: "Custom Rotors", traits: .button)
        let discovery = Screen.makeForTests(
            elements: [(customRotors, "custom_rotors")],
            offViewport: [
                Screen.OffViewportEntry(
                    controls,
                    heistId: "controls_demo",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(discovery)

        let refreshedBottom = Screen.makeForTests(elements: [(customRotors, "custom_rotors")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(refreshedBottom)

        XCTAssertEqual(bagman.visibleIds, ["custom_rotors"])
        XCTAssertEqual(bagman.knownIds, ["controls_demo", "custom_rotors"])
        XCTAssertEqual(
            bagman.resolveTarget(.predicate(ElementPredicate(label: "Controls Demo", traits: [.button]))).resolved?.heistId,
            "controls_demo"
        )
    }

    func testVisibleCommitDoesNotPreserveKnownOnlyMemoryForDisjointKnownViewport() {
        let bottom = element(label: "Bottom Row", traits: .button)
        let staleOffscreen = element(label: "Stale Row", traits: .button)
        let discovery = Screen.makeForTests(
            elements: [(bottom, "bottom_row")],
            offViewport: [
                Screen.OffViewportEntry(
                    staleOffscreen,
                    heistId: "shared_row",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(discovery)

        let freshVisible = element(label: "Fresh Row", traits: .button)
        let refreshedTop = Screen.makeForTests(elements: [(freshVisible, "shared_row")])
        bagman.semanticObservationStream.commitSettledVisibleObservation(refreshedTop)

        XCTAssertEqual(bagman.visibleIds, ["shared_row"])
        XCTAssertEqual(bagman.knownIds, ["shared_row"])
        XCTAssertEqual(bagman.knownElement(heistId: "shared_row")?.element.label, "Fresh Row")
        XCTAssertNil(bagman.knownElement(heistId: "bottom_row"))
    }

    func testVisibleCommitDropsDiscoveryMemoryWhenScreenIdChangesDespiteSharedVisibleElement() {
        let previousHeader = element(label: "Controls Demo", traits: .header)
        let sharedPreviousAction = element(label: "Shared Action", traits: .button)
        let staleOffscreen = element(label: "Stale Offscreen", traits: .button)
        let previousDiscovery = Screen.makeForTests(
            elements: [
                (previousHeader, "controls_demo"),
                (sharedPreviousAction, "shared_action"),
            ],
            offViewport: [
                Screen.OffViewportEntry(
                    staleOffscreen,
                    heistId: "stale_offscreen",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        XCTAssertEqual(previousDiscovery.id, "controls_demo")
        bagman.semanticObservationStream.commitSettledDiscoveryObservation(previousDiscovery)

        let currentHeader = element(label: "ButtonHeist Demo", traits: .header)
        let sharedCurrentAction = element(label: "Shared Action", traits: .button)
        let currentVisible = Screen.makeForTests(elements: [
            (currentHeader, "buttonheist_demo"),
            (sharedCurrentAction, "shared_action"),
        ])
        XCTAssertEqual(currentVisible.id, "buttonheist_demo")
        bagman.semanticObservationStream.commitSettledVisibleObservation(currentVisible)

        XCTAssertEqual(bagman.visibleIds, ["buttonheist_demo", "shared_action"])
        XCTAssertEqual(bagman.knownIds, ["buttonheist_demo", "shared_action"])
        XCTAssertNil(bagman.knownElement(heistId: "controls_demo"))
        XCTAssertNil(bagman.knownElement(heistId: "stale_offscreen"))
    }

    // MARK: - Matcher Resolution

    func testMatcherResolvesUniqueElement() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Cancel")))
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
        bagman.installScreenForTesting(Screen(
            elements: [
                "checkout_pay": Screen.ScreenElement(
                    heistId: "checkout_pay",
                    path: checkoutPath,
                    scrollMembership: nil,
                    element: checkoutPay
                ),
                "cart_pay": Screen.ScreenElement(
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

        let result = bagman.resolveTarget(.within(.label("Checkout"), .label("Pay")))

        XCTAssertEqual(result.resolved?.heistId, "checkout_pay")
    }

    func testMatcherAmbiguousReturnsCandidates() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Cancel")))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save", value: "final")))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Long")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("Long List"), "Should suggest known offscreen candidate: \(diagnostics)")
        // The near-miss names the candidate by its label predicate, not by an
        // agent-facing heistId — that concept was removed.
        XCTAssertTrue(diagnostics.contains("label=\"Long List\""), "Should describe candidate by label predicate: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("offscreen"))
        XCTAssertTrue(diagnostics.contains("unreachable"))
    }

    func testEmptyMatcherMissIncludesNextTargetingMove() {
        let result = bagman.resolveTarget(.predicate(ElementPredicate()))
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
        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "nope")))
        XCTAssertNil(result.resolved)
    }

    func testResolvedPropertyReturnsNilForAmbiguous() {
        let save1 = element(label: "Save")
        let save2 = element(label: "Save")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
        XCTAssertNil(result.resolved)
    }

    func testDiagnosticsEmptyForResolved() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "OK")))
        XCTAssertEqual(result.diagnostics, "")
    }

    // MARK: - Ambiguous Matcher Diagnostics

    func testAmbiguousMatcherReturnsDiagnostics() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
        XCTAssertTrue(result.diagnostics.contains("2 elements match"), "Should return ambiguous message: \(result.diagnostics)")
    }

    func testEmptyScreenReturnsCompactSummary() {
        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Anything")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("known hierarchy is empty"))
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

        let result0 = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 0))
        XCTAssertEqual(result0.resolved?.element.value, "draft")

        let result1 = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 1))
        XCTAssertEqual(result1.resolved?.element.value, "final")

        let result2 = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 2))
        XCTAssertEqual(result2.resolved?.element.value, "archive")
    }

    func testOrdinalOutOfBoundsReturnsNotFound() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 5))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Duplicate")))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 0))
        XCTAssertNotNil(result.resolved)
        XCTAssertEqual(result.resolved?.element.label, "Save")
    }

    func testNegativeOrdinalReturnsNotFound() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: -1))
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
        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Nonexistent"), ordinal: 0))
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Long List", traits: [.button])))
        guard case .resolved(let target) = result else {
            XCTFail("Expected known semantic match, got \(result)")
            return
        }
        XCTAssertEqual(target.heistId, "long_list_button")
    }

    func testScopedHeistIdsSeparateVisibleFromKnownUnion() {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        register(onScreen, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "long_list_button")

        XCTAssertEqual(bagman.ids(in: .visible), ["button_visible"])
        XCTAssertEqual(bagman.ids(in: .known), ["button_visible", "long_list_button"])
        XCTAssertEqual(bagman.visibleIds, bagman.ids(in: .visible))
        XCTAssertEqual(bagman.knownIds, bagman.ids(in: .known))
    }

    func testScopedScreenElementRequiresVisibleScopeForLiveLookup() {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        register(onScreen, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "long_list_button")

        XCTAssertNotNil(bagman.screenElement(heistId: "button_visible", in: .visible))
        XCTAssertNil(bagman.screenElement(heistId: "long_list_button", in: .visible))
        XCTAssertNotNil(bagman.screenElement(heistId: "long_list_button", in: .known))
    }

    func testResolveVisibleTargetFailsClosedForAmbiguousMatcher() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveVisibleTarget(.predicate(ElementPredicate(label: "Save")))

        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected visible ambiguity, got \(result)")
            return
        }
        XCTAssertEqual(facts.candidates.count, 2)
        XCTAssertEqual(facts.resolutionScope, .visible)
        let diagnostics = result.diagnostics
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testResolveVisibleTargetPreservesExplicitOrdinalOutOfRange() {
        let save = element(label: "Save", traits: .button)
        register(save, heistId: "button_save", index: 0)

        let result = bagman.resolveVisibleTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 4))

        guard case .notFound(let facts) = result else {
            XCTFail("Expected ordinal miss, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 4, matchCount: 1))
        XCTAssertEqual(facts.resolutionScope, .visible)
        XCTAssertTrue(diagnostics.contains("ordinal 4 requested"))
        XCTAssertTrue(diagnostics.contains("1 match"))
    }

    func testResolveVisibleTargetRequiresLiveHierarchy() {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Below Fold", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "below_fold_button")

        let knownResult = bagman.resolveTarget(.predicate(ElementPredicate(label: "Below Fold")))
        XCTAssertEqual(knownResult.resolved?.heistId, "below_fold_button")

        let visibleResult = bagman.resolveVisibleTarget(.predicate(ElementPredicate(label: "Below Fold")))
        guard case .notFound(let facts) = visibleResult else {
            XCTFail("Expected visible miss, got \(visibleResult)")
            return
        }
        let diagnostics = visibleResult.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertEqual(facts.resolutionScope, .visible)
        XCTAssertTrue(diagnostics.contains("No match for"))
        XCTAssertTrue(diagnostics.contains("scope: visible"), "Should identify failed resolution scope: \(diagnostics)")
    }

    func testResolveFirstVisibleMatchIgnoresKnownOnlyEntry() {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Below Fold", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "below_fold_button")

        XCTAssertNil(bagman.resolveFirstVisibleMatch(.predicate(ElementPredicate(label: "Below Fold"))))
        XCTAssertEqual(
            bagman.resolveFirstVisibleMatch(.predicate(ElementPredicate(label: "Visible")))?.heistId,
            "button_visible"
        )
    }

    func testKnownOnlyEntryWithStaleObjectIsNotDispatchableUntilVisible() {
        let offScreen = element(label: "Below Fold", traits: .button)
        let object = UIAccessibilityElement(accessibilityContainer: NSObject())
        object.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 44)
        object.accessibilityActivationPoint = CGPoint(x: 50, y: 22)
        let scrollView = UIScrollView()
        let entry = Screen.ScreenElement(
            heistId: "below_fold_button",
            scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: offScreen
        )

        bagman.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(.predicate(ElementPredicate(label: "Below Fold"))).resolved else {
            XCTFail("Known-only entry should still resolve")
            return
        }
        XCTAssertEqual(resolved.heistId, "below_fold_button")
        XCTAssertNil(bagman.screenElement(heistId: "below_fold_button", in: .visible))
        guard case .objectUnavailable = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Known-only target should not have a live action target")
            return
        }

        bagman.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [.element(offScreen, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        let refreshed = bagman.resolveTarget(.predicate(ElementPredicate(label: "Below Fold"))).resolved
        XCTAssertNotNil(bagman.screenElement(heistId: "below_fold_button", in: .visible))
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
        let entry = Screen.ScreenElement(
            heistId: "button_visible",
            scrollMembership: nil,
            element: visible
        )
        bagman.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [.element(visible, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(.predicate(ElementPredicate(label: "Visible"))).resolved else {
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

        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Below Fold"))).resolved)
    }

    func testResolveTargetFindsLivePredicateInViewport() {
        let element = element(label: "Visible", traits: .button)
        register(element, heistId: "visible_button", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Visible"))).resolved)
    }

    func testResolveTargetHonorsExplicitOrdinal() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 1)).resolved)
        guard case .notFound = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"), ordinal: 2)) else {
            XCTFail("Expected out-of-range ordinal to fail closed")
            return
        }
    }

    func testRegisteredElementResolvesWithoutMarkPresented() {
        let element = element(label: "Combobox", traits: .button)
        register(element, heistId: "button_combobox", index: 0)

        // Element resolves immediately — no markPresented gate
        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Combobox")))
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
            let target: ElementTarget
            let expected: ExpectedResolution
        }

        let cases = [
            ResolutionCase(
                name: "unique",
                target: .predicate(ElementPredicate(label: "Done")),
                expected: .resolved("done_button")
            ),
            ResolutionCase(
                name: "ambiguous",
                target: .predicate(ElementPredicate(label: "Delete")),
                expected: .ambiguous(2)
            ),
            ResolutionCase(
                name: "not found",
                target: .predicate(ElementPredicate(label: "Missing")),
                expected: .notFound
            ),
            ResolutionCase(
                name: "ordinal select",
                target: .predicate(ElementPredicate(label: "Delete"), ordinal: 1),
                expected: .resolved("delete_second")
            ),
            ResolutionCase(
                name: "ordinal out of range",
                target: .predicate(ElementPredicate(label: "Delete"), ordinal: 2),
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
                XCTAssertEqual(setMatches.count, 1, testCase.name)
                XCTAssertEqual(setMatches.elements.map(matchSignature), [matchSignature(expectedElement)], testCase.name)
            case .ambiguous(let expectedCount):
                guard case .ambiguous(let facts) = resolution else {
                    return XCTFail("Expected ambiguous for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.matchedCount, expectedCount, testCase.name)
                XCTAssertEqual(setMatches.count, expectedCount, testCase.name)
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

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
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

        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"))).resolved)
        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "save"))).resolved)
        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "SAVE"))).resolved)
    }

    /// Typography folding still works under exact-or-miss: a label with a smart
    /// apostrophe resolves against an ASCII apostrophe matcher.
    func testTypographyFoldingPreservedUnderExactSemantics() {
        let dontSkip = element(label: "Don\u{2019}t skip", traits: .button)
        register(dontSkip, heistId: "button_dont_skip", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Don't skip"))).resolved)
    }

    /// When two labels share a partial substring, exact must win outright
    /// (no ambiguity). This was Finding 5's regression case.
    func testExactMatchWinsOverPartialSiblings() {
        let save = element(label: "Save")
        let saveDraft = element(label: "Save Draft")
        register(save, heistId: "button_save", index: 0)
        register(saveDraft, heistId: "button_save_draft", index: 1)

        let result = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save")))
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
        guard case .notFound = bagman.resolveTarget(.predicate(ElementPredicate(label: "Save"))) else {
            XCTFail("Expected substring-only matcher to miss")
            return
        }
        // Exact label still resolves to present.
        XCTAssertNotNil(bagman.resolveTarget(.predicate(ElementPredicate(label: "Save Draft"))).resolved)
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

#endif
