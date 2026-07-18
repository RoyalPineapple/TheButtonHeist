#if canImport(UIKit)
import Foundation
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for post-action observation and exploration behavior
/// that operate purely against the current `InterfaceObservation` snapshot: failure result
/// assembly, wait-change guards, and semantic discovery observation.
///
/// Success-path post-action observation and `exploreScreen` container iteration
/// require a live window and are covered by integration/benchmark runs.
@MainActor
final class TheBrainsPipelineTests: XCTestCase {
    var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains.stopSemanticObservation()
        brains = nil
        try await super.tearDown()
    }

    func testCaptureSemanticStateKeepsKnownElementsInCanonicalInterface() {
        let visible = AccessibilityElement.make(
            label: "Visible",
            traits: .button,
            respondsToUserInteraction: false
        )
        let offViewport = AccessibilityElement.make(
            label: "Below fold",
            traits: .button,
            respondsToUserInteraction: false
        )
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(visible, HeistId(rawValue: "button_visible"))],
            offViewport: [.init(offViewport, heistId: HeistId(rawValue: "button_below_fold"))]
        ))
        let state = brains.postActionObservation.captureSemanticState()

        XCTAssertEqual(
            Set(state.observation.tree.orderedElements.map(\.heistId)),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertEqual(
            Set(state.interface.projectedElements.compactMap { $0.label }),
            ["Visible", "Below fold"]
        )
    }

    func testVisibleSettledEvidenceKeepsKnownElementsInCanonicalBaseline() {
        let observation = InterfaceObservation.makeForTests(
            elements: [
                (AccessibilityElement.make(label: "Visible", traits: .button), "button_visible"),
            ],
            offViewport: [
                .init(
                    AccessibilityElement.make(label: "Below fold", traits: .button),
                    heistId: "button_below_fold"
                ),
            ]
        )
        let event = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(observation)

        let evidence = brains.postActionObservation.semanticObservation(from: event)

        XCTAssertEqual(
            Set(evidence.baseline.observation.tree.orderedElements.map(\.heistId)),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertEqual(
            Set(evidence.baseline.interface.projectedElements.compactMap(\.label)),
            ["Visible", "Below fold"]
        )
    }

    func testBeforeStateDerivesNeededSemanticProjectionsFromCanonicalInputs() {
        let screen = makeScreen(elements: [("Save", .button, "save")])
        brains.vault.installObservationForTesting(screen)
        let captured = brains.postActionObservation.captureSemanticState()

        let state = PostActionObservation.ObservationBaseline(
            observation: captured.observation,
            capture: captured.capture,
            tripwireSignal: captured.tripwireSignal,
            settledObservationSequence: captured.settledObservationSequence
        )

        XCTAssertEqual(state.elements, screen.tree.orderedElements.map(\.element))
        XCTAssertEqual(state.interface, captured.capture.interface)
        XCTAssertEqual(state.interfaceHash, screen.tree.interfaceHash)
        XCTAssertEqual(state.screenSnapshot, ScreenClassifier.snapshot(of: screen.tree))
        XCTAssertEqual(state.screenId, screen.tree.id)
    }

    func testDiscoveryObservationStateAndTraceUseCanonicalSemanticInterface() throws {
        let viewportObservation = makeDiscoveryObservationProjectionFixture()
        let discoveryInterface = TheVault.WireConversion.discoveryProjection(
            from: viewportObservation.tree
        ).interface
        let semanticInterface = TheVault.WireConversion.toSemanticInterface(from: viewportObservation.tree)
        let traceCapture = brains.postActionObservation.makeTraceCapture(
            interface: semanticInterface,
            sequence: 1,
            observation: viewportObservation,
            tripwireSignal: .empty,
            screenId: viewportObservation.tree.id
        )
        let trace = AccessibilityTrace(capture: traceCapture)
        let settled = SettledObservation(
            sequence: 7,
            scope: .discovery,
            observation: viewportObservation,
            semanticSignal: .empty
        )
        let event = SettledObservationEvent(
            continuity: .sameGeneration,
            settledObservation: settled,
            previous: nil,
            trace: trace
        )
        let observation = brains.postActionObservation.semanticObservation(from: event)

        XCTAssertNotEqual(discoveryInterface.tree, semanticInterface.tree)
        XCTAssertEqual(observation.baseline.interface.tree, semanticInterface.tree)
        XCTAssertEqual(observation.baseline.interface.annotations, semanticInterface.annotations)
        XCTAssertEqual(observation.accessibilityTrace.captures.last?.interface.tree, semanticInterface.tree)
        XCTAssertEqual(observation.accessibilityTrace.captures.last?.interface.annotations, semanticInterface.annotations)
        let predicate = AccessibilityPredicate.exists(.container(.identifier("OffscreenGroup")))
        let resolved = try resolvedPredicate(predicate)
        XCTAssertEqual(
            PredicateEvaluation.evaluate(resolved, expression: predicate, in: observation),
            ExpectationResult(met: true, predicate: predicate)
        )
    }

    func testShouldRecordAccessibilityTraceIgnoresViewportOnlyMovement() {
        let beforeElement = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 0, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: 22),
            respondsToUserInteraction: false
        )
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(beforeElement, HeistId(rawValue: "chicken_tikka_button"))]
        ))
        let baseline = brains.postActionObservation.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: -300, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: -278),
            respondsToUserInteraction: false
        )
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(afterElement, HeistId(rawValue: "chicken_tikka_button"))]
        ))
        let current = brains.postActionObservation.captureSemanticState()
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot,
            notifications: []
        )

        XCTAssertFalse(
            PostActionObservation.shouldRecordAccessibilityTrace(
                baseline: baseline,
                current: current,
                classification: classification
            ),
            "Viewport-only geometry movement updates interaction state but does not become trace history"
        )
    }

    func testShouldRecordAccessibilityTraceRecordsSameScreenSemanticChange() {
        let beforeElement = AccessibilityElement.make(
            label: "Total",
            value: "$4.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(beforeElement, HeistId(rawValue: "total_staticText"))]
        ))
        let baseline = brains.postActionObservation.captureSemanticState()

        let afterElement = AccessibilityElement.make(
            label: "Total",
            value: "$8.00",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(afterElement, HeistId(rawValue: "total_staticText"))]
        ))
        let current = brains.postActionObservation.captureSemanticState()
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot,
            notifications: []
        )

        XCTAssertTrue(
            PostActionObservation.shouldRecordAccessibilityTrace(
                baseline: baseline,
                current: current,
                classification: classification
            ),
            "Same-screen value changes are semantic patches"
        )
    }

    // MARK: - Semantic Discovery Observation

    func testSemanticDiscoveryObservationCommitsUnion() async {
        // Exploration seeds the local union from the interface tree and merges each
        // parse into it. The observation stream commits the completed union as
        // settled discovery truth. There is no pruning — the union is the
        // canonical "all elements seen this cycle".
        // With no scrollable containers in the host hierarchy, semantic discovery
        // reduces to refresh-and-commit, and the seeded entry merges into the
        // live parse rather than being pruned.
        seedScreen(elements: [("Seed", .button, "button_seed")])
        XCTAssertEqual(brains.vault.interfaceTree.elements.count, 1)

        brains.startSemanticObservation()
        let observation = await brains.vault.semanticObservationStream.settledEvent(scope: .discovery, after: nil, timeout: 2)

        // Either the seed survives (no live parse landed and the union still
        // holds it) or it merges with new live entries — either way, the
        // settled screen reflects the committed union, not the pre-explore
        // value alone.
        XCTAssertNotNil(observation)
        XCTAssertGreaterThanOrEqual(brains.vault.interfaceTree.elements.count, 1)
    }

    func testExploreScreenStopsEarlyWhenTargetAlreadyResolved() async throws {
        let screen = try XCTUnwrap(
            brains.vault.refreshLiveCapture(),
            "Expected a live hierarchy in the hosted test app"
        )
        let label = try XCTUnwrap(
            screen.tree.viewportElementIDs
                .compactMap { screen.tree.findElement(heistId: $0)?.element.label }
                .first(where: { !$0.isEmpty }),
            "Expected a labeled viewport element in the hosted test app"
        )

        guard let exploration = await brains.navigation.exploreScreen(
            target: try AccessibilityTarget.label(label).resolve(in: .empty)
        ) else {
            return XCTFail("Expected target exploration to settle")
        }

        XCTAssertEqual(exploration.progress.scrollCount, 0)
        XCTAssertTrue(exploration.progress.pendingScrollPaths.isEmpty)
        XCTAssertTrue(exploration.progress.exploredScrollPaths.isEmpty)
    }

    func testExplorationTerminalResolutionSupportsContainerTargets() throws {
        let observation = makeDiscoveryObservationProjectionFixture()
        let visibleRoot = try AccessibilityTarget.container(.identifier("RootViewController")).resolve(in: .empty)
        let offscreenGroup = try AccessibilityTarget.container(.identifier("OffscreenGroup")).resolve(in: .empty)
        let missing = try AccessibilityTarget.container(.identifier("Missing")).resolve(in: .empty)

        XCTAssertTrue(brains.vault.hasVisibleTerminalResolution(visibleRoot, in: observation.tree))
        XCTAssertFalse(brains.vault.hasVisibleTerminalResolution(offscreenGroup, in: observation.tree))
        XCTAssertFalse(brains.vault.hasVisibleTerminalResolution(missing, in: observation.tree))
    }

    func testSemanticExplorationAddsNestedContainersAfterOuterContainerIsExplored() {
        let outer = makeScrollableContainer(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400),
            contentSize: CGSize(width: 320, height: 1_200)
        )
        let nested = makeScrollableContainer(
            frame: CGRect(x: 20, y: 520, width: 280, height: 240),
            contentSize: CGSize(width: 280, height: 900)
        )
        let outerPath = TreePath([0])
        let nestedPath = TreePath([0, 0])
        let outerEntry = semanticContainer(outer, path: outerPath)
        let nestedEntry = semanticContainer(nested, path: nestedPath)
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))
        exploration.progress.addPendingContainers([outerEntry])

        exploration.markExplored(outerEntry)
        exploration.addDiscoveredContainers([outerEntry, nestedEntry])

        XCTAssertTrue(exploration.progress.exploredScrollPaths.contains(outerPath))
        XCTAssertFalse(exploration.progress.pendingScrollPaths.contains(outerPath))
        XCTAssertTrue(exploration.progress.pendingScrollPaths.contains(nestedPath))
    }

    func testSemanticExplorationAbsorbQueuesScrollContainersFromParsedPage() {
        let outer = makeScrollableContainer(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400),
            contentSize: CGSize(width: 320, height: 1_200)
        )
        let nested = makeScrollableContainer(
            frame: CGRect(x: 20, y: 180, width: 280, height: 240),
            contentSize: CGSize(width: 280, height: 900)
        )
        let page = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(outer, children: [
                    .container(nested, children: [])
                ])
            ],
            firstResponderHeistId: nil,
        )
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))

        exploration.recordCommittedObservation(
            continuity: .sameGeneration,
            scrollableContainers: page.tree.orderedContainers.filter { $0.container.isScrollable }
        )

        XCTAssertTrue(exploration.progress.pendingScrollPaths.contains(TreePath([0])))
        XCTAssertTrue(exploration.progress.pendingScrollPaths.contains(TreePath([0, 0])))
    }

    func testSemanticExplorationAbsorbQueuesNestedContainerWithoutRequeuingExploredOuter() {
        let outer = makeScrollableContainer(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400),
            contentSize: CGSize(width: 320, height: 1_200)
        )
        let nested = makeScrollableContainer(
            frame: CGRect(x: 20, y: 520, width: 280, height: 240),
            contentSize: CGSize(width: 280, height: 900)
        )
        let page = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(outer, children: [
                    .container(nested, children: [])
                ])
            ],
            firstResponderHeistId: nil,
        )
        let outerPath = TreePath([0])
        let nestedPath = TreePath([0, 0])
        let outerEntry = semanticContainer(outer, path: outerPath)
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))
        exploration.progress.addPendingContainers([outerEntry])
        exploration.markExplored(outerEntry)

        exploration.recordCommittedObservation(
            continuity: .sameGeneration,
            scrollableContainers: page.tree.orderedContainers.filter { $0.container.isScrollable }
        )

        XCTAssertTrue(exploration.progress.exploredScrollPaths.contains(outerPath))
        XCTAssertFalse(exploration.progress.pendingScrollPaths.contains(outerPath))
        XCTAssertTrue(exploration.progress.pendingScrollPaths.contains(nestedPath))
    }

    func testSemanticExplorationFinishOwnsExplorationTimestamp() {
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))
        let event = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(.empty)

        let result = exploration.finish(
            startTime: CACurrentMediaTime() - 0.01,
            event: event,
            didMoveViewport: false
        )

        XCTAssertGreaterThan(result.progress.explorationTime, 0)
        XCTAssertFalse(result.didMoveViewport)
        XCTAssertEqual(result.event.settledObservation.observation.tree, InterfaceObservation.empty.tree)
        XCTAssertEqual(
            result.event.settledObservation.observation.liveCapture.snapshot,
            InterfaceObservation.empty.liveCapture.snapshot
        )
    }

    func testSemanticOnlyScrollableContainerIsQueuedForSwipeExploration() {
        let path = TreePath([0])
        let container = semanticContainer(
            makeScrollableContainer(
                frame: CGRect(x: 0, y: 0, width: 320, height: 400),
                contentSize: CGSize(width: 320, height: 1_200)
            ),
            path: path
        )
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(.empty))

        exploration.recordCommittedObservation(
            continuity: .sameGeneration,
            scrollableContainers: [container]
        )

        XCTAssertNil(brains.vault.liveScrollableContainerView(forPath: path))
        XCTAssertTrue(exploration.progress.pendingScrollPaths.contains(path))
    }

    // MARK: - Helpers

    func makeDiscoveryObservationProjectionFixture() -> InterfaceObservation {
        let rootPath = TreePath([0])
        let visiblePath = TreePath([0, 0])
        let offscreenContainerPath = TreePath([0, 2])
        let rootContainer = AccessibilityContainer(
            type: .none,
            identifier: "RootViewController",
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let offscreenContainer = AccessibilityContainer(
            type: .semanticGroup(label: "OffscreenGroup", value: nil),
            identifier: "OffscreenGroup",
            frame: AccessibilityRect(CGRect(x: 0, y: 480, width: 320, height: 240))
        )
        let visible = AccessibilityElement.make(
            label: "Visible",
            traits: .button,
            respondsToUserInteraction: false
        )
        let offscreen = AccessibilityElement.make(
            label: "Offscreen",
            traits: .button,
            respondsToUserInteraction: false
        )
        let viewportObservation = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "visible_button": InterfaceTree.Element(
                        heistId: "visible_button",
                        path: visiblePath,
                        scrollMembership: nil,
                        element: visible
                    ),
                    "offscreen_button": InterfaceTree.Element(
                        heistId: "offscreen_button",
                        path: TreePath([0, 2, 0]),
                        scrollMembership: InterfaceTree.ScrollMembership(
                            containerPath: offscreenContainerPath,
                            index: 0
                        ),
                        element: offscreen
                    ),
                ],
                containers: [
                    rootPath: InterfaceTree.Container(
                        container: rootContainer,
                        path: rootPath,
                        containerName: "root",
                        contentFrame: nil
                    ),
                    offscreenContainerPath: InterfaceTree.Container(
                        container: offscreenContainer,
                        path: offscreenContainerPath,
                        containerName: "offscreen_group",
                        contentFrame: nil,
                        scrollMembership: InterfaceTree.ScrollMembership(
                            containerPath: rootPath,
                            index: 0
                        )
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [
                    .container(rootContainer, children: [
                        .element(visible, traversalIndex: 0),
                    ]),
                ],
                containerNamesByPath: [rootPath: "root"],
                heistIdsByPath: [visiblePath: "visible_button"],
                elementRefs: [:],
                firstResponderHeistId: nil
            )
        )
        return viewportObservation
    }

    func successOutcome(
        method: ActionMethod = .activate,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil
    ) -> TheSafecracker.ActionDispatchOutcome {
        .success(
            method: method,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace
        )
    }

    func failureOutcome(
        method: ActionMethod = .activate,
        message: String = "action failed",
        subjectEvidence: ActionSubjectEvidence? = nil,
        failureKind: TheSafecracker.FailureKind = .actionFailed,
        activationTrace: ActivationTrace? = nil
    ) -> TheSafecracker.ActionDispatchOutcome {
        .failure(
            method,
            message: message,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            failureKind: failureKind
        )
    }

    func seedScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) {
        brains.vault.installObservationForTesting(makeScreen(elements: elements))
    }

    func notificationBatch(
        kind: AccessibilityNotificationKind,
        gap: AccessibilityNotificationGap? = nil
    ) -> AccessibilityNotificationBatch {
        AccessibilityNotificationBatch(
            events: [PendingAccessibilityNotificationEvent(
                sequence: 1,
                kind: kind,
                timestamp: Date(timeIntervalSince1970: 0),
                notificationData: .none,
                associatedElement: .none,
                provenance: .scoped
            )],
            through: AccessibilityNotificationCursor(sequence: 1),
            scopedScreenChangedThrough: kind == .screenChanged ? 1 : 0,
            gap: gap
        )
    }

    func volumeScreen(value: String) -> InterfaceObservation {
        InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Volume",
                    value: value,
                    traits: .adjustable,
                    respondsToUserInteraction: false
                ),
                "volume"
            ),
        ])
    }

    func temporalWaitReceipt(
        predicate: AccessibilityPredicate,
        baseline: InterfaceObservation,
        final: InterfaceObservation
    ) async throws -> HeistWaitReceipt {
        let stream = brains.vault.semanticObservationStream
        let baselineEvent = stream.commitVisibleObservationForTesting(baseline)
        brains.vault.installObservationForTesting(final)
        let baselineCapture = try XCTUnwrap(baselineEvent.settledCapture)
        return await brains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: predicate, timeout: .milliseconds(1))),
            changeBaseline: .supplied(baselineCapture)
        )
    }

    func elementChanges(
        in receipt: HeistWaitReceipt
    ) -> [AccessibilityTrace.ElementsChangeFact] {
        receipt.result.actionResult.accessibilityTrace?.changeFacts.compactMap { fact in
            guard case .elementsChanged(let changes) = fact else { return nil }
            return changes
        } ?? []
    }

    func makeScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)]) -> InterfaceObservation {
        let pairs: [(AccessibilityElement, HeistId)] = elements.map { entry in
            let element = AccessibilityElement.make(
                label: entry.label,
                traits: entry.traits,
                respondsToUserInteraction: false
            )
            return (element, entry.heistId)
        }
        return .makeForTests(elements: pairs)
    }

    func activationSubjectEvidence(
        target: AccessibilityTarget,
        element: AccessibilityElement,
        settledObservationSequence: SettledObservationSequence?
    ) throws -> ActionSubjectEvidence {
        ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: try target.resolve(in: .empty),
            element: TheVault.WireConversion.convert(element),
            resolution: ActionSubjectResolution(origin: .visible),
            settledObservationSequence: settledObservationSequence
        )
    }

    func makeScrollableContainer(frame: CGRect, contentSize: CGSize) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(contentSize),
            frame: AccessibilityRect(frame)
        )
    }

    func semanticContainer(
        _ container: AccessibilityContainer,
        path: TreePath
    ) -> InterfaceTree.Container {
        InterfaceTree.Container(
            container: container,
            path: path,
            containerName: nil,
            contentFrame: container.frame.cgRect
        )
    }

    func settledOutcome(
        finalScreen: InterfaceObservation?,
        outcome: SettleOutcome = .settled(timeMs: 0)
    ) -> SettleSession.Result {
        if let finalScreen {
            brains.vault.recordParsedObservedEvidence(finalScreen)
        }
        let elements = finalScreen?.liveCapture.hierarchy.sortedElements ?? []
        let elementsByKey = Dictionary(uniqueKeysWithValues: elements.map { ($0.timelineKey, $0) })
        return SettleSession.Result(
            outcome: outcome,
            events: [],
            finalObservation: finalScreen.map { SettleSessionFinalObservation(observation: $0) },
            elementsByKey: elementsByKey,
            tripwireSignal: brains.vault.semanticObservationStream.currentTripwireSignal()
        )
    }

}

#endif
