#if canImport(UIKit)
import ButtonHeistSupport
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsScrollTests {

    func testTargetDiscoveryMissDoesNotRevealStaleOffViewportTarget() async throws {
        let staleScrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let staleVisible = makeElement(label: "Root Visible")
        let staleRootButton = makeElement(label: "Controls Demo", traits: .button)
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(staleVisible, heistId: "root_visible"),
            offscreen: OffViewportScrollTarget(
                staleRootButton,
                heistId: "stale_controls_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: staleScrollView
            )
        )

        let currentHeader = makeElement(label: "Controls Demo", traits: .header)
        let currentBackButton = makeElement(label: "ButtonHeist Demo", traits: [.button, .backButton])
        let currentScreen = InterfaceObservation.makeForTests(elements: [
            (currentHeader, "current_controls_header"),
            (currentBackButton, "current_back_button"),
        ])
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(currentScreen)
        var discoveryAttempts = 0
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in
            discoveryAttempts += 1
            return nil
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Controls Demo").and(.traits([.button]))),
            method: .activate
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected current-screen target miss, got \(result)")
        }
        XCTAssertEqual(discoveryAttempts, 1)
        XCTAssertEqual(failure.failedStep, .notFound)
        XCTAssertEqual(staleScrollView.setContentOffsetAnimations, [])
        XCTAssertTrue(
            failure.message.contains("traits=[button]"),
            "Expected current semantic miss to preserve the requested button traits, got \(failure.message)"
        )
    }

    func testActionTargetDiscoveryStartsFromCurrentVisibleScreen() async throws {
        let staleVisible = makeElement(label: "Root Visible")
        let staleRootButton = makeElement(label: "Controls Demo", traits: .button)
        let staleRootScreen = makeScreenWithOffViewportEntry(
            liveHierarchy: [(staleVisible, "root_visible")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleRootButton,
                    heistId: "stale_controls_button",
                    scrollContainerPath: TreePath([0])
                )
            ]
        )
        brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(staleRootScreen)

        let currentHeader = makeElement(label: "Controls Demo", traits: .header)
        let currentBackButton = makeElement(label: "ButtonHeist Demo", traits: [.button, .backButton])
        let currentScreen = InterfaceObservation.makeForTests(elements: [
            (currentHeader, "current_controls_header"),
            (currentBackButton, "current_back_button"),
        ])
        brains.vault.observeInterface(currentScreen)
        brains.vault.nextVisibleRefreshObservationForTesting = currentScreen

        let discovered = await brains.navigation.elementInflation.exploration.discoverTarget(
            try resolvedTarget(.label("Controls Demo").and(.traits([.button])))
        )

        XCTAssertNotNil(discovered?.event.settledObservation.observation.tree.findElement(heistId: "current_controls_header"))
        XCTAssertNil(discovered?.event.settledObservation.observation.tree.findElement(heistId: "stale_controls_button"))
    }

    func testInterfaceDiscoveryDoesNotGraftStaleRowsFromReusedScrollContainerName() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = AccessibilityRevealingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scrollView.contentSize = CGSize(width: 320, height: 1_200)
        scrollView.revealThreshold = 300

        let visibleWord = UILabel(frame: CGRect(x: 40, y: 80, width: 240, height: 44))
        visibleWord.text = "Words"
        visibleWord.accessibilityLabel = "Words"
        visibleWord.accessibilityTraits = .staticText
        visibleWord.isAccessibilityElement = true

        let discoveredWord = UILabel(frame: CGRect(x: 40, y: 760, width: 240, height: 44))
        discoveredWord.text = "zymurgy"
        discoveredWord.accessibilityLabel = "zymurgy"
        discoveredWord.accessibilityTraits = .staticText
        discoveredWord.isAccessibilityElement = true

        scrollView.revealedElements = [discoveredWord]
        scrollView.updateAccessibilityVisibility()
        scrollView.addSubview(visibleWord)
        scrollView.addSubview(discoveredWord)
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let visibleScreen = try XCTUnwrap(
            brains.vault.refreshLiveCapture(),
            "Expected a live hierarchy for the interface discovery contamination regression test"
        )
        let scrollContainerPath = try XCTUnwrap(
            visibleScreen.tree.orderedContainers.compactMap { container -> TreePath? in
                guard container.container.isScrollable else { return nil }
                return container.path
            }.first,
            "Expected the parser to expose the fixture scroll view as a scroll container"
        )
        let visibleEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(visibleScreen)

        let staleRootRow = makeElement(label: "Auto-Settle Fixtures", traits: .button)
        let staleEntry = InterfaceTree.Element(
            heistId: "stale_auto_settle_fixtures",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            element: staleRootRow
        )
        let staleScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [staleEntry.heistId: staleEntry],
                containers: visibleScreen.tree.containers
            ),
            liveCapture: visibleScreen.liveCapture
        )
        brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(staleScreen)

        guard let exploration = await brains.navigation.exploreScreen(
            baseline: .currentViewport(brains.vault.visibleExplorationBaseline(from: visibleScreen)),
            maxScrollsPerContainer: 3,
            maxScrollsPerDiscovery: 3
        ) else {
            return XCTFail("Expected word-list exploration to settle")
        }
        let labels = try brains.vault.selectInterface(InterfaceQuery()).projectedElements.compactMap(\.label)
        XCTAssertEqual(
            exploration.event.generation,
            visibleEvent.generation,
            "Canonical viewport movement must preserve one list generation"
        )
        XCTAssertGreaterThan(exploration.progress.scrollCount, 0, "Expected discovery to scroll the word list")
        XCTAssertTrue(labels.contains("Words"), "Expected visible word in discovered interface: \(labels)")
        XCTAssertTrue(labels.contains("zymurgy"), "Expected scrolled word in discovered interface: \(labels)")
        XCTAssertFalse(
            labels.contains("Auto-Settle Fixtures"),
            "Stale root rows must not be grafted into the current scroll container: \(labels)"
        )
    }

    func testDiscoveryCrossesBlankViewportBeforeUnknownTarget() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = AccessibilityRevealingScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 600)
        )
        scrollView.contentSize = CGSize(width: 320, height: 2_200)
        scrollView.revealThreshold = 1_000

        let visible = UILabel(frame: CGRect(x: 40, y: 80, width: 240, height: 44))
        visible.text = "Blank Page Anchor"
        visible.accessibilityLabel = "Blank Page Anchor"
        visible.isAccessibilityElement = true

        let target = UIButton(type: .system)
        target.frame = CGRect(x: 40, y: 1_500, width: 240, height: 44)
        target.setTitle("Beyond Blank Page", for: .normal)
        target.accessibilityLabel = "Beyond Blank Page"
        target.accessibilityTraits = .button
        target.isAccessibilityElement = true

        scrollView.revealedElements = [target]
        scrollView.updateAccessibilityVisibility()
        scrollView.addSubview(visible)
        scrollView.addSubview(target)
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        let initialVisualOrigin = Navigation.visualOrigin(in: scrollView)
        let visibleScreen = try XCTUnwrap(
            brains.vault.refreshLiveCapture(),
            "Expected a live hierarchy for blank-page discovery"
        )

        guard let exploration = await brains.navigation.exploreScreen(
            target: try resolvedTarget(.label("Beyond Blank Page")),
            baseline: .currentViewport(brains.vault.visibleExplorationBaseline(from: visibleScreen)),
            exitPosition: .origin,
            maxScrollsPerContainer: 4,
            maxScrollsPerDiscovery: 4
        ) else {
            return XCTFail("Expected discovery to cross the blank viewport")
        }

        XCTAssertGreaterThanOrEqual(exploration.progress.scrollCount, 2)
        XCTAssertNotNil(brains.vault.interfaceTree.orderedElements.first {
            $0.element.label == "Beyond Blank Page"
        })
        XCTAssertEqual(
            Navigation.visualOrigin(in: scrollView).y,
            initialVisualOrigin.y,
            accuracy: 0.01
        )
    }

    func testWaitDiscoveryRestoresViewportAfterOffscreenTargetMatch() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = AccessibilityRevealingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scrollView.contentSize = CGSize(width: 320, height: 1_200)
        scrollView.revealThreshold = 300

        let visible = UILabel(frame: CGRect(x: 40, y: 80, width: 240, height: 44))
        visible.text = "Wait Discovery Anchor"
        visible.accessibilityLabel = "Wait Discovery Anchor"
        visible.accessibilityTraits = .staticText
        visible.isAccessibilityElement = true

        let target = UIButton(type: .system)
        target.frame = CGRect(x: 40, y: 760, width: 240, height: 44)
        target.setTitle("Wait Discovery Target", for: .normal)
        target.accessibilityLabel = "Wait Discovery Target"
        target.accessibilityTraits = .button
        target.isAccessibilityElement = true

        scrollView.revealedElements = [target]
        scrollView.updateAccessibilityVisibility()
        scrollView.addSubview(visible)
        scrollView.addSubview(target)
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        let initialVisualOrigin = Navigation.visualOrigin(in: scrollView)

        let visibleScreen = try XCTUnwrap(
            brains.vault.refreshLiveCapture(),
            "Expected a live hierarchy for wait discovery restoration"
        )
        guard let exploration = await brains.navigation.exploreScreen(
            target: try resolvedTarget(.label("Wait Discovery Target")),
            baseline: .currentViewport(brains.vault.visibleExplorationBaseline(from: visibleScreen)),
            exitPosition: .origin,
            maxScrollsPerContainer: 3,
            maxScrollsPerDiscovery: 3
        ) else {
            return XCTFail("Expected wait discovery to find the offscreen target")
        }

        XCTAssertNotNil(exploration.event.settledObservation.observation.tree.orderedElements.first {
            $0.element.label == "Wait Discovery Target"
        })
        XCTAssertEqual(
            Navigation.visualOrigin(in: scrollView).y,
            initialVisualOrigin.y,
            accuracy: 0.01
        )
        XCTAssertFalse(exploration.event.settledObservation.observation.liveCapture.hierarchy.sortedElements.contains {
            $0.label == "Wait Discovery Target"
        })
    }

    func testScrollToVisibleDiscoversTargetAboveCurrentViewport() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = AccessibilityRevealingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        scrollView.contentSize = CGSize(width: 320, height: 1_200)
        scrollView.revealMode = .atOrAbove
        scrollView.revealThreshold = 10

        let target = UIButton(type: .system)
        target.setTitle("Top Target", for: .normal)
        target.accessibilityLabel = "Top Target"
        target.accessibilityTraits = .button
        target.isAccessibilityElement = true
        target.frame = CGRect(x: 40, y: 40, width: 240, height: 44)

        let visibleMarker = UILabel(frame: CGRect(x: 40, y: 620, width: 240, height: 44))
        visibleMarker.text = "Visible Marker"
        visibleMarker.accessibilityLabel = "Visible Marker"
        visibleMarker.accessibilityTraits = .staticText
        visibleMarker.isAccessibilityElement = true

        scrollView.revealedElements = [target]
        scrollView.addSubview(target)
        scrollView.addSubview(visibleMarker)
        scrollView.contentOffset = CGPoint(x: 0, y: 520)
        scrollView.updateAccessibilityVisibility()
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        _ = brains.vault.refreshLiveCapture()

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .label("Top Target"))
            )
        )

        XCTAssertTrue(result.success, "Expected scroll_to_visible to discover the target above; got \(result)")
        XCTAssertLessThanOrEqual(scrollView.contentOffset.y, 10)
        XCTAssertTrue(brains.vault.latestObservation.tree.orderedElements.contains {
            $0.element.label == "Top Target"
        })
    }

    func testKnownSemanticRevealIgnoresStaleDetachedScrollView() async throws {
        let staleScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(visible, HeistId(rawValue: "visible_element"))]
        ))

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .label("Offscreen"))
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertEqual(staleScrollView.contentOffset, .zero)
        XCTAssertFalse(
            result.message?.contains("after semantic reveal") ?? false,
            "Detached scroll views should not authorize semantic reveal"
        )
    }

    func testStaleKnownRevealWaitsForSettledRecoveryWithoutRediscovery() async throws {
        brains.stopSemanticObservation()
        let staleScrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let staleTarget = makeElement(label: "Target")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                staleTarget,
                heistId: "target_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: staleScrollView
            )
        )

        let recoveredFrame = CGRect(x: 40, y: 160, width: 240, height: 44)
        let recoveredTarget = AccessibilityElement.make(
            label: "Target",
            traits: .button,
            frame: recoveredFrame
        )
        let recoveredObject = retainedLiveObject()
        let recoveredEntry = InterfaceTree.Element(
            heistId: "target_button",
            scrollMembership: nil,
            element: recoveredTarget
        )
        let recoveredScreen = InterfaceObservation.makeForTests(
            elements: [recoveredEntry.heistId: recoveredEntry],
            hierarchy: [.element(recoveredTarget, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): recoveredEntry.heistId],
            elementRefs: [
                recoveredEntry.heistId: .init(object: recoveredObject, scrollView: nil)
            ],
            firstResponderHeistId: nil,
        )
        var discoveryAttempts = 0
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in
            discoveryAttempts += 1
            return nil
        }

        let target = try resolvedTarget(AccessibilityTarget.label("Target"))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .scrollToVisible
            )
        }
        await waitForSettledSemanticWaiter()
        brains.vault.nextVisibleRefreshObservationForTesting = recoveredScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

        await inflation.value
        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail("Expected settled observation to recover stale reveal")
        }
        XCTAssertEqual(discoveryAttempts, 0)
        XCTAssertEqual(staleScrollView.setContentOffsetAnimations, [false])
        XCTAssertEqual(staleScrollView.contentOffset.y, 1_000, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.treeElement.heistId, recoveredEntry.heistId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, recoveredFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, recoveredFrame.midY, accuracy: 0.01)
    }

    func testKnownTargetWithMissingLiveScrollAncestorRecapturesVisibleActionableTarget() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "known_coke_button"
        let staleScrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let knownTarget = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                knownTarget,
                heistId: targetId,
                contentActivationPoint: CGPoint(x: 160, y: 1_200),
                scrollView: staleScrollView
            ),
            includeLiveScrollAncestor: false
        )

        let comfortZone = ElementInflation.interactionComfortZone
        let recoveredFrame = CGRect(
            x: comfortZone.midX - 100,
            y: comfortZone.midY - 22,
            width: 200,
            height: 44
        )
        let recoveredTarget = AccessibilityElement.make(
            label: "Coke",
            traits: .button,
            frame: recoveredFrame
        )
        let recoveredObject = retainLiveObject(makeButton(label: "Coke", frame: recoveredFrame))
        let scrollContainerPath = TreePath([0])
        let recoveredEntry = InterfaceTree.Element(
            heistId: targetId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            element: recoveredTarget
        )
        let recoveredScreen = InterfaceObservation.makeForTests(
            elements: [recoveredEntry.heistId: recoveredEntry],
            hierarchy: [
                .container(makeScrollableContainer(), children: [
                    .element(recoveredTarget, traversalIndex: 0)
                ])
            ],
            containerNamesByPath: [scrollContainerPath: "current_drinks_scroll"],
            heistIdsByPath: [scrollContainerPath.appending(0): recoveredEntry.heistId],
            elementRefs: [
                recoveredEntry.heistId: .init(object: recoveredObject, scrollView: nil)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [:]
        )
        XCTAssertTrue(recoveredScreen.tree.viewportElementIDs.contains(recoveredEntry.heistId))
        XCTAssertNotNil(recoveredScreen.liveCapture.object(for: recoveredEntry.heistId))
        var revealAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { request in
            XCTAssertEqual(request.heistId, targetId)
            revealAttempts += 1
            return nil
        }

        let target = try resolvedTarget(AccessibilityTarget.label("Coke").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .activate
            )
        }
        await waitForSettledSemanticWaiter()
        brains.vault.nextVisibleRefreshObservationForTesting = recoveredScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)
        await inflation.value

        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail("Expected current visible target recovery, got \(String(describing: resultBox.value))")
        }
        XCTAssertEqual(revealAttempts, 1)
        XCTAssertEqual(staleScrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(inflatedTarget.treeElement.heistId, recoveredEntry.heistId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, recoveredFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, recoveredFrame.midY, accuracy: 0.01)
        XCTAssertTrue(inflatedTarget.liveTarget.object === recoveredObject)
        XCTAssertFalse(brains.vault.liveScrollView(for: inflatedTarget.treeElement) === staleScrollView)
    }

    func testScrollReturnsReasonInsteadOfRevealingOffViewportTarget() async throws {
        // Contract: Scroll either reveals the requested target or returns a reason it cannot.
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                offscreen,
                heistId: "offscreen_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            )
        )

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Offscreen"), direction: .down))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scroll)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertEqual(scrollView.contentOffset, .zero)
        XCTAssertTrue(
            result.message?.contains("exists in the interface tree but is outside the current viewport") == true,
            "Expected offscreen guidance, got \(String(describing: result.message))"
        )
        XCTAssertTrue(result.message?.contains("scroll_to_visible") == true)
    }

    func testScrollToEdgeReturnsReasonInsteadOfRevealingOffViewportTarget() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                offscreen,
                heistId: "offscreen_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            )
        )

        let result = await brains.navigation.executeScrollToEdge(
            try resolvedScrollToEdgeTarget(
                ScrollToEdgeTarget(target: .label("Offscreen"), edge: .bottom)
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToEdge)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertEqual(scrollView.contentOffset, .zero)
        XCTAssertTrue(
            result.message?.contains("exists in the interface tree but is outside the current viewport") == true,
            "Expected offscreen guidance, got \(String(describing: result.message))"
        )
        XCTAssertTrue(result.message?.contains("scroll_to_visible") == true)
    }

    func testScrollWithoutElementUsesSingleVisibleContainerAndDefaultsDown() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            containerRefsByPath: [TreePath([0]): .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        ))
        let baselineSequence = brains.vault.semanticObservationStream.latestCommittedEvent?.sequence

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget())
        )

        XCTAssertTrue(result.success, "Expected default scroll to pick the only visible container: \(String(describing: result.message))")
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        let committedMovement = try XCTUnwrap(brains.vault.semanticObservationStream.latestCommittedEvent)
        XCTAssertEqual(committedMovement.scope, .discovery)
        XCTAssertNotEqual(committedMovement.sequence, baselineSequence)
    }

    func testScrollToEdgeWithoutElementDefaultsTop() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        scrollView.contentOffset.y = 600
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            containerRefsByPath: [TreePath([0]): .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        ))

        let result = await brains.navigation.executeScrollToEdge(
            try resolvedScrollToEdgeTarget(ScrollToEdgeTarget())
        )

        XCTAssertTrue(result.success, "Expected default edge scroll to pick the only visible container: \(String(describing: result.message))")
        XCTAssertEqual(scrollView.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollToEdgeAlreadyAtRequestedEdgeSucceeds() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            containerRefsByPath: [TreePath([0]): .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        ))

        let result = await brains.navigation.executeScrollToEdge(
            try resolvedScrollToEdgeTarget(ScrollToEdgeTarget(edge: .top))
        )

        XCTAssertTrue(result.success, "Expected already-at-edge scroll to be idempotent: \(String(describing: result.message))")
        XCTAssertEqual(scrollView.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollUsesNamedContainer() async throws {
        let firstScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        firstScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let secondScrollView = UIScrollView(frame: CGRect(x: 0, y: 420, width: 320, height: 400))
        secondScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let firstContainer = makeScrollableContainer(contentSize: firstScrollView.contentSize, frame: firstScrollView.frame)
        let secondContainer = makeScrollableContainer(contentSize: secondScrollView.contentSize, frame: secondScrollView.frame)
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(firstContainer, children: []),
                .container(secondContainer, children: []),
            ],
            containerNamesByPath: [
                TreePath([0]): "first_scroll",
                TreePath([1]): "second_scroll",
            ],
            containerRefsByPath: [
                TreePath([0]): .init(object: firstScrollView),
                TreePath([1]): .init(object: secondScrollView),
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                TreePath([0]): .init(view: firstScrollView),
                TreePath([1]): .init(view: secondScrollView),
            ]
        ))

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(
                ScrollTarget(selection: .container("second_scroll"), direction: .down)
            )
        )

        XCTAssertTrue(result.success, "Expected named container scroll to succeed: \(String(describing: result.message))")
        XCTAssertEqual(firstScrollView.contentOffset.y, 0, accuracy: 0.01)
        XCTAssertGreaterThan(secondScrollView.contentOffset.y, 0)
    }

    func testScrollToEdgeUsesNamedContainer() async throws {
        let firstScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        firstScrollView.contentSize = CGSize(width: 320, height: 1_600)
        firstScrollView.contentOffset.y = 500
        let secondScrollView = UIScrollView(frame: CGRect(x: 0, y: 420, width: 320, height: 400))
        secondScrollView.contentSize = CGSize(width: 320, height: 1_600)
        secondScrollView.contentOffset.y = 500
        let firstContainer = makeScrollableContainer(contentSize: firstScrollView.contentSize, frame: firstScrollView.frame)
        let secondContainer = makeScrollableContainer(contentSize: secondScrollView.contentSize, frame: secondScrollView.frame)
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(firstContainer, children: []),
                .container(secondContainer, children: []),
            ],
            containerNamesByPath: [
                TreePath([0]): "first_scroll",
                TreePath([1]): "second_scroll",
            ],
            containerRefsByPath: [
                TreePath([0]): .init(object: firstScrollView),
                TreePath([1]): .init(object: secondScrollView),
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                TreePath([0]): .init(view: firstScrollView),
                TreePath([1]): .init(view: secondScrollView),
            ]
        ))

        let result = await brains.navigation.executeScrollToEdge(
            try resolvedScrollToEdgeTarget(
                ScrollToEdgeTarget(selection: .container("second_scroll"), edge: .top)
            )
        )

        XCTAssertTrue(result.success, "Expected named container edge scroll to succeed: \(String(describing: result.message))")
        XCTAssertEqual(firstScrollView.contentOffset.y, 500, accuracy: 0.01)
        XCTAssertEqual(secondScrollView.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollUsesPathKeyedContainerWhenRepeatedSameSizedScrollViews() async throws {
        let firstScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        firstScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let secondScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        secondScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let repeatedContainer = makeScrollableContainer(
            contentSize: firstScrollView.contentSize,
            frame: firstScrollView.frame
        )
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])

        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(repeatedContainer, children: []),
                .container(repeatedContainer, children: []),
            ],
            containerNamesByPath: [
                firstPath: "first_repeated_scroll",
                secondPath: "second_repeated_scroll",
            ],
            containerRefsByPath: [
                firstPath: .init(object: firstScrollView),
                secondPath: .init(object: secondScrollView),
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                firstPath: .init(view: firstScrollView),
                secondPath: .init(view: secondScrollView),
            ]
        ))

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(
                ScrollTarget(selection: .container("second_repeated_scroll"), direction: .down)
            )
        )

        XCTAssertTrue(result.success, "Expected path-keyed named container scroll to succeed: \(String(describing: result.message))")
        XCTAssertEqual(firstScrollView.contentOffset.y, 0, accuracy: 0.01)
        XCTAssertGreaterThan(secondScrollView.contentOffset.y, 0)
    }

    func testScrollWithoutElementReportsAmbiguousContainers() async throws {
        let firstContainer = makeScrollableContainer()
        let secondContainer = makeScrollableContainer(frame: CGRect(x: 0, y: 420, width: 320, height: 400))
        installScrollableContainers([firstContainer, secondContainer])
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(firstContainer, children: []),
                .container(secondContainer, children: []),
            ],
            containerNamesByPath: [
                TreePath([0]): "first_scroll",
                TreePath([1]): "second_scroll",
            ],
            containerRefsByPath: [
                TreePath([0]): .init(object: retainedLiveObject()),
                TreePath([1]): .init(object: retainedLiveObject()),
            ],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget())
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message?.contains("ambiguous") == true)
        XCTAssertTrue(result.message?.contains("target an element inside the intended scroll region") == true)
        XCTAssertFalse(result.message?.contains("first_scroll") == true)
        XCTAssertFalse(result.message?.contains("second_scroll") == true)
    }

    func testScrollToVisibleVisibleAmbiguousMatcherFailsClosed() async throws {
        let first = makeElement(label: "Duplicate", traits: .button)
        let second = makeElement(label: "Duplicate", traits: .button)
        let firstEntry = InterfaceTree.Element(
            heistId: "duplicate_1",
            scrollMembership: nil,
            element: first
        )
        let secondEntry = InterfaceTree.Element(
            heistId: "duplicate_2",
            scrollMembership: nil,
            element: second
        )
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [
                firstEntry.heistId: firstEntry,
                secondEntry.heistId: secondEntry,
            ],
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): firstEntry.heistId,
                TreePath([1]): secondEntry.heistId,
            ],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .label("Duplicate"))
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("element inflation failed [ambiguous]") ?? false,
            "Expected classified ambiguity diagnostic, got \(String(describing: result.message))"
        )
        XCTAssertTrue(
            result.message?.contains("2 elements match") ?? false,
            "Expected ambiguity diagnostic, got \(String(describing: result.message))"
        )
    }

    func testScrollToVisiblePreservesVisibleMatcherOrdinalOutOfRange() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        rootView.addSubview(makeButton(label: "Save", frame: CGRect(x: 40, y: 120, width: 260, height: 44)))

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .target(.label("Save"), ordinal: 3))
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("ordinal 3 requested") ?? false,
            "Expected ordinal diagnostic, got \(String(describing: result.message))"
        )
    }

    func testScrollToVisiblePostSemanticRevealDoesNotRetargetCommittedIdentity() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = AccessibilityRevealingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let firstTarget = makeAccessibleView(label: "Jump Target", frame: CGRect(x: 40, y: 900, width: 240, height: 44))
        let secondTarget = makeAccessibleView(label: "Jump Target", frame: CGRect(x: 40, y: 960, width: 240, height: 44))
        scrollView.revealedElements = [firstTarget, secondTarget]
        scrollView.updateAccessibilityVisibility()
        scrollView.addSubview(firstTarget)
        scrollView.addSubview(secondTarget)
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        let scrollContainerPath = TreePath([0])
        let liveScreen = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(
                    makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame),
                    children: []
                ),
            ],
            containerRefsByPath: [scrollContainerPath: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [scrollContainerPath: .init(view: scrollView)]
        )
        brains.vault.installObservationForTesting(liveScreen)
        let prematureResolution = brains.vault.resolveTarget(
            literalTarget(ElementPredicate.label("Jump Target"), ordinal: 0)
        )
        guard case .notFound = prematureResolution else {
            XCTFail("Parser exposed offscreen scroll content before semantic reveal: \(prematureResolution)")
            return
        }

        let interfaceElement = makeElement(
            label: "Jump Target",
            traits: .button,
            shape: .frame(AccessibilityRect(firstTarget.frame))
        )
        let knownEntry = InterfaceTree.Element(
            heistId: "known_reveal_target",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: observedContentActivationPoint(CGPoint(
                x: firstTarget.frame.midX,
                y: firstTarget.frame.midY
            )),
            element: interfaceElement
        )
        let knownScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [knownEntry.heistId: knownEntry],
                containers: liveScreen.tree.containers
            ),
            liveCapture: liveScreen.liveCapture
        )
        brains.vault.installObservationForTesting(knownScreen)
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Jump Target")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected uncommitted live identities to fail closed, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, .noRevealPath)
        XCTAssertEqual(failure.failureKind, .actionFailed)
        XCTAssertFalse(failure.message.contains("[ambiguous]"))
    }

}

#endif
