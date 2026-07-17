#if canImport(UIKit)
import ButtonHeistSupport
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class TheBrainsScrollTests: XCTestCase {

    @MainActor
    private final class InflationResultBox {
        var value: ElementInflation.ElementInflationResult?
    }

    private var brains: TheBrains!
    private var retainedLiveObjects: [NSObject] = []

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
    }

    override func tearDown() async throws {
        brains?.stopSemanticObservation()
        brains?.tripwire.stopPulse()
        brains = nil
        retainedLiveObjects.removeAll()
        try await super.tearDown()
    }

    private func retainLiveObject<Object: NSObject>(_ object: Object) -> Object {
        retainedLiveObjects.append(object)
        return object
    }

    private func retainedLiveObject() -> NSObject {
        retainLiveObject(NSObject())
    }

    private func resolvedTarget(
        _ target: AccessibilityTarget
    ) throws -> ResolvedAccessibilityTarget {
        try target.resolve(in: .empty)
    }

    private func resolvedScrollTarget(
        _ target: ScrollTarget
    ) throws -> ResolvedScrollTarget {
        try target.resolve(in: .empty)
    }

    private func resolvedScrollToEdgeTarget(
        _ target: ScrollToEdgeTarget
    ) throws -> ResolvedScrollToEdgeTarget {
        try target.resolve(in: .empty)
    }

    private func resolvedScrollToVisibleTarget(
        _ target: ScrollToVisibleTarget
    ) throws -> ResolvedAccessibilityTarget {
        try resolvedTarget(target.target)
    }

    private func observedContentActivationPoint(
        _ point: CGPoint
    ) -> InterfaceTree.ObservedScrollContentActivationPoint {
        guard let observedPoint = InterfaceTree.ObservedScrollContentActivationPoint(point) else {
            preconditionFailure("Test content activation point must be finite")
        }
        return observedPoint
    }

    private func semanticRevealDeadline() -> SemanticObservationDeadline {
        SemanticObservationDeadline(start: CFAbsoluteTimeGetCurrent(), timeoutSeconds: 10)
    }

    private func waitForSettledSemanticWaiter(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = CFAbsoluteTimeGetCurrent() + 1
        while brains.stash.semanticObservationStream.observationReplayWaiterCount == 0,
              CFAbsoluteTimeGetCurrent() < deadline {
            await Task.yield()
            guard await Task.cancellableSleep(for: .milliseconds(5)) else { break }
        }
        XCTAssertEqual(
            brains.stash.semanticObservationStream.observationReplayWaiterCount,
            1,
            file: file,
            line: line
        )
    }

    // MARK: - Programmatic Scroll Safety

    func testTargetUnavailableScrollFailureMapsToElementNotFoundErrorKind() {
        let result = TheSafecracker.ActionDispatchOutcome.failure(
            .scrollToVisible,
            message: "element inflation failed [notFound]: missing",
            failureKind: .targetUnavailable
        )

        guard let failureKind = result.failureKind else {
            return XCTFail("Expected scroll_to_visible failure kind")
        }
        XCTAssertEqual(TheBrains.actionErrorKind(for: failureKind), .elementNotFound)
    }

    func testExploreScreenReturnsNoProofWhenInitialSettlementIsCancelled() async {
        let staleBaseline = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                AccessibilityElement.make(label: "Stale", traits: .staticText),
                heistId: "stale_staticText"
            )
        ])
        let explorationTask = Task { @MainActor in
            await brains.navigation.exploreScreen(baseline: .interfaceMemory(staleBaseline)) != nil
        }
        explorationTask.cancel()

        let returnedProof = await explorationTask.value

        XCTAssertFalse(returnedProof)
    }

    func testScanForHeistIdReturnsNoProofWhenInitialSettlementIsCancelled() async {
        let staleId: HeistId = "stale_action_target"
        brains.stash.installScreenForTesting(.makeForTests([
            .init(
                AccessibilityElement.make(label: "Stale action target", traits: .button),
                heistId: staleId
            ),
        ]))
        let deadline = semanticRevealDeadline()
        let scanTask = Task { @MainActor in
            await brains.navigation.scanForHeistId(staleId, deadline: deadline) == nil
        }
        scanTask.cancel()

        let returnedNoProof = await scanTask.value
        XCTAssertTrue(returnedNoProof)
    }

    func testScanForHeistIdReturnsNoProofWhenDeadlineIsExpired() async {
        let deadline = SemanticObservationDeadline(
            start: CFAbsoluteTimeGetCurrent() - 1,
            timeoutSeconds: 0
        )

        let result = await brains.navigation.scanForHeistId("stale_action_target", deadline: deadline)

        XCTAssertNil(result)
    }

    func testGeometryCrossingDeadlineDuringFrameAwaitTimesOut() async throws {
        let targetId: HeistId = "geometry_deadline_target"
        let element = makeElement(
            label: "Deadline Target",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 40, y: 120, width: 200, height: 44)))
        )
        let object = retainedLiveObject()
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests([
            .init(element, heistId: targetId, object: object),
        ]))
        let treeElement = try XCTUnwrap(brains.stash.interfaceElement(heistId: targetId))
        guard case .resolved(let liveTarget) = brains.stash.resolveLiveActionTarget(for: treeElement) else {
            return XCTFail("Expected live geometry fixture to resolve")
        }
        var now: CFAbsoluteTime = 100
        let inflation = brains.navigation.elementInflation
        inflation.geometryEnvironment = .init(
            now: { now },
            awaitFrame: { now = 101 }
        )
        let inflatedTarget = ElementInflation.InflatedElementTarget(
            target: try resolvedTarget(.label("Deadline Target")),
            treeElement: treeElement,
            liveTarget: liveTarget,
            deadline: SemanticObservationDeadline(start: 100, timeoutSeconds: 1),
            resolution: ActionSubjectResolution(origin: .visible)
        )

        let state = await inflation.stateAfterResolvedFreshTarget(
            inflatedTarget,
            activationPointPolicy: .liveObjectOnly
        )

        guard case .failed(let failure) = state else {
            return XCTFail("Expected deadline crossed during frame await to fail, got \(state)")
        }
        XCTAssertEqual(failure.failedStep, .timedOut)
        XCTAssertEqual(failure.failureKind, .timeout)
        let dispatchOutcome = failure.actionDispatchOutcome(commandMethod: .activate)
        guard let failureKind = dispatchOutcome.failureKind else {
            return XCTFail("Expected timed-out dispatch failure kind")
        }
        XCTAssertEqual(failureKind, .timeout)
        XCTAssertEqual(TheBrains.actionErrorKind(for: failureKind), .timeout)
    }

    func testExploreScreenSkipsUIPageViewControllerQueuingScrollView() async throws {
        let windowScene = try requireForegroundWindowScene()
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        let pages = [
            PageContentViewController(label: "Page One Visible Label"),
            PageContentViewController(label: "Page Two Hidden Label"),
            PageContentViewController(label: "Page Three Hidden Label"),
        ]
        let dataSource = PageDataSource(pages: pages)
        pageViewController.dataSource = dataSource
        pageViewController.setViewControllers([pages[0]], direction: .forward, animated: false)
        pageViewController.view.accessibilityViewIsModal = true

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 20
        window.rootViewController = pageViewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false

        defer {
            window.isHidden = true
            pageViewController.view.accessibilityViewIsModal = false
        }

        window.layoutIfNeeded()
        await brains.tripwire.yieldFrames(3)

        guard brains.stash.refreshLiveCapture() != nil else {
            throw XCTSkip("No live hierarchy available for UIPageViewController regression test")
        }

        var seenUnsafeTargets = Set<ObjectIdentifier>()
        let unsafeTargets = brains.stash.scrollableContainerViewsByPath.values.filter {
            guard $0.bhIsUnsafeForProgrammaticScrolling else { return false }
            return seenUnsafeTargets.insert(ObjectIdentifier($0)).inserted
        }
        let unsafeOffsets = Dictionary(
            uniqueKeysWithValues: unsafeTargets.map { (ObjectIdentifier($0), $0.contentOffset) }
        )

        guard let exploration = await brains.navigation.exploreScreen() else {
            return XCTFail("Expected UIPageViewController exploration to settle")
        }
        let manifest = exploration.manifest

        XCTAssertEqual(manifest.scrollCount, 0)
        for scrollView in unsafeTargets {
            XCTAssertEqual(Optional(scrollView.contentOffset), unsafeOffsets[ObjectIdentifier(scrollView)])
        }
        XCTAssertTrue(
            exploration.event.observation.screen.tree.elements.values.contains {
                $0.element.label == "Page One Visible Label"
            },
            "Visible page content should remain discoverable without scrolling the private queuing scroll view"
        )
    }

    // MARK: - requiredAxis Mapping

    func testRequiredAxisForScrollDirection() {
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.up), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.down), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.left), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.right), .horizontal)
    }

    func testRequiredAxisForScrollEdge() {
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.top), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.bottom), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.left), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.right), .horizontal)
    }

    // MARK: - uiScrollDirection Mapping

    func testUIScrollDirectionFromScrollDirection() {
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.up), .up)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.down), .down)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.left), .left)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.right), .right)
    }

    // MARK: - Scroll Target Description

    func testScrollTargetDescriptionUsesNamedPriority() {
        let labeled = InterfaceTree.Element(
            heistId: "labeled_item",
            scrollMembership: nil,
            element: AccessibilityElement.make(label: "Labeled", identifier: "labeled_id")
        )
        let identified = InterfaceTree.Element(
            heistId: "identified_item",
            scrollMembership: nil,
            element: AccessibilityElement.make(identifier: "identified_id")
        )
        let anonymous = InterfaceTree.Element(
            heistId: "anonymous_item",
            scrollMembership: nil,
            element: AccessibilityElement.make()
        )

        XCTAssertEqual(
            Navigation.ScrollTargetDescription(labeled),
            .label("Labeled")
        )
        XCTAssertEqual(
            Navigation.ScrollTargetDescription(identified),
            .identifier("identified_id")
        )
        XCTAssertEqual(
            Navigation.ScrollTargetDescription(anonymous),
            .element
        )
    }

    // MARK: - Scroll Target Selection

    func testScrollCandidatesFilterToRequiredAxis() {
        let vertical = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let horizontal = makeScrollableContainer(
            contentSize: CGSize(width: 1200, height: 200),
            frame: CGRect(x: 0, y: 420, width: 320, height: 200)
        )
        installScrollableContainers([vertical, horizontal])

        let candidates = brains.navigation.scrollCandidates(requiredAxis: .horizontal)

        XCTAssertEqual(candidates.map(\.container), [horizontal])
    }

    func testScrollCandidatesPreserveTreeOrderWithinRequiredAxis() {
        let horizontal = makeScrollableContainer(
            contentSize: CGSize(width: 1200, height: 200),
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )
        let verticalOne = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1600),
            frame: CGRect(x: 0, y: 220, width: 320, height: 400)
        )
        let verticalTwo = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1800),
            frame: CGRect(x: 0, y: 640, width: 320, height: 400)
        )
        installScrollableContainers([horizontal, verticalOne, verticalTwo])

        let candidates = brains.navigation.scrollCandidates(requiredAxis: .vertical)

        XCTAssertEqual(candidates.map(\.container), [verticalOne, verticalTwo])
    }

    func testLiveVisibleScreenPreservesDuplicateEqualElementsByPath() {
        let duplicate = makeElement(label: "Duplicate", traits: .button)
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        let firstEntry = InterfaceTree.Element(
            heistId: "duplicate_button_1",
            scrollMembership: nil,
            element: duplicate
        )
        let secondEntry = InterfaceTree.Element(
            heistId: "duplicate_button_2",
            scrollMembership: nil,
            element: duplicate
        )

        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [
                firstEntry.heistId: firstEntry,
                secondEntry.heistId: secondEntry,
            ],
            hierarchy: [
                .element(duplicate, traversalIndex: 0),
                .element(duplicate, traversalIndex: 1),
            ],
            heistIdsByPath: [
                firstPath: firstEntry.heistId,
                secondPath: secondEntry.heistId,
            ],
            elementRefs: [
                firstEntry.heistId: .init(object: NSObject(), scrollView: nil),
                secondEntry.heistId: .init(object: NSObject(), scrollView: nil),
            ],
            firstResponderHeistId: nil,
        ))

        XCTAssertEqual(
            brains.stash.latestObservation.orderedElements.map(\.heistId),
            [firstEntry.heistId, secondEntry.heistId]
        )
    }

    func testResolveLiveActionTargetFailsClosedWhenWeakObjectIsStale() async {
        let element = makeElement(label: "Detached", traits: .button)
        let entry = InterfaceTree.Element(
            heistId: "detached_button",
            scrollMembership: nil,
            element: element
        )
        var object: NSObject? = NSObject()
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))
        object = nil

        switch brains.stash.resolveLiveActionTarget(for: entry) {
        case .objectUnavailable:
            break
        case .resolved(let target):
            XCTFail("Expected stale weak object to fail closed, got \(target)")
        case .geometryUnavailable:
            XCTFail("Expected stale weak object failure before geometry lookup")
        }
    }

    // MARK: - Known Offscreen Entry

    /// Install a InterfaceObservation whose `elements` includes an entry that's not in the
    /// live hierarchy — simulating an element retained from a previous
    /// exploration commit that has since scrolled off.
    private func makeScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, HeistId)],
        offViewport: [InterfaceObservation.OffViewportEntry]
    ) -> InterfaceObservation {
        .makeForTests(
            elements: liveHierarchy.map { ($0.0, $0.1) },
            offViewport: offViewport
        )
    }

    private func installScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, HeistId)],
        offViewport: [InterfaceObservation.OffViewportEntry]
    ) {
        brains.stash.installScreenForTesting(makeScreenWithOffViewportEntry(
            liveHierarchy: liveHierarchy,
            offViewport: offViewport
        ))
    }

    private struct OffViewportScrollTarget {
        let element: AccessibilityElement
        let heistId: HeistId
        let observedActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint
        let scrollView: UIScrollView

        init(
            _ element: AccessibilityElement,
            heistId: HeistId,
            contentActivationPoint: CGPoint,
            scrollView: UIScrollView
        ) {
            guard let observedActivationPoint = InterfaceTree.ObservedScrollContentActivationPoint(contentActivationPoint) else {
                preconditionFailure("Test content activation point must be finite")
            }
            self.element = element
            self.heistId = heistId
            self.observedActivationPoint = observedActivationPoint
            self.scrollView = scrollView
        }
    }

    private func installScreenWithOffViewport(
        visible: InterfaceObservation.TestEntry,
        offscreen: OffViewportScrollTarget,
        includeLiveScrollAncestor: Bool = true,
        revealsTargetOnRefresh: Bool = false
    ) {
        let scrollContainerPath = TreePath([0])
        let visibleEntry = InterfaceTree.Element(
            heistId: visible.heistId,
            scrollMembership: nil,
            element: visible.element
        )
        let scrollContainer = makeScrollableContainer(
            contentSize: offscreen.scrollView.contentSize,
            frame: offscreen.scrollView.frame
        )
        let containerName: ContainerName = "known_offscreen_scroll"
        let offscreenEntry = InterfaceTree.Element(
            heistId: offscreen.heistId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: offscreen.observedActivationPoint,
            element: offscreen.element
        )
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [
                visibleEntry.heistId: visibleEntry,
                offscreenEntry.heistId: offscreenEntry,
            ],
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(visible.element, traversalIndex: 0)
                ])
            ],
            containerNamesByPath: [scrollContainerPath: containerName],
            heistIdsByPath: [scrollContainerPath.appending(0): visible.heistId],
            containerRefsByPath: includeLiveScrollAncestor
                ? [scrollContainerPath: .init(object: offscreen.scrollView)]
                : [:],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: includeLiveScrollAncestor
                ? [scrollContainerPath: .init(view: offscreen.scrollView)]
                : [:]
        ))
        if revealsTargetOnRefresh {
            brains.stash.nextVisibleRefreshScreenForTesting = InterfaceObservation.makeForTests(
                elements: [offscreenEntry.heistId: offscreenEntry],
                hierarchy: [
                    .container(scrollContainer, children: [
                        .element(offscreen.element, traversalIndex: 0),
                    ]),
                ],
                containerNamesByPath: [scrollContainerPath: containerName],
                heistIdsByPath: [scrollContainerPath.appending(0): offscreen.heistId],
                elementRefs: [
                    offscreen.heistId: .init(object: retainedLiveObject(), scrollView: offscreen.scrollView),
                ],
                containerRefsByPath: [scrollContainerPath: .init(object: offscreen.scrollView)],
                firstResponderHeistId: nil,
                scrollableContainerViewsByPath: [
                    scrollContainerPath: .init(view: offscreen.scrollView),
                ]
            )
        }
    }

    func testSemanticRevealNoOpsWhenAlreadyVisible() async {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visibleEntry = InterfaceTree.Element(
            heistId: "visible_element",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: makeElement(label: "Visible")
        )
        installLiveScrollTarget(visibleEntry, scrollView: scrollView, containerName: "visible_scroll")

        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            visibleEntry, deadline: semanticRevealDeadline()
        )

        guard case .alreadyVisible = result else {
            return XCTFail("Expected already-visible no-op, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    func testDirectSemanticRevealRejectsReusedIdReplacementWithoutStaleRestore() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        scrollView.contentOffset = CGPoint(x: 0, y: 80)
        let targetId: HeistId = "direct_reused_target"
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Original Target", traits: .button),
                heistId: targetId,
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            )
        )
        brains.stash.nextVisibleRefreshScreenForTesting = InterfaceObservation.makeForTests([
            .init(
                makeElement(label: "Replacement Target", traits: .button),
                heistId: targetId,
                object: retainedLiveObject()
            ),
        ])
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        scrollView.setContentOffsetAnimations.removeAll()
        let treeElement = try XCTUnwrap(brains.stash.interfaceElement(heistId: targetId))

        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            treeElement,
            deadline: semanticRevealDeadline()
        )

        guard case .failed(.noLiveScrollableAncestor) = result else {
            return XCTFail("Expected direct reused-ID evidence to fail closed, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [false])
        XCTAssertNotEqual(scrollView.contentOffset, CGPoint(x: 0, y: 80))
    }

    func testSemanticRevealFailsWithoutProvenLiveScrollAncestor() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Settings")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                offscreen,
                heistId: "settings_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )

        let entry = try XCTUnwrap(
            brains.stash.interfaceTree.findElement(heistId: "settings_button")
        )
        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            entry, deadline: semanticRevealDeadline()
        )

        guard case .failed(.noLiveScrollableAncestor) = result else {
            return XCTFail("Expected missing live scroll ancestor failure, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    func testKnownTargetRevealReturnsTimedOutInflationFailureBeforeWork() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Settings"),
                heistId: "settings_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )
        let entry = try XCTUnwrap(brains.stash.interfaceTree.findElement(heistId: "settings_button"))
        var knownTargetAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            knownTargetAttempts += 1
            return nil
        }
        let deadline = SemanticObservationDeadline(
            start: CFAbsoluteTimeGetCurrent() - 1,
            timeoutSeconds: 0
        )

        let state = await brains.navigation.elementInflation.stateAfterReveal(
            entry,
            target: try resolvedTarget(.label("Settings")),
            deadline: deadline,
            resolution: ActionSubjectResolution(origin: .known),
            transaction: .init(stash: brains.stash)
        )

        guard case .failed(let failure) = state else {
            return XCTFail("Expected typed deadline failure, got \(state)")
        }
        XCTAssertEqual(failure.failedStep, .timedOut)
        XCTAssertEqual(knownTargetAttempts, 0)
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
    }

    func testKnownTargetRevealReturnsCancelledInflationFailureBeforeWork() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Settings"),
                heistId: "settings_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )
        let entry = try XCTUnwrap(brains.stash.interfaceTree.findElement(heistId: "settings_button"))
        var knownTargetAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            knownTargetAttempts += 1
            return nil
        }
        let target = try resolvedTarget(AccessibilityTarget.label("Settings"))
        let revealTask = Task { @MainActor in
            let state = await self.brains.navigation.elementInflation.stateAfterReveal(
                entry,
                target: target,
                deadline: self.semanticRevealDeadline(),
                resolution: ActionSubjectResolution(origin: .known),
                transaction: .init(stash: self.brains.stash)
            )
            guard case .failed(let failure) = state else { return false }
            return failure.failedStep == .cancelled
        }
        revealTask.cancel()

        let wasCancelled = await revealTask.value
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(knownTargetAttempts, 0)
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
    }

    func testScrollToVisibleUnknownTargetUsesCurrentSemanticDiagnostics() async throws {
        let visible = makeElement(label: "Visible")
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(visible, HeistId(rawValue: "visible_element"))]
        ))

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .label("Missing Button"))
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertTrue(result.message?.contains("element inflation failed [notFound]") == true)
        XCTAssertTrue(result.message?.contains("No match for") == true)
        XCTAssertTrue(result.message?.contains("Missing Button") == true)
        XCTAssertFalse(result.message?.contains("get_interface") == true)
    }

    func testElementInflationNamesNoRevealPathFailure() async throws {
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [InterfaceObservation.OffViewportEntry(offscreen, heistId: "offscreen_button")]
        )

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Offscreen")),
            method: .activate
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected element inflation failure, got \(result)")
        }
        XCTAssertEqual(
            failure.failedStep,
            ElementInflation.ElementInflationFailureStep.noRevealPath,
            failure.message
        )
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
    }

    func testInflationRecordsDiscoveredOriginWhenExplorationFindsTarget() async throws {
        let baselineObject = retainedLiveObject()
        brains.stash.installScreenForTesting(.makeForTests([
            .init(makeElement(label: "Home"), heistId: "home", object: baselineObject),
        ]))
        let discoveredFrame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let discoveredElement = makeElement(
            label: "Discovered",
            traits: .button,
            shape: .frame(AccessibilityRect(discoveredFrame))
        )
        let discoveredObject = retainLiveObject(makeButton(label: "Discovered", frame: discoveredFrame))
        let discoveredScreen = InterfaceObservation.makeForTests([
            .init(
                discoveredElement,
                heistId: "discovered_button",
                object: discoveredObject
            ),
        ])
        brains.stash.nextVisibleRefreshScreenForTesting = discoveredScreen
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in
            self.brains.stash.recordParsedObservedEvidence(discoveredScreen)
            let event = self.brains.stash.semanticObservationStream
                .commitDiscoveryObservationForTesting(discoveredScreen)
            return Navigation.ExploredScreen(
                event: event,
                manifest: .init(),
                didMoveViewport: true
            )
        }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Discovered").and(.traits([.button]))),
            method: .activate
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected discovered target inflation, got \(result)")
        }
        XCTAssertTrue(inflatedTarget.liveTarget.object === discoveredObject)
        XCTAssertEqual(
            inflatedTarget.resolution,
            ActionSubjectResolution(origin: .discovered, adjustments: [.semanticReveal])
        )
    }

    func testInflationUsesNextSettledVisibleEvidenceForCommittedTarget() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "coke_button"
        let staleKnownTarget = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(makeElement(label: "Drink", traits: .header), "drink_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleKnownTarget, heistId: targetId)]
        )

        let visibleFrame = CGRect(x: 40, y: 217, width: 300, height: 96)
        let visibleTarget = AccessibilityElement.make(
            label: "Coke",
            traits: .button,
            frame: visibleFrame
        )
        let visibleObject = NSObject()
        let visibleScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                visibleTarget,
                heistId: targetId,
                object: visibleObject
            )
        ])
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        var revealAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            revealAttempts += 1
            return nil
        }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
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
        brains.stash.nextVisibleRefreshScreenForTesting = visibleScreen
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(visibleScreen)
        await inflation.value

        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail("Expected visible target inflation, got \(String(describing: resultBox.value))")
        }
        XCTAssertEqual(revealAttempts, 0)
        XCTAssertEqual(inflatedTarget.treeElement.heistId, targetId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, visibleFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, visibleFrame.midY, accuracy: 0.01)
    }

    func testRevealRetryResolvesTargetFromNextSettledObservation() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "coke_button"
        let overviewVisible = makeElement(label: "Combo Overview", traits: .header)
        let staleCoke = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(overviewVisible, "combo_overview_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleCoke, heistId: targetId)]
        )

        let arrivedFrame = CGRect(
            x: ElementInflation.interactionComfortZone.midX - 150,
            y: ElementInflation.interactionComfortZone.midY - 48,
            width: 300,
            height: 96
        )
        let arrivedCoke = AccessibilityElement.make(
            label: "Coke",
            traits: .button,
            frame: arrivedFrame
        )
        let arrivedObject = retainLiveObject(makeButton(label: "Coke", frame: arrivedFrame))
        let arrivedScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                arrivedCoke,
                heistId: targetId,
                object: arrivedObject
            )
        ])
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
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
        brains.stash.nextVisibleRefreshScreenForTesting = arrivedScreen
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(arrivedScreen)

        await inflation.value

        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail(
                "Expected settled-observation recovery of arriving target, got \(String(describing: resultBox.value))"
            )
        }
        XCTAssertEqual(inflatedTarget.treeElement.heistId, targetId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, arrivedFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, arrivedFrame.midY, accuracy: 0.01)
        XCTAssertTrue(inflatedTarget.liveTarget.object === arrivedObject)
    }

    func testRevealRetryAttemptsFreshKnownTargetOnlyOnce() async throws {
        brains.stopSemanticObservation()
        let overviewVisible = makeElement(label: "Combo Overview", traits: .header)
        let staleCoke = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(overviewVisible, "combo_overview_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleCoke, heistId: "stale_coke_button")]
        )

        let freshKnownScreen = InterfaceObservation.makeForTests(
            elements: [(overviewVisible, HeistId(rawValue: "combo_overview_header"))],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleCoke,
                    heistId: "stale_coke_button",
                    scrollContainerPath: TreePath([0])
                )
            ]
        )
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        var revealAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            revealAttempts += 1
            return nil
        }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
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
        brains.stash.nextVisibleRefreshScreenForTesting = freshKnownScreen
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(freshKnownScreen)
        await waitForSettledSemanticWaiter()
        XCTAssertEqual(revealAttempts, 1)
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(freshKnownScreen)
        await waitForSettledSemanticWaiter()
        XCTAssertEqual(revealAttempts, 1)
        inflation.cancel()

        await inflation.value
        guard case .failed(let failure)? = resultBox.value else {
            return XCTFail("Expected typed cancellation after reveal retry")
        }
        XCTAssertEqual(failure.failedStep, .cancelled)
    }

    func testRevealRetryFailsNoRevealPathAtActionDeadline() async throws {
        let overviewVisible = makeElement(label: "Combo Overview", traits: .header)
        let staleCoke = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(overviewVisible, "combo_overview_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleCoke, heistId: "stale_coke_button")]
        )
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Coke").and(.traits([.button]))),
            method: .activate
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected noRevealPath failure at the action deadline, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.noRevealPath)
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
        XCTAssertTrue(failure.message.contains("before the action deadline"))
        XCTAssertTrue(failure.message.contains("Coke"))
    }

    func testStaleLiveObjectRawRefreshDoesNotPromoteSemanticTruth() async throws {
        brains.stopSemanticObservation()
        let targetId = HeistId(rawValue: "gone_target")
        let staleTarget = AccessibilityElement.make(
            label: "Gone Target",
            traits: .button,
            frame: CGRect(x: 40, y: 120, width: 240, height: 44)
        )
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [(staleTarget, targetId)],
            objects: [targetId: nil]
        ))

        let rawTarget = AccessibilityElement.make(
            label: "Raw Replacement",
            traits: .button,
            frame: CGRect(x: 48, y: 136, width: 260, height: 44)
        )
        brains.stash.nextVisibleRefreshScreenForTesting = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                rawTarget,
                heistId: targetId,
                object: retainedLiveObject()
            )
        ])

        let target = try resolvedTarget(AccessibilityTarget.label("Gone Target").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .activate
            )
        }
        await waitForSettledSemanticWaiter()

        XCTAssertEqual(brains.stash.latestObservation.orderedElements.first?.element.label, "Raw Replacement")
        XCTAssertEqual(brains.stash.interfaceTree.orderedElements.first?.element.label, "Gone Target")
        if let committed = brains.stash.interfaceElement(heistId: targetId) {
            XCTAssertNil(brains.stash.visibleLiveElementAliasing(committed))
        } else {
            XCTFail("Expected committed semantic target to remain available")
        }

        inflation.cancel()
        await inflation.value
        guard case .failed(let failure)? = resultBox.value else {
            return XCTFail("Expected typed cancellation while waiting for settled target evidence")
        }
        XCTAssertEqual(failure.failedStep, .cancelled)
    }

    func testStaleLiveObjectRefreshResolvesNextSettledObservation() async throws {
        brains.stopSemanticObservation()
        let targetId = HeistId(rawValue: "recycled_target")
        let staleFrame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let staleTarget = AccessibilityElement.make(
            label: "Recycled Target",
            traits: .button,
            frame: staleFrame
        )
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [(staleTarget, targetId)],
            objects: [targetId: nil]
        ))

        let recoveredFrame = CGRect(x: 48, y: 136, width: 260, height: 44)
        let recoveredTarget = AccessibilityElement.make(
            label: "Recycled Target",
            traits: .button,
            frame: recoveredFrame
        )
        let recoveredObject = retainedLiveObject()
        let recoveredScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                recoveredTarget,
                heistId: targetId,
                object: recoveredObject
            )
        ])
        let target = try resolvedTarget(AccessibilityTarget.label("Recycled Target").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .scrollToVisible
            )
        }
        await waitForSettledSemanticWaiter()
        brains.stash.nextVisibleRefreshScreenForTesting = recoveredScreen
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

        await inflation.value

        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail(
                "Expected settled-observation refresh to recover target, got \(String(describing: resultBox.value))"
            )
        }
        XCTAssertEqual(inflatedTarget.treeElement.heistId, targetId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, recoveredFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, recoveredFrame.midY, accuracy: 0.01)
        XCTAssertTrue(inflatedTarget.liveTarget.object === recoveredObject)
        XCTAssertEqual(
            inflatedTarget.resolution,
            ActionSubjectResolution(
                origin: .visible,
                adjustments: [.objectDeallocationRefresh]
            )
        )
    }

    func testStaleSemanticTargetRefreshPreservesTypedWitness() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "restored_target"
        let target = try resolvedTarget(AccessibilityTarget.label("Restored Target").and(.traits([.button])))
        let originalScreen = InterfaceObservation.makeForTests([
            .init(
                makeElement(label: "Restored Target", traits: .button),
                heistId: targetId,
                object: retainedLiveObject()
            ),
        ])
        brains.stash.installScreenForTesting(originalScreen)
        let selected = try XCTUnwrap(brains.stash.interfaceElement(heistId: targetId))

        let emptyScreen = InterfaceObservation.makeForTests()
        brains.stash.installScreenForTesting(emptyScreen)
        brains.stash.nextVisibleRefreshScreenForTesting = emptyScreen

        let recoveredFrame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let recoveredElement = makeElement(
            label: "Restored Target",
            traits: .button,
            shape: .frame(AccessibilityRect(recoveredFrame))
        )
        let recoveredObject = retainLiveObject(makeButton(label: "Restored Target", frame: recoveredFrame))
        let recoveredScreen = InterfaceObservation.makeForTests([
            .init(
                recoveredElement,
                heistId: targetId,
                object: recoveredObject
            ),
        ])
        let resolutionTask = Task { @MainActor in
            let state = await self.brains.navigation.elementInflation.stateAfterRefresh(
                target: target,
                treeElement: selected,
                resolution: ActionSubjectResolution(origin: .visible),
                method: .activate,
                activationPointPolicy: .liveObjectOnly,
                deadline: SemanticObservationDeadline(
                    start: CFAbsoluteTimeGetCurrent(),
                    timeoutSeconds: 3
                )
            )
            guard case .inflated(let inflatedTarget) = state else {
                XCTFail("Expected stale target refresh to recover, got \(state)")
                return nil as ActionSubjectResolution?
            }
            XCTAssertTrue(inflatedTarget.liveTarget.object === recoveredObject)
            return inflatedTarget.resolution
        }
        await waitForSettledSemanticWaiter()
        brains.stash.nextVisibleRefreshScreenForTesting = recoveredScreen
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

        let resolution = await resolutionTask.value
        XCTAssertEqual(
            resolution,
            ActionSubjectResolution(origin: .visible, adjustments: [.staleTargetRefresh])
        )
    }

    func testActivationPointPlacementAddsTypedAdjustment() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "placed_target"
        let scrollView = RecordingScrollView(frame: ScreenMetrics.current.bounds)
        scrollView.contentSize = CGSize(
            width: ScreenMetrics.current.bounds.width,
            height: ScreenMetrics.current.bounds.height * 3
        )
        let object = retainLiveObject(UIButton(type: .system))
        let initialFrame = CGRect(
            x: 40,
            y: ScreenMetrics.current.bounds.maxY + 120,
            width: 200,
            height: 44
        )
        object.accessibilityLabel = "Placed Target"
        object.accessibilityFrame = initialFrame
        let initialActivationPoint = CGPoint(x: initialFrame.midX, y: initialFrame.midY)
        object.accessibilityActivationPoint = initialActivationPoint
        let initialElement = AccessibilityElement.make(
            label: "Placed Target",
            traits: .button,
            shape: .frame(AccessibilityRect(initialFrame)),
            activationPoint: initialActivationPoint
        )
        let initialScreen = makePlacementScreen(
            targetId: targetId,
            element: initialElement,
            object: object,
            scrollView: scrollView
        )
        brains.stash.installScreenForTesting(initialScreen)
        guard let committed = brains.stash.interfaceElement(heistId: targetId) else {
            return XCTFail("Expected placement target in committed semantic state")
        }
        switch brains.stash.resolveLiveActionTarget(for: committed) {
        case .resolved:
            break
        case .objectUnavailable:
            return XCTFail("Expected placement target to have a live object")
        case .geometryUnavailable:
            return XCTFail(
                "Expected placement target to have fresh live geometry: "
                    + String(describing: brains.stash.liveInterfaceElement(heistId: targetId)?.element.shape)
            )
        }
        XCTAssertTrue(brains.stash.liveScrollView(for: committed) === scrollView)

        let placedFrame = CGRect(
            x: ElementInflation.interactionComfortZone.midX - 100,
            y: ElementInflation.interactionComfortZone.midY - 22,
            width: 200,
            height: 44
        )
        let placedActivationPoint = CGPoint(x: placedFrame.midX, y: placedFrame.midY)
        let placedElement = AccessibilityElement.make(
            label: "Placed Target",
            traits: .button,
            shape: .frame(AccessibilityRect(placedFrame)),
            activationPoint: placedActivationPoint
        )
        let placedScreen = makePlacementScreen(
            targetId: targetId,
            element: placedElement,
            object: object,
            scrollView: scrollView
        )
        let originalMoveViewport = brains.navigation.elementInflation.exploration.moveViewport
        brains.navigation.elementInflation.exploration.moveViewport = { intent in
            object.accessibilityFrame = placedFrame
            object.accessibilityActivationPoint = placedActivationPoint
            self.brains.stash.nextVisibleRefreshScreenForTesting = placedScreen
            return await originalMoveViewport(intent)
        }
        defer {
            brains.navigation.elementInflation.exploration.moveViewport = originalMoveViewport
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(AccessibilityTarget.label("Placed Target").and(.traits([.button]))),
            method: .activate
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected activation-point placement inflation, got \(result)")
        }
        XCTAssertEqual(
            inflatedTarget.resolution,
            ActionSubjectResolution(origin: .visible, adjustments: [.activationPointPlacement])
        )
    }

    func testOffViewportTargetWithoutLiveScrollParentFailsNoRevealPath() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
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
            ),
            includeLiveScrollAncestor: false
        )
        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Offscreen")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected no-reveal-path inflation failure, got \(result)")
        }
        XCTAssertEqual(
            failure.failedStep,
            ElementInflation.ElementInflationFailureStep.noRevealPath,
            failure.message
        )
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
        XCTAssertTrue(failure.message.contains("no live scrollable ancestor"))
        XCTAssertTrue(failure.message.contains("expectedScrollContainerPath=[0]"), failure.message)
        XCTAssertTrue(failure.message.contains("available live scroll containers: path=[0]"), failure.message)
    }

    func testVisibleTargetOutsideViewportWithoutLiveScrollParentFailsGeometryNotActionable() async throws {
        let elementFrame = CGRect(
            x: 24,
            y: ScreenMetrics.current.bounds.maxY + 80,
            width: 180,
            height: 44
        )
        let object = UIButton(type: .system)
        object.accessibilityLabel = "Escaped"
        object.accessibilityFrame = elementFrame
        object.accessibilityActivationPoint = CGPoint(x: elementFrame.midX, y: elementFrame.midY)
        let element = makeElement(
            label: "Escaped",
            traits: .button,
            shape: .frame(AccessibilityRect(elementFrame))
        )
        let entry = InterfaceTree.Element(
            heistId: "escaped_button",
            scrollMembership: nil,
            element: element
        )
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Escaped")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected no-reveal-path failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.noRevealPath)
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
    }

    func testInflationRequiresActivationPointOnScreenWhenFrameIntersectsViewport() async throws {
        let elementFrame = CGRect(x: 24, y: -24, width: 180, height: 44)
        let object = UIButton(type: .system)
        object.accessibilityLabel = "Escaped"
        object.accessibilityFrame = elementFrame
        object.accessibilityActivationPoint = CGPoint(x: elementFrame.midX, y: -4)
        let element = AccessibilityElement.make(
            label: "Escaped",
            traits: .button,
            shape: .frame(AccessibilityRect(elementFrame)),
            activationPoint: object.accessibilityActivationPoint
        )
        let entry = InterfaceTree.Element(
            heistId: "escaped_button",
            scrollMembership: nil,
            element: element
        )
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Escaped")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected not-actionable failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.geometryNotActionable)
        XCTAssertTrue(failure.message.contains("element inflation failed [geometryNotActionable]"))
    }

    func testElementActionsConsumeElementInflationFailureBeforeDispatch() async throws {
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [InterfaceObservation.OffViewportEntry(offscreen, heistId: "offscreen_button")]
        )
        var didDispatch = false

        let result = await brains.actions.performElementAction(
            target: try resolvedTarget(.label("Offscreen")),
            method: .activate,
            requireInteractive: false
        ) { _ in
            didDispatch = true
            return TheSafecracker.ActionDispatchOutcome.success(method: .activate)
        }

        XCTAssertFalse(didDispatch)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, ActionMethod.activate)
        XCTAssertTrue(result.message?.contains("element inflation failed [noRevealPath]") == true)
    }

    func testElementActionPreservesFinalDispatchSubjectResolution() async throws {
        let frame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let element = makeElement(
            label: "Refreshable",
            traits: .button,
            shape: .frame(AccessibilityRect(frame))
        )
        let object = retainLiveObject(makeButton(label: "Refreshable", frame: frame))
        let screen = InterfaceObservation.makeForTests([
            .init(element, heistId: "refreshable_button", object: object),
        ])
        brains.stash.installScreenForTesting(screen)
        brains.stash.nextVisibleRefreshScreenForTesting = screen
        let target = try resolvedTarget(AccessibilityTarget.label("Refreshable").and(.traits([.button])))
        let finalResolution = ActionSubjectResolution(
            origin: .known,
            adjustments: [.staleTargetRefresh]
        )

        let result = await brains.actions.performElementAction(
            target: target,
            method: .activate,
            requireInteractive: false
        ) { context in
            .success(
                method: .activate,
                subjectEvidence: ActionSubjectEvidence(
                    source: .resolvedSemanticTarget,
                    target: target,
                    element: TheStash.WireConversion.convert(context.treeElement.element),
                    resolution: finalResolution
                )
            )
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.subjectEvidence?.resolution, finalResolution)
    }

    func testTargetedActionDoesNotRecoverFromStaleOffscreenSnapshotAfterFreshScreenChange() async throws {
        let staleScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let staleVisible = makeElement(label: "Old Visible")
        let staleOffscreen = makeElement(label: "Old Offscreen")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(staleVisible, heistId: "old_visible"),
            offscreen: OffViewportScrollTarget(
                staleOffscreen,
                heistId: "old_offscreen",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: staleScrollView
            )
        )

        let rootView = UIView()
        rootView.backgroundColor = .white
        rootView.addSubview(makeButton(label: "Fresh Visible", frame: CGRect(x: 40, y: 120, width: 240, height: 44)))
        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        brains.stash.clearInstalledVisibleRefreshScreenForTesting()

        let result = await brains.executeRuntimeAction(
            .activate(try resolvedTarget(.label("Old Offscreen")))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.outcome.errorKind, .elementNotFound)
        XCTAssertEqual(staleScrollView.contentOffset, .zero)
        XCTAssertFalse(
            result.message?.contains("after semantic reveal") ?? false,
            "Stale offscreen memory must not drive operation-local semantic reveal after a fresh screen change"
        )
    }

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
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(currentScreen)
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
        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(staleRootScreen)

        let currentHeader = makeElement(label: "Controls Demo", traits: .header)
        let currentBackButton = makeElement(label: "ButtonHeist Demo", traits: [.button, .backButton])
        let currentScreen = InterfaceObservation.makeForTests(elements: [
            (currentHeader, "current_controls_header"),
            (currentBackButton, "current_back_button"),
        ])
        brains.stash.recordParsedObservedEvidence(currentScreen)
        brains.stash.nextVisibleRefreshScreenForTesting = currentScreen

        let discovered = await brains.navigation.elementInflation.exploration.discoverTarget(
            try resolvedTarget(.label("Controls Demo").and(.traits([.button])))
        )

        XCTAssertNotNil(discovered?.event.observation.screen.findElement(heistId: "current_controls_header"))
        XCTAssertNil(discovered?.event.observation.screen.findElement(heistId: "stale_controls_button"))
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

        guard let visibleScreen = brains.stash.refreshLiveCapture() else {
            throw XCTSkip("No live hierarchy available for interface discovery contamination regression test")
        }
        guard let scrollContainerPath = visibleScreen.orderedContainers.compactMap({ container -> TreePath? in
            guard container.container.isScrollable else { return nil }
            return container.path
        }).first else {
            throw XCTSkip("Parser did not expose the test scroll view as a scroll container")
        }
        let visibleEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(visibleScreen)

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
        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(staleScreen)

        guard let exploration = await brains.navigation.exploreScreen(
            baseline: .currentViewport(brains.stash.visibleExplorationBaseline(from: visibleScreen)),
            maxScrollsPerContainer: 3,
            maxScrollsPerDiscovery: 3
        ) else {
            return XCTFail("Expected word-list exploration to settle")
        }
        let labels = brains.stash.discoveryInterface().projectedElements.compactMap(\.label)
        XCTAssertEqual(
            exploration.event.generation,
            visibleEvent.generation,
            "Canonical viewport movement must preserve one list generation"
        )
        XCTAssertGreaterThan(exploration.manifest.scrollCount, 0, "Expected discovery to scroll the word list")
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
        guard let visibleScreen = brains.stash.refreshLiveCapture() else {
            throw XCTSkip("No live hierarchy available for blank-page discovery")
        }

        guard let exploration = await brains.navigation.exploreScreen(
            target: try resolvedTarget(.label("Beyond Blank Page")),
            baseline: .currentViewport(brains.stash.visibleExplorationBaseline(from: visibleScreen)),
            exitPosition: .origin,
            maxScrollsPerContainer: 4,
            maxScrollsPerDiscovery: 4
        ) else {
            return XCTFail("Expected discovery to cross the blank viewport")
        }

        XCTAssertGreaterThanOrEqual(exploration.manifest.scrollCount, 2)
        XCTAssertNotNil(brains.stash.interfaceTree.orderedElements.first {
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

        guard let visibleScreen = brains.stash.refreshLiveCapture() else {
            throw XCTSkip("No live hierarchy available for wait discovery restoration")
        }
        guard let exploration = await brains.navigation.exploreScreen(
            target: try resolvedTarget(.label("Wait Discovery Target")),
            baseline: .currentViewport(brains.stash.visibleExplorationBaseline(from: visibleScreen)),
            exitPosition: .origin,
            maxScrollsPerContainer: 3,
            maxScrollsPerDiscovery: 3
        ) else {
            return XCTFail("Expected wait discovery to find the offscreen target")
        }

        XCTAssertNotNil(exploration.event.observation.screen.orderedElements.first {
            $0.element.label == "Wait Discovery Target"
        })
        XCTAssertEqual(
            Navigation.visualOrigin(in: scrollView).y,
            initialVisualOrigin.y,
            accuracy: 0.01
        )
        XCTAssertFalse(exploration.event.observation.screen.liveCapture.hierarchy.sortedElements.contains {
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
        _ = brains.stash.refreshLiveCapture()

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .label("Top Target"))
            )
        )

        XCTAssertTrue(result.success, "Expected scroll_to_visible to discover the target above; got \(result)")
        XCTAssertLessThanOrEqual(scrollView.contentOffset.y, 10)
        XCTAssertTrue(brains.stash.latestObservation.orderedElements.contains {
            $0.element.label == "Top Target"
        })
    }

    func testKnownSemanticRevealIgnoresStaleDetachedScrollView() async throws {
        let staleScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        brains.stash.installScreenForTesting(.makeForTests(
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
        brains.stash.nextVisibleRefreshScreenForTesting = recoveredScreen
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

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
        XCTAssertTrue(recoveredScreen.viewportElementIDs.contains(recoveredEntry.heistId))
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
        brains.stash.nextVisibleRefreshScreenForTesting = recoveredScreen
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)
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
        XCTAssertFalse(brains.stash.liveScrollView(for: inflatedTarget.treeElement) === staleScrollView)
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
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            containerRefsByPath: [TreePath([0]): .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        ))
        let baselineSequence = brains.stash.latestSettledSemanticObservationEvent?.sequence

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget())
        )

        XCTAssertTrue(result.success, "Expected default scroll to pick the only visible container: \(String(describing: result.message))")
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        let committedMovement = try XCTUnwrap(brains.stash.latestSettledSemanticObservationEvent)
        XCTAssertEqual(committedMovement.scope, .discovery)
        XCTAssertNotEqual(committedMovement.sequence, baselineSequence)
    }

    func testScrollToEdgeWithoutElementDefaultsTop() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        scrollView.contentOffset.y = 600
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
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
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
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
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
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
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
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

        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
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
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
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
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
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
        let liveScreen = try XCTUnwrap(
            brains.stash.refreshLiveCapture(),
            "No live hierarchy available for scroll_to_visible post-reveal regression test"
        )
        guard let scrollContainerPath = liveScreen.liveCapture.hierarchy.scrollablePathIndexedContainers.first(where: {
            liveScreen.liveCapture.scrollView(forContainerPath: $0.path) != nil
        })?.path else {
            throw XCTSkip("No live hierarchy available for scroll_to_visible post-reveal regression test")
        }
        if brains.stash.resolveTarget(
            literalTarget(ElementPredicate.label("Jump Target"), ordinal: 0)
        ).resolved != nil {
            throw XCTSkip("Parser exposed offscreen scroll content before semantic reveal")
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
        brains.stash.installScreenForTesting(knownScreen)
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

    // MARK: - Element Scroll Target Resolution

    func testScrollWithVisibleElementReportsMissingScrollableAncestor() async throws {
        let treeElement = InterfaceTree.Element(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [treeElement.heistId: treeElement],
            hierarchy: [.element(treeElement.element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): treeElement.heistId],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(
            result.message,
            "scroll target failed: observed \"Item\" with no live scrollable ancestor; "
                + "target an element inside the intended scroll region"
        )
    }

    func testScrollWithVisibleElementReportsAxisMismatch() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 200)

        let treeElement = InterfaceTree.Element(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        installLiveScrollTarget(treeElement, scrollView: scrollView, containerName: "axis_scroll")

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(
            result.message,
            "scroll target failed: observed \"Item\" inside a scroll view that supports no scrolling; "
                + "expected vertical scrolling; try a matching scroll direction or target an element "
                + "inside the intended scroll region"
        )
    }

    func testScrollWithVisibleElementUsesElementScrollViewWhenAxisMatches() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 1200)

        let treeElement = InterfaceTree.Element(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        installLiveScrollTarget(treeElement, scrollView: scrollView, containerName: "vertical_scroll")

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down))
        )

        XCTAssertTrue(result.success, "Expected element scroll to succeed: \(String(describing: result.message))")
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
    }

    // MARK: - safeSwipeFrame

    func testScrollableTargetUsesAccessibilityContainerFrameForSemanticOnlySwipeFallback() throws {
        let captureFrame = CGRect(x: 40, y: 120, width: 240, height: 360)
        let contentSize = AccessibilitySize(width: 320, height: 2000)
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: contentSize,
            frame: AccessibilityRect(captureFrame)
        )
        let path = TreePath([0])
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: retainedLiveObject())],
            firstResponderHeistId: nil
        ))

        let target = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        guard case .swipeable(let liveContainer, let resolvedContentSize) = target else {
            XCTFail("Expected semantic-only scroll container to use swipeable accessibility geometry")
            return
        }
        XCTAssertEqual(liveContainer.frame, captureFrame)
        XCTAssertEqual(resolvedContentSize, contentSize.cgSize)
    }

    func testScrollableTargetUsesPathKeyedLiveScrollView() throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let contentSize = AccessibilitySize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        let path = TreePath([0])
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [path: "main_scroll"],
            containerRefsByPath: [path: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: scrollView)]
        ))

        let target = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        guard case .uiScrollView(_, let resolvedScrollView) = target else {
            XCTFail("Expected path-keyed UIScrollView target, got \(target)")
            return
        }
        XCTAssertTrue(resolvedScrollView === scrollView)
    }

    func testPageScrollReacquiresContainerFromCurrentCapture() async throws {
        let path = TreePath([0])
        let oldScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        oldScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: oldScrollView.contentSize, frame: oldScrollView.frame)
        let contentSize = try XCTUnwrap(container.scrollableContentSize)
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: oldScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: oldScrollView)]
        ))
        let staleTarget = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        let replacementScrollView = UIScrollView(frame: oldScrollView.frame)
        replacementScrollView.contentSize = oldScrollView.contentSize
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: replacementScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: replacementScrollView)]
        ))

        let proof = await brains.navigation.scrollOnePageAndSettle(
            staleTarget,
            direction: .down,
            animated: false
        )

        XCTAssertEqual(proof.result, .moved)
        XCTAssertEqual(oldScrollView.contentOffset, .zero)
        XCTAssertGreaterThan(replacementScrollView.contentOffset.y, 0)
    }

    func testEdgeScrollReacquiresContainerFromCurrentCapture() async throws {
        let path = TreePath([0])
        let oldScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        oldScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: oldScrollView.contentSize, frame: oldScrollView.frame)
        let contentSize = try XCTUnwrap(container.scrollableContentSize)
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: oldScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: oldScrollView)]
        ))
        let staleTarget = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        let replacementScrollView = UIScrollView(frame: oldScrollView.frame)
        replacementScrollView.contentSize = oldScrollView.contentSize
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: replacementScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: replacementScrollView)]
        ))

        let proof = await brains.navigation.scrollToEdgeAndSettle(staleTarget, edge: .bottom)

        XCTAssertEqual(proof.result, .moved)
        XCTAssertEqual(oldScrollView.contentOffset, .zero)
        XCTAssertEqual(replacementScrollView.contentOffset.y, 1_200)
    }

    func testSafeSwipeFrameFullyInSafeBoundsIsUnchanged() throws {
        // A frame sitting comfortably inside the safe area passes through
        // intersected with itself, which is the frame.
        let screen = UIScreen.main.bounds
        let inner = screen.insetBy(dx: 80, dy: 120)
        let result = try XCTUnwrap(brains.navigation.safeSwipeFrame(from: inner))
        XCTAssertEqual(result, inner)
    }

    func testSafeSwipeFrameZeroWidthReturnsNil() {
        // Degenerate input has no targetable on-screen geometry, so command
        // execution must fail instead of swiping the stale original frame.
        let input = CGRect(x: 0, y: 0, width: 0, height: 100)
        XCTAssertNil(brains.navigation.safeSwipeFrame(from: input))
    }

    func testSafeSwipeFrameFullyOffscreenReturnsNil() {
        let input = CGRect(x: -500, y: -500, width: 100, height: 100)
        XCTAssertNil(brains.navigation.safeSwipeFrame(from: input))
    }

    func testSafeSwipeFrameOversizedFrameClampsWithinScreen() throws {
        // A frame larger than any iPhone screen must clamp to the safe
        // region and stay within the current screen bounds.
        let huge = CGRect(x: -1000, y: -1000, width: 10000, height: 10000)
        let result = try XCTUnwrap(brains.navigation.safeSwipeFrame(from: huge))
        let screenBounds = UIScreen.main.bounds
        XCTAssertTrue(
            screenBounds.contains(result),
            "Result \(result) must fit within the screen \(screenBounds)"
        )
    }

    func testSafeSwipeFrameClampsAboveTabBarContainer() throws {
        // A .tabBar container in the accessibility hierarchy defines the
        // bottom clear line. A swipe rectangle that overlaps the tab bar
        // must be clipped to end at its top edge.
        let tabBarFrame = CGRect(x: 0, y: 700, width: 400, height: 80)
        let tabBarContainer = AccessibilityContainer(type: .tabBar, frame: AccessibilityRect(tabBarFrame))
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(tabBarContainer, children: [])],
            firstResponderHeistId: nil,
        ))
        let result = try XCTUnwrap(
            brains.navigation.safeSwipeFrame(from: CGRect(x: 100, y: 400, width: 200, height: 500))
        )
        XCTAssertEqual(
            result.maxY, tabBarFrame.minY,
            "Swipe area must end at the tab bar's top edge"
        )
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = .none,
        shape: AccessibilityElement.Shape = .frame(AccessibilityRect.zero)
    ) -> AccessibilityElement {
        .make(label: label, traits: traits, shape: shape, respondsToUserInteraction: false)
    }

    private func makePlacementScreen(
        targetId: HeistId,
        element: AccessibilityElement,
        object: NSObject,
        scrollView: UIScrollView
    ) -> InterfaceObservation {
        let containerPath = TreePath([0])
        let scrollMembership = InterfaceTree.ScrollMembership(containerPath: containerPath, index: nil)
        let treeElement = InterfaceTree.Element(
            heistId: targetId,
            scrollMembership: scrollMembership,
            element: element
        )
        let container = makeScrollableContainer(
            contentSize: scrollView.contentSize,
            frame: scrollView.frame
        )
        return InterfaceObservation.makeForTests(
            elements: [targetId: treeElement],
            hierarchy: [
                .container(container, children: [
                    .element(element, traversalIndex: 0),
                ]),
            ],
            heistIdsByPath: [containerPath.appending(0): targetId],
            elementRefs: [targetId: .init(object: object, scrollView: scrollView)],
            containerRefsByPath: [containerPath: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [containerPath: .init(view: scrollView)]
        )
    }

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 320, height: 2000),
        frame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 400)
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(contentSize),
            frame: AccessibilityRect(frame)
        )
    }

    private func installScrollableContainers(_ containers: [AccessibilityContainer]) {
        let containerRefs = Dictionary(uniqueKeysWithValues: containers.indices.map { index in
            (TreePath([index]), LiveCapture.ContainerRef(object: retainedLiveObject()))
        })
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: containers.map { .container($0, children: []) },
            containerRefsByPath: containerRefs,
            firstResponderHeistId: nil,
        ))
    }

    private func installLiveScrollTarget(
        _ treeElement: InterfaceTree.Element,
        scrollView: UIScrollView,
        containerName: ContainerName
    ) {
        let container = makeScrollableContainer(
            contentSize: scrollView.contentSize,
            frame: scrollView.frame
        )
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [treeElement.heistId: treeElement],
            hierarchy: [
                .container(container, children: [
                    .element(treeElement.element, traversalIndex: 0)
                ])
            ],
            containerNamesByPath: [TreePath([0]): containerName],
            heistIdsByPath: [TreePath([0, 0]): treeElement.heistId],
            elementRefs: [
                treeElement.heistId: .init(object: nil, scrollView: scrollView)
            ],
            containerRefsByPath: [TreePath([0]): .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                TreePath([0]): .init(view: scrollView)
            ]
        ))
    }

    private func makeButton(label: String, frame: CGRect) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(label, for: .normal)
        button.accessibilityLabel = label
        button.isAccessibilityElement = true
        button.frame = frame
        return button
    }

    private func makeAccessibleView(label: String, frame: CGRect) -> UIView {
        let view = UIView(frame: frame)
        view.backgroundColor = .white
        view.accessibilityLabel = label
        view.accessibilityTraits = .button
        view.isAccessibilityElement = true
        return view
    }

    private func installModalWindow(rootView: UIView) throws -> UIWindow {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view = rootView
        viewController.view.frame = UIScreen.main.bounds
        viewController.view.accessibilityViewIsModal = true

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 30
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    private final class PageDataSource: NSObject, UIPageViewControllerDataSource {
        let pages: [UIViewController]

        init(pages: [UIViewController]) {
            self.pages = pages
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let index = pages.firstIndex(of: viewController),
                  index > 0 else {
                return nil
            }
            return pages[index - 1]
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let index = pages.firstIndex(of: viewController),
                  index < pages.count - 1 else {
                return nil
            }
            return pages[index + 1]
        }
    }

    private final class PageContentViewController: UIViewController {
        private let pageLabel: String

        init(label: String) {
            self.pageLabel = label
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .white

            let label = UILabel()
            label.text = pageLabel
            label.accessibilityLabel = pageLabel
            label.isAccessibilityElement = true
            label.frame = CGRect(x: 40, y: 120, width: 280, height: 44)
            view.addSubview(label)
        }
    }

    private enum AccessibilityRevealMode {
        case atOrAbove
        case atOrBelow
    }

    private final class AccessibilityRevealingScrollView: UIScrollView {
        var revealedElements: [UIView] = []
        var revealThreshold: CGFloat = 500
        var revealMode: AccessibilityRevealMode = .atOrBelow

        override var contentOffset: CGPoint {
            didSet {
                updateAccessibilityVisibility()
            }
        }

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            super.setContentOffset(contentOffset, animated: animated)
            updateAccessibilityVisibility(for: contentOffset)
        }

        func updateAccessibilityVisibility(for offset: CGPoint? = nil) {
            let y = (offset ?? contentOffset).y
            let isRevealed: Bool
            switch revealMode {
            case .atOrAbove:
                isRevealed = y <= revealThreshold
            case .atOrBelow:
                isRevealed = y >= revealThreshold
            }
            for element in revealedElements {
                element.isHidden = !isRevealed
                element.isAccessibilityElement = isRevealed
            }
        }
    }

    private final class RecordingScrollView: UIScrollView {
        var setContentOffsetAnimations: [Bool] = []
        var onSetContentOffset: (@MainActor (RecordingScrollView) -> Void)?

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            setContentOffsetAnimations.append(animated)
            onSetContentOffset?(self)
            super.setContentOffset(contentOffset, animated: animated)
        }
    }
}

private extension UIView {
    var nearestScrollableSuperviewForTesting: UIScrollView? {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            ancestor = current.superview
        }
        return nil
    }
}

#endif
