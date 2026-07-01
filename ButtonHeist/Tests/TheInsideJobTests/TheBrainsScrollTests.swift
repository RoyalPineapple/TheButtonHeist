#if canImport(UIKit)
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class TheBrainsScrollTests: XCTestCase {

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

    private func observedContentActivationPoint(
        _ point: CGPoint
    ) -> Screen.ObservedScrollContentActivationPoint {
        guard let observedPoint = Screen.ObservedScrollContentActivationPoint(point) else {
            preconditionFailure("Test content activation point must be finite")
        }
        return observedPoint
    }

    // MARK: - Programmatic Scroll Safety

    func testTargetUnavailableScrollFailureMapsToElementNotFoundErrorKind() {
        let result = TheSafecracker.InteractionResult.failure(
            .scrollToVisible,
            message: "element inflation failed [notFound]: missing",
            failureKind: .targetUnavailable
        )

        XCTAssertEqual(TheBrains.actionErrorKind(for: result), .elementNotFound)
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

        let exploration = await brains.navigation.exploreScreen()
        let manifest = exploration.manifest

        XCTAssertEqual(manifest.scrollCount, 0)
        for scrollView in unsafeTargets {
            XCTAssertEqual(Optional(scrollView.contentOffset), unsafeOffsets[ObjectIdentifier(scrollView)])
        }
        XCTAssertTrue(
            exploration.screen.semantic.elements.values.contains {
                $0.element.label == "Page One Visible Label"
            },
            "Visible page content should remain discoverable without scrolling the private queuing scroll view"
        )
    }

    // MARK: - semanticRevealTargetOffset (Pure Math)

    func testScrollTargetOffsetCentersOnContentPoint() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        scrollView.contentInset = .zero

        let contentPoint = CGPoint(x: 100, y: 2500)
        let offset = ElementInflation.semanticRevealTargetOffset(
            for: observedContentActivationPoint(contentPoint),
            in: scrollView
        )

        XCTAssertEqual(offset.x, max(contentPoint.x - 375.0 / 2, 0), accuracy: 0.01)
        XCTAssertEqual(offset.y, contentPoint.y - 667.0 / 2, accuracy: 0.01)
    }

    func testScrollTargetOffsetClampsToTop() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)

        let offset = ElementInflation.semanticRevealTargetOffset(
            for: observedContentActivationPoint(CGPoint(x: 100, y: 100)),
            in: scrollView
        )

        XCTAssertGreaterThanOrEqual(offset.y, 0)
    }

    func testScrollTargetOffsetClampsToBottom() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)

        let offset = ElementInflation.semanticRevealTargetOffset(
            for: observedContentActivationPoint(CGPoint(x: 100, y: 4900)),
            in: scrollView
        )

        let maxY = scrollView.contentSize.height - scrollView.bounds.height
        XCTAssertLessThanOrEqual(offset.y, maxY + 0.01)
    }

    func testScrollTargetOffsetRespectsContentInsets() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        scrollView.contentInset = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)

        let offset = ElementInflation.semanticRevealTargetOffset(
            for: observedContentActivationPoint(CGPoint(x: 100, y: 10)),
            in: scrollView
        )

        XCTAssertGreaterThanOrEqual(offset.y, -scrollView.adjustedContentInset.top)
    }

    func testScrollTargetOffsetCentersWithinAdjustedVisibleRect() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        scrollView.contentSize = CGSize(width: 3000, height: 5000)
        scrollView.contentInset = UIEdgeInsets(top: 100, left: 20, bottom: 50, right: 60)

        let contentPoint = CGPoint(x: 1000, y: 1800)
        let offset = ElementInflation.semanticRevealTargetOffset(
            for: observedContentActivationPoint(contentPoint),
            in: scrollView
        )

        let insets = scrollView.adjustedContentInset
        let visibleWidth = scrollView.bounds.width - insets.left - insets.right
        let visibleHeight = scrollView.bounds.height - insets.top - insets.bottom
        XCTAssertEqual(offset.x + insets.left + visibleWidth / 2, contentPoint.x, accuracy: 0.01)
        XCTAssertEqual(offset.y + insets.top + visibleHeight / 2, contentPoint.y, accuracy: 0.01)
    }

    func testScrollTargetOffsetHorizontalClamping() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 2000, height: 667)

        let offsetStart = ElementInflation.semanticRevealTargetOffset(
            for: observedContentActivationPoint(CGPoint(x: 50, y: 300)),
            in: scrollView
        )
        XCTAssertGreaterThanOrEqual(offsetStart.x, 0)

        let offsetEnd = ElementInflation.semanticRevealTargetOffset(
            for: observedContentActivationPoint(CGPoint(x: 1950, y: 300)),
            in: scrollView
        )
        let maxX = scrollView.contentSize.width - scrollView.bounds.width
        XCTAssertLessThanOrEqual(offsetEnd.x, maxX + 0.01)
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
        let labeled = TheStash.ScreenElement(
            heistId: "labeled_item",
            scrollMembership: nil,
            element: AccessibilityElement.make(label: "Labeled", identifier: "labeled_id")
        )
        let identified = TheStash.ScreenElement(
            heistId: "identified_item",
            scrollMembership: nil,
            element: AccessibilityElement.make(identifier: "identified_id")
        )
        let anonymous = TheStash.ScreenElement(
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
        let firstEntry = Screen.ScreenElement(
            heistId: "duplicate_button_1",
            scrollMembership: nil,
            element: duplicate
        )
        let secondEntry = Screen.ScreenElement(
            heistId: "duplicate_button_2",
            scrollMembership: nil,
            element: duplicate
        )

        brains.stash.installScreenForTesting(Screen(
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
            brains.stash.liveVisibleScreen.orderedElements.map(\.heistId),
            [firstEntry.heistId, secondEntry.heistId]
        )
    }

    func testResolveLiveActionTargetFailsClosedWhenWeakObjectIsStale() async {
        let element = makeElement(label: "Detached", traits: .button)
        let entry = Screen.ScreenElement(
            heistId: "detached_button",
            scrollMembership: nil,
            element: element
        )
        var object: NSObject? = NSObject()
        brains.stash.installScreenForTesting(Screen(
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

    /// Install a Screen whose `elements` includes an entry that's not in the
    /// live hierarchy — simulating an element retained from a previous
    /// exploration commit that has since scrolled off.
    private func makeScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, HeistId)],
        offViewport: [Screen.OffViewportEntry]
    ) -> Screen {
        .makeForTests(
            elements: liveHierarchy.map { ($0.0, $0.1) },
            offViewport: offViewport
        )
    }

    private func installScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, HeistId)],
        offViewport: [Screen.OffViewportEntry]
    ) {
        brains.stash.installScreenForTesting(makeScreenWithOffViewportEntry(
            liveHierarchy: liveHierarchy,
            offViewport: offViewport
        ))
    }

    private struct KnownOffscreenScrollTarget {
        let element: AccessibilityElement
        let heistId: HeistId
        let observedActivationPoint: Screen.ObservedScrollContentActivationPoint
        let scrollView: UIScrollView

        init(
            _ element: AccessibilityElement,
            heistId: HeistId,
            contentActivationPoint: CGPoint,
            scrollView: UIScrollView
        ) {
            guard let observedActivationPoint = Screen.ObservedScrollContentActivationPoint(contentActivationPoint) else {
                preconditionFailure("Test content activation point must be finite")
            }
            self.element = element
            self.heistId = heistId
            self.observedActivationPoint = observedActivationPoint
            self.scrollView = scrollView
        }
    }

    private func installScreenWithKnownOffscreen(
        visible: Screen.TestEntry,
        offscreen: KnownOffscreenScrollTarget,
        includeLiveScrollAncestor: Bool = true,
        scrollContainerPath: TreePath = TreePath([0])
    ) {
        let visibleEntry = Screen.ScreenElement(
            heistId: visible.heistId,
            scrollMembership: nil,
            element: visible.element
        )
        let scrollContainer = makeScrollableContainer(
            contentSize: offscreen.scrollView.contentSize,
            frame: offscreen.scrollView.frame
        )
        let containerName: ContainerName = "known_offscreen_scroll"
        let offscreenEntry = Screen.ScreenElement(
            heistId: offscreen.heistId,
            scrollMembership: Screen.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: offscreen.observedActivationPoint,
            element: offscreen.element
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [
                visibleEntry.heistId: visibleEntry,
                offscreenEntry.heistId: offscreenEntry,
            ],
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(visible.element, traversalIndex: 0)
                ])
            ],
            containerNamesByPath: [TreePath([0]): containerName],
            heistIdsByPath: [TreePath([0, 0]): visible.heistId],
            elementRefs: includeLiveScrollAncestor ? [
                offscreenEntry.heistId: .init(object: nil, scrollView: offscreen.scrollView)
            ] : [:],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: includeLiveScrollAncestor
                ? [TreePath([0]): .init(view: offscreen.scrollView)]
                : [:]
        ))
    }

    func testSemanticRevealNoOpsWhenAlreadyVisible() async {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visibleEntry = Screen.ScreenElement(
            heistId: "visible_element",
            scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: makeElement(label: "Visible")
        )
        installLiveScrollTarget(visibleEntry, scrollView: scrollView, containerName: "visible_scroll")

        let result = await brains.navigation.elementInflation.revealSemanticTarget(visibleEntry)

        guard case .alreadyVisible = result else {
            return XCTFail("Expected already-visible no-op, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    func testSemanticRevealDoesNotNoopWhenVisibleIdRepresentsDifferentElement() async {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        scrollView.contentOffset = CGPoint(x: 0, y: 800)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        let containerName: ContainerName = "reused_cell_scroll"
        let target = makeElement(label: "Controls Demo", traits: .button)
        let currentlyVisibleReuse = makeElement(label: "Custom Rotors", traits: .button)
        let entry = Screen.ScreenElement(
            heistId: "reused_cell",
            scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: nil),
            observedScrollContentActivationPoint: observedContentActivationPoint(CGPoint(x: 0, y: 100)),
            element: target
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [
                .container(container, children: [
                    .element(currentlyVisibleReuse, traversalIndex: 0)
                ])
            ],
            containerNamesByPath: [TreePath([0]): containerName],
            heistIdsByPath: [TreePath([0, 0]): entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: nil, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                TreePath([0]): .init(view: scrollView)
            ]
        ))

        let result = await brains.navigation.elementInflation.revealSemanticTarget(entry)

        guard case .revealed = result else {
            return XCTFail("Expected reused visible id to trigger semantic reveal, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [false])
        XCTAssertLessThan(scrollView.contentOffset.y, 100)
    }

    func testSemanticRevealUsesNonAnimatedJumpForKnownOffscreenElement() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Settings")
        let contentActivationPoint = CGPoint(x: 0, y: 1_200)
        let observedActivationPoint = try XCTUnwrap(Screen.ObservedScrollContentActivationPoint(contentActivationPoint))
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(visible, heistId: "visible_element"),
            offscreen: KnownOffscreenScrollTarget(
                offscreen,
                heistId: "settings_button",
                contentActivationPoint: contentActivationPoint,
                scrollView: scrollView
            )
        )

        let entry = try XCTUnwrap(
            brains.stash.settledSemanticScreen.findElement(heistId: "settings_button")
        )
        let result = await brains.navigation.elementInflation.revealSemanticTarget(entry)

        guard case .revealed = result else {
            return XCTFail("Expected semantic reveal to resolve, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [false])
        let expectedOffset = ElementInflation.semanticRevealTargetOffset(for: observedActivationPoint, in: scrollView)
        XCTAssertEqual(scrollView.contentOffset.x, expectedOffset.x, accuracy: 0.01)
        XCTAssertEqual(scrollView.contentOffset.y, expectedOffset.y, accuracy: 0.01)
    }

    func testSemanticRevealFailsWithoutProvenLiveScrollAncestor() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Settings")
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(visible, heistId: "visible_element"),
            offscreen: KnownOffscreenScrollTarget(
                offscreen,
                heistId: "settings_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )

        let entry = try XCTUnwrap(
            brains.stash.settledSemanticScreen.findElement(heistId: "settings_button")
        )
        let result = await brains.navigation.elementInflation.revealSemanticTarget(entry)

        guard case .failed(.noLiveScrollableAncestor) = result else {
            return XCTFail("Expected missing live scroll ancestor failure, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    func testScrollToVisibleUnknownTargetUsesCurrentSemanticDiagnostics() async {
        let visible = makeElement(label: "Visible")
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(visible, HeistId(rawValue: "visible_element"))]
        ))

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Missing Button")))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertTrue(result.message?.contains("element inflation failed [notFound]") == true)
        XCTAssertTrue(result.message?.contains("No match for") == true)
        XCTAssertTrue(result.message?.contains("Missing Button") == true)
        XCTAssertFalse(result.message?.contains("get_interface") == true)
    }

    func testElementInflationNamesNoRevealPathFailure() async {
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [Screen.OffViewportEntry(offscreen, heistId: "offscreen_button")]
        )

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Offscreen")),
            method: .activate,
            deallocatedBoundary: "test inflation"
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
        XCTAssertTrue(failure.message.contains("has no scroll membership"))
    }

    func testInflationUsesFreshVisibleTargetBeforeKnownNoRevealPath() async {
        let staleKnownTarget = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(makeElement(label: "Drink", traits: .header), "drink_header")],
            offViewport: [Screen.OffViewportEntry(staleKnownTarget, heistId: "stale_coke_button")]
        )

        let visibleFrame = CGRect(x: 40, y: 217, width: 300, height: 96)
        let visibleTarget = AccessibilityElement.make(
            label: "Coke",
            traits: .button,
            frame: visibleFrame
        )
        let visibleObject = NSObject()
        let visibleScreen = Screen.makeForTests([
            Screen.TestEntry(
                visibleTarget,
                heistId: "current_coke_button",
                object: visibleObject
            )
        ])
        var discoveryAttempts = 0
        brains.navigation.elementInflation.discoverTarget = { _ in
            discoveryAttempts += 1
            self.brains.stash.nextVisibleRefreshScreenForTesting = visibleScreen
            _ = self.brains.stash.refreshLiveCapture()
            return nil
        }
        var revealAttempts = 0
        brains.navigation.elementInflation.revealKnownTarget = { _ in
            revealAttempts += 1
            return nil
        }
        defer {
            brains.navigation.elementInflation.discoverTarget = nil
            brains.navigation.elementInflation.revealKnownTarget = nil
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Coke", traits: [.button])),
            method: .activate,
            deallocatedBoundary: "test inflation"
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected visible target inflation, got \(result)")
        }
        XCTAssertEqual(discoveryAttempts, 1)
        XCTAssertEqual(revealAttempts, 0)
        XCTAssertEqual(inflatedTarget.screenElement.heistId, "current_coke_button")
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, visibleFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, visibleFrame.midY, accuracy: 0.01)
    }

    func testStaleLiveObjectRefreshExhaustsRetryState() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        rootView.addSubview(makeButton(label: "Current Visible", frame: CGRect(x: 40, y: 120, width: 240, height: 44)))
        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let staleTarget = AccessibilityElement.make(
            label: "Gone Target",
            traits: .button,
            frame: CGRect(x: 40, y: 120, width: 240, height: 44),
            respondsToUserInteraction: false
        )
        let staleScreen = Screen.makeForTests(
            elements: [(staleTarget, HeistId(rawValue: "gone_target"))],
            objects: [HeistId(rawValue: "gone_target"): nil]
        )
        var discoveryAttempts = 0
        brains.navigation.elementInflation.discoverTarget = { _ in
            discoveryAttempts += 1
            return staleScreen
        }
        defer {
            brains.navigation.elementInflation.discoverTarget = nil
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Gone Target", traits: [.button])),
            method: .activate,
            deallocatedBoundary: "test inflation"
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected stale refresh failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, .staleRefresh)
        XCTAssertEqual(failure.failureKind, .targetUnavailable)
        XCTAssertEqual(discoveryAttempts, 2)
        XCTAssertTrue(failure.message.contains("element inflation failed [staleRefresh]"))
        XCTAssertTrue(failure.message.contains("inflation exhausted 2 retry attempts"))
        XCTAssertTrue(failure.message.contains("the live object was deallocated"))
        XCTAssertFalse(failure.message.contains("target was not found in fresh live geometry"))
    }

    func testKnownOffscreenTargetWithoutLiveScrollParentFailsNoRevealPath() async {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(visible, heistId: "visible_element"),
            offscreen: KnownOffscreenScrollTarget(
                offscreen,
                heistId: "offscreen_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false,
            scrollContainerPath: TreePath([99])
        )
        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Offscreen")),
            method: .scrollToVisible,
            deallocatedBoundary: "scroll_to_visible dispatch"
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
    }

    func testVisibleTargetOutsideViewportWithoutLiveScrollParentFailsGeometryNotActionable() async {
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
        let entry = Screen.ScreenElement(
            heistId: "escaped_button",
            scrollMembership: nil,
            element: element
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Escaped")),
            method: .scrollToVisible,
            deallocatedBoundary: "test inflation"
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected no-reveal-path failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.noRevealPath)
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
    }

    func testInflationRequiresActivationPointOnScreenWhenFrameIntersectsViewport() async {
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
        let entry = Screen.ScreenElement(
            heistId: "escaped_button",
            scrollMembership: nil,
            element: element
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Escaped")),
            method: .scrollToVisible,
            deallocatedBoundary: "test inflation"
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected not-actionable failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.geometryNotActionable)
        XCTAssertTrue(failure.message.contains("element inflation failed [geometryNotActionable]"))
    }

    func testElementActionsConsumeElementInflationFailureBeforeDispatch() async {
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [Screen.OffViewportEntry(offscreen, heistId: "offscreen_button")]
        )
        var didDispatch = false

        let result = await brains.actions.performElementAction(
            target: .predicate(ElementPredicate(label: "Offscreen")),
            method: .activate,
            requireInteractive: false
        ) { _ in
            didDispatch = true
            return TheSafecracker.InteractionResult.success(method: .activate)
        }

        XCTAssertFalse(didDispatch)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, ActionMethod.activate)
        XCTAssertTrue(result.message?.contains("element inflation failed [noRevealPath]") == true)
    }

    func testTargetedActionDoesNotRecoverFromStaleOffscreenSnapshotAfterFreshScreenChange() async throws {
        let staleScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let staleVisible = makeElement(label: "Old Visible")
        let staleOffscreen = makeElement(label: "Old Offscreen")
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(staleVisible, heistId: "old_visible"),
            offscreen: KnownOffscreenScrollTarget(
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

        let result = await brains.executeRuntimeAction(.activate(.predicate(ElementPredicate(label: "Old Offscreen"))))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.errorKind, .elementNotFound)
        XCTAssertEqual(staleScrollView.contentOffset, .zero)
        XCTAssertFalse(
            result.message?.contains("after semantic reveal") ?? false,
            "Stale offscreen memory must not drive operation-local semantic reveal after a fresh screen change"
        )
    }

    func testTargetDiscoveryMissDoesNotRevealStaleKnownOffscreenTarget() async {
        let staleScrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let staleVisible = makeElement(label: "Root Visible")
        let staleRootButton = makeElement(label: "Controls Demo", traits: .button)
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(staleVisible, heistId: "root_visible"),
            offscreen: KnownOffscreenScrollTarget(
                staleRootButton,
                heistId: "stale_controls_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: staleScrollView
            )
        )

        let currentHeader = makeElement(label: "Controls Demo", traits: .header)
        let currentBackButton = makeElement(label: "ButtonHeist Demo", traits: [.button, .backButton])
        let currentScreen = Screen.makeForTests(elements: [
            (currentHeader, "current_controls_header"),
            (currentBackButton, "current_back_button"),
        ])
        var discoveryAttempts = 0
        brains.navigation.elementInflation.discoverTarget = { _ in
            discoveryAttempts += 1
            return currentScreen
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Controls Demo", traits: [.button])),
            method: .activate,
            deallocatedBoundary: "test inflation"
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

    func testActionTargetDiscoveryStartsFromCurrentVisibleScreen() async {
        let staleVisible = makeElement(label: "Root Visible")
        let staleRootButton = makeElement(label: "Controls Demo", traits: .button)
        let staleRootScreen = makeScreenWithOffViewportEntry(
            liveHierarchy: [(staleVisible, "root_visible")],
            offViewport: [
                Screen.OffViewportEntry(
                    staleRootButton,
                    heistId: "stale_controls_button",
                    scrollContainerPath: TreePath([0])
                )
            ]
        )
        brains.stash.semanticObservationStream.commitSettledDiscoveryObservation(staleRootScreen)

        let currentHeader = makeElement(label: "Controls Demo", traits: .header)
        let currentBackButton = makeElement(label: "ButtonHeist Demo", traits: [.button, .backButton])
        let currentScreen = Screen.makeForTests(elements: [
            (currentHeader, "current_controls_header"),
            (currentBackButton, "current_back_button"),
        ])
        brains.stash.recordParsedObservedEvidence(currentScreen)
        brains.stash.nextVisibleRefreshScreenForTesting = currentScreen

        let discovered = await brains.navigation.elementInflation.discoverTarget?(
            .predicate(ElementPredicate(label: "Controls Demo", traits: [.button]))
        )

        XCTAssertNotNil(discovered?.findElement(heistId: "current_controls_header"))
        XCTAssertNil(discovered?.findElement(heistId: "stale_controls_button"))
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
            guard case .scrollable = container.container.type else { return nil }
            return container.path
        }).first else {
            throw XCTSkip("Parser did not expose the test scroll view as a scroll container")
        }

        let staleRootRow = makeElement(label: "Auto-Settle Fixtures", traits: .button)
        let staleEntry = TheStash.ScreenElement(
            heistId: "stale_auto_settle_fixtures",
            scrollMembership: Screen.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            element: staleRootRow
        )
        let staleScreen = Screen(
            semantic: SemanticScreen(
                elements: [staleEntry.heistId: staleEntry],
                containers: visibleScreen.semantic.containers
            ),
            liveCapture: visibleScreen.liveCapture
        )
        brains.stash.semanticObservationStream.commitSettledDiscoveryObservation(staleScreen)

        let exploration = await brains.navigation.exploreScreen(
            baseline: brains.stash.visibleExplorationBaseline(from: visibleScreen),
            maxScrollsPerContainer: 3,
            maxScrollsPerDiscovery: 3
        )
        _ = brains.stash.commitSettledDiscoveryWorld(exploration.screen)

        let labels = brains.stash.discoveryInterface().projectedElements.compactMap(\.label)
        XCTAssertGreaterThan(exploration.manifest.scrollCount, 0, "Expected discovery to scroll the word list")
        XCTAssertTrue(labels.contains("Words"), "Expected visible word in discovered interface: \(labels)")
        XCTAssertTrue(labels.contains("zymurgy"), "Expected scrolled word in discovered interface: \(labels)")
        XCTAssertFalse(
            labels.contains("Auto-Settle Fixtures"),
            "Stale root rows must not be grafted into the current scroll container: \(labels)"
        )
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
        _ = brains.stash.refreshCurrentVisibleTree()

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Top Target")))
        )

        XCTAssertTrue(result.success, "Expected scroll_to_visible to discover the target above; got \(result)")
        XCTAssertLessThanOrEqual(scrollView.contentOffset.y, 10)
        XCTAssertTrue(brains.stash.liveVisibleScreen.orderedElements.contains {
            $0.element.label == "Top Target"
        })
    }

    func testKnownSemanticRevealIgnoresStaleDetachedScrollView() async {
        let staleScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(visible, HeistId(rawValue: "visible_element"))]
        ))

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Offscreen")))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertEqual(staleScrollView.contentOffset, .zero)
        XCTAssertFalse(
            result.message?.contains("after semantic reveal") ?? false,
            "Detached scroll views should not authorize semantic reveal"
        )
    }

    func testStaleKnownRevealReentersCurrentDiscoveryBeforeFailing() async {
        let staleScrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let staleTarget = makeElement(label: "Target")
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(visible, heistId: "visible_element"),
            offscreen: KnownOffscreenScrollTarget(
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
        let recoveredEntry = TheStash.ScreenElement(
            heistId: "target_button",
            scrollMembership: nil,
            element: recoveredTarget
        )
        let recoveredScreen = Screen(
            elements: [recoveredEntry.heistId: recoveredEntry],
            hierarchy: [.element(recoveredTarget, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): recoveredEntry.heistId],
            elementRefs: [
                recoveredEntry.heistId: .init(object: recoveredObject, scrollView: nil)
            ],
            firstResponderHeistId: nil,
        )
        var discoveryAttempts = 0
        brains.navigation.elementInflation.discoverTarget = { _ in
            discoveryAttempts += 1
            return discoveryAttempts == 1 ? nil : recoveredScreen
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Target")),
            method: .scrollToVisible,
            deallocatedBoundary: "scroll_to_visible dispatch"
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected current discovery to recover stale reveal, got \(result)")
        }
        XCTAssertEqual(discoveryAttempts, 2)
        XCTAssertEqual(staleScrollView.setContentOffsetAnimations, [false])
        XCTAssertEqual(inflatedTarget.screenElement.heistId, recoveredEntry.heistId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, recoveredFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, recoveredFrame.midY, accuracy: 0.01)
    }

    func testKnownTargetWithMissingLiveScrollAncestorRecapturesVisibleActionableTarget() async {
        let staleScrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let knownTarget = makeElement(label: "Coke", traits: .button)
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(visible, heistId: "visible_element"),
            offscreen: KnownOffscreenScrollTarget(
                knownTarget,
                heistId: "known_coke_button",
                contentActivationPoint: CGPoint(x: 160, y: 1_200),
                scrollView: staleScrollView
            ),
            includeLiveScrollAncestor: false,
            scrollContainerPath: TreePath([99])
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
        let recoveredEntry = TheStash.ScreenElement(
            heistId: "current_coke_button",
            scrollMembership: Screen.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            element: recoveredTarget
        )
        let recoveredScreen = Screen(
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
        XCTAssertTrue(recoveredScreen.visibleIds.contains(recoveredEntry.heistId))
        XCTAssertNotNil(recoveredScreen.liveCapture.object(for: recoveredEntry.heistId))
        var revealAttempts = 0
        brains.navigation.elementInflation.revealKnownTarget = { _ in
            revealAttempts += 1
            self.brains.stash.nextVisibleRefreshScreenForTesting = recoveredScreen
            return nil
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Coke", traits: [.button])),
            method: .activate,
            deallocatedBoundary: "activation dispatch"
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected current visible target recovery, got \(result)")
        }
        XCTAssertEqual(revealAttempts, 1)
        XCTAssertEqual(staleScrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(inflatedTarget.screenElement.heistId, recoveredEntry.heistId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, recoveredFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, recoveredFrame.midY, accuracy: 0.01)
        XCTAssertTrue(inflatedTarget.liveTarget.object === recoveredObject)
        XCTAssertNil(brains.stash.liveScrollView(for: inflatedTarget.screenElement))
    }

    func testScrollReturnsReasonInsteadOfRevealingKnownOffscreenTarget() async {
        // Contract: Scroll either reveals the requested target or returns a reason it cannot.
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(visible, heistId: "visible_element"),
            offscreen: KnownOffscreenScrollTarget(
                offscreen,
                heistId: "offscreen_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            )
        )

        let result = await brains.navigation.executeScroll(
            ScrollTarget(elementTarget: .predicate(ElementPredicate(label: "Offscreen")), direction: .down)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scroll)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertEqual(scrollView.contentOffset, .zero)
        XCTAssertTrue(
            result.message?.contains("known but not currently visible") == true,
            "Expected offscreen guidance, got \(String(describing: result.message))"
        )
        XCTAssertTrue(result.message?.contains("scroll_to_visible") == true)
    }

    func testScrollToEdgeReturnsReasonInsteadOfRevealingKnownOffscreenTarget() async {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithKnownOffscreen(
            visible: Screen.TestEntry(visible, heistId: "visible_element"),
            offscreen: KnownOffscreenScrollTarget(
                offscreen,
                heistId: "offscreen_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            )
        )

        let result = await brains.navigation.executeScrollToEdge(
            ScrollToEdgeTarget(elementTarget: .predicate(ElementPredicate(label: "Offscreen")), edge: .bottom)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToEdge)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertEqual(scrollView.contentOffset, .zero)
        XCTAssertTrue(
            result.message?.contains("known but not currently visible") == true,
            "Expected offscreen guidance, got \(String(describing: result.message))"
        )
        XCTAssertTrue(result.message?.contains("scroll_to_visible") == true)
    }

    func testScrollWithoutElementUsesSingleVisibleContainerAndDefaultsDown() async {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        ))

        let result = await brains.navigation.executeScroll(ScrollTarget())

        XCTAssertTrue(result.success, "Expected default scroll to pick the only visible container: \(String(describing: result.message))")
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
    }

    func testScrollToEdgeWithoutElementDefaultsTop() async {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        scrollView.contentOffset.y = 600
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        ))

        let result = await brains.navigation.executeScrollToEdge(ScrollToEdgeTarget())

        XCTAssertTrue(result.success, "Expected default edge scroll to pick the only visible container: \(String(describing: result.message))")
        XCTAssertEqual(scrollView.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollToEdgeAlreadyAtRequestedEdgeSucceeds() async {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        ))

        let result = await brains.navigation.executeScrollToEdge(ScrollToEdgeTarget(edge: .top))

        XCTAssertTrue(result.success, "Expected already-at-edge scroll to be idempotent: \(String(describing: result.message))")
        XCTAssertEqual(scrollView.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollUsesNamedContainer() async {
        let firstScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        firstScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let secondScrollView = UIScrollView(frame: CGRect(x: 0, y: 420, width: 320, height: 400))
        secondScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let firstContainer = makeScrollableContainer(contentSize: firstScrollView.contentSize, frame: firstScrollView.frame)
        let secondContainer = makeScrollableContainer(contentSize: secondScrollView.contentSize, frame: secondScrollView.frame)
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [
                .container(firstContainer, children: []),
                .container(secondContainer, children: []),
            ],
            containerNamesByPath: [
                TreePath([0]): "first_scroll",
                TreePath([1]): "second_scroll",
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                TreePath([0]): .init(view: firstScrollView),
                TreePath([1]): .init(view: secondScrollView),
            ]
        ))

        let result = await brains.navigation.executeScroll(
            ScrollTarget(selection: .container("second_scroll"), direction: .down)
        )

        XCTAssertTrue(result.success, "Expected named container scroll to succeed: \(String(describing: result.message))")
        XCTAssertEqual(firstScrollView.contentOffset.y, 0, accuracy: 0.01)
        XCTAssertGreaterThan(secondScrollView.contentOffset.y, 0)
    }

    func testScrollToEdgeUsesNamedContainer() async {
        let firstScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        firstScrollView.contentSize = CGSize(width: 320, height: 1_600)
        firstScrollView.contentOffset.y = 500
        let secondScrollView = UIScrollView(frame: CGRect(x: 0, y: 420, width: 320, height: 400))
        secondScrollView.contentSize = CGSize(width: 320, height: 1_600)
        secondScrollView.contentOffset.y = 500
        let firstContainer = makeScrollableContainer(contentSize: firstScrollView.contentSize, frame: firstScrollView.frame)
        let secondContainer = makeScrollableContainer(contentSize: secondScrollView.contentSize, frame: secondScrollView.frame)
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [
                .container(firstContainer, children: []),
                .container(secondContainer, children: []),
            ],
            containerNamesByPath: [
                TreePath([0]): "first_scroll",
                TreePath([1]): "second_scroll",
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                TreePath([0]): .init(view: firstScrollView),
                TreePath([1]): .init(view: secondScrollView),
            ]
        ))

        let result = await brains.navigation.executeScrollToEdge(
            ScrollToEdgeTarget(selection: .container("second_scroll"), edge: .top)
        )

        XCTAssertTrue(result.success, "Expected named container edge scroll to succeed: \(String(describing: result.message))")
        XCTAssertEqual(firstScrollView.contentOffset.y, 500, accuracy: 0.01)
        XCTAssertEqual(secondScrollView.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollUsesPathKeyedContainerWhenRepeatedSameSizedScrollViews() async {
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

        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [
                .container(repeatedContainer, children: []),
                .container(repeatedContainer, children: []),
            ],
            containerNamesByPath: [
                firstPath: "first_repeated_scroll",
                secondPath: "second_repeated_scroll",
            ],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [
                firstPath: .init(view: firstScrollView),
                secondPath: .init(view: secondScrollView),
            ]
        ))

        let result = await brains.navigation.executeScroll(
            ScrollTarget(selection: .container("second_repeated_scroll"), direction: .down)
        )

        XCTAssertTrue(result.success, "Expected path-keyed named container scroll to succeed: \(String(describing: result.message))")
        XCTAssertEqual(firstScrollView.contentOffset.y, 0, accuracy: 0.01)
        XCTAssertGreaterThan(secondScrollView.contentOffset.y, 0)
    }

    func testScrollWithoutElementReportsAmbiguousContainers() async {
        let firstContainer = makeScrollableContainer()
        let secondContainer = makeScrollableContainer(frame: CGRect(x: 0, y: 420, width: 320, height: 400))
        installScrollableContainers([firstContainer, secondContainer])
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [
                .container(firstContainer, children: []),
                .container(secondContainer, children: []),
            ],
            containerNamesByPath: [
                TreePath([0]): "first_scroll",
                TreePath([1]): "second_scroll",
            ],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScroll(ScrollTarget())

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message?.contains("ambiguous") == true)
        XCTAssertTrue(result.message?.contains("target an element inside the intended scroll region") == true)
        XCTAssertFalse(result.message?.contains("first_scroll") == true)
        XCTAssertFalse(result.message?.contains("second_scroll") == true)
    }

    func testScrollToVisibleVisibleAmbiguousMatcherFailsClosed() async {
        let first = makeElement(label: "Duplicate", traits: .button)
        let second = makeElement(label: "Duplicate", traits: .button)
        let firstEntry = Screen.ScreenElement(
            heistId: "duplicate_1",
            scrollMembership: nil,
            element: first
        )
        let secondEntry = Screen.ScreenElement(
            heistId: "duplicate_2",
            scrollMembership: nil,
            element: second
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [
                firstEntry.heistId: firstEntry,
                secondEntry.heistId: secondEntry,
            ],
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Duplicate")))
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
            ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Save"), ordinal: 3))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("ordinal 3 requested") ?? false,
            "Expected ordinal diagnostic, got \(String(describing: result.message))"
        )
    }

    func testScrollToVisiblePostSemanticRevealAmbiguousLiveTargetFailsClosed() async throws {
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
        if !brains.stash.matchScreenElements(ElementPredicate(label: "Jump Target"), limit: 1).isEmpty {
            throw XCTSkip("Parser exposed offscreen scroll content before semantic reveal")
        }

        let knownElement = makeElement(
            label: "Jump Target",
            traits: .button,
            shape: .frame(AccessibilityRect(firstTarget.frame))
        )
        let knownEntry = TheStash.ScreenElement(
            heistId: "known_reveal_target",
            scrollMembership: Screen.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: observedContentActivationPoint(CGPoint(
                x: firstTarget.frame.midX,
                y: firstTarget.frame.midY
            )),
            element: knownElement
        )
        let knownScreen = Screen(
            semantic: SemanticScreen(
                elements: [knownEntry.heistId: knownEntry],
                containers: liveScreen.semantic.containers
            ),
            liveCapture: liveScreen.liveCapture
        )
        brains.stash.installScreenForTesting(knownScreen)
        brains.navigation.elementInflation.discoverTarget = nil

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Jump Target")),
            method: .scrollToVisible,
            deallocatedBoundary: "scroll_to_visible dispatch"
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected post-reveal ambiguity failure, got \(result)")
        }
        XCTAssertTrue(
            failure.message.contains("element inflation failed [ambiguous]"),
            "Expected classified post-reveal ambiguity diagnostic, got \(failure.message)"
        )
        XCTAssertTrue(
            failure.message.contains("2 elements match"),
            "Expected post-reveal ambiguity diagnostic, got \(failure.message)"
        )
    }

    // MARK: - Element Scroll Target Resolution

    func testScrollWithVisibleElementReportsMissingScrollableAncestor() async {
        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [screenElement.heistId: screenElement],
            hierarchy: [.element(screenElement.element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): screenElement.heistId],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScroll(
            ScrollTarget(elementTarget: .predicate(ElementPredicate(label: "Item")), direction: .down)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(
            result.message,
            "scroll target failed: observed \"Item\" with no live scrollable ancestor; "
                + "target an element inside the intended scroll region"
        )
    }

    func testScrollWithVisibleElementReportsAxisMismatch() async {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 200)

        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        installLiveScrollTarget(screenElement, scrollView: scrollView, containerName: "axis_scroll")

        let result = await brains.navigation.executeScroll(
            ScrollTarget(elementTarget: .predicate(ElementPredicate(label: "Item")), direction: .down)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(
            result.message,
            "scroll target failed: observed \"Item\" inside a scroll view that supports no scrolling; "
                + "expected vertical scrolling; try a matching scroll direction or target an element "
                + "inside the intended scroll region"
        )
    }

    func testScrollWithVisibleElementUsesElementScrollViewWhenAxisMatches() async {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 1200)

        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        installLiveScrollTarget(screenElement, scrollView: scrollView, containerName: "vertical_scroll")

        let result = await brains.navigation.executeScroll(
            ScrollTarget(elementTarget: .predicate(ElementPredicate(label: "Item")), direction: .down)
        )

        XCTAssertTrue(result.success, "Expected element scroll to succeed: \(String(describing: result.message))")
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
    }

    // MARK: - SettleSwipeLoopState (Pure Decision Logic)

    func testSettleLoopSameDirectionExitsAfterOneStableFrame() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .sameDirection,
            previousVisibleIds: ["a"]
        )
        let step1 = state.advance(
            visibleIds: ["b"],
            newHeistIds: []
        )
        XCTAssertEqual(step1, .continue, "Viewport change resets stable counter")
        XCTAssertTrue(state.moved, "Visible-id set differs, motion detected")

        let step2 = state.advance(
            visibleIds: ["b"],
            newHeistIds: []
        )
        XCTAssertEqual(step2, .done, "Same-direction profile exits once stable visible count hits 1")
        XCTAssertTrue(state.moved)
    }

    func testSettleLoopDirectionChangeHonorsMinFrames() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"]
        )
        for frameIndex in 0..<5 {
            let step = state.advance(
                visibleIds: ["a"],
                newHeistIds: []
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) must not exit before minFrames=6")
        }
        let finalStep = state.advance(
            visibleIds: ["a"],
            newHeistIds: []
        )
        XCTAssertEqual(finalStep, .done, "Direction-change profile exits at frame 6")
        XCTAssertEqual(state.frame, 6)
    }

    func testSettleLoopExitsAtMaxFramesWhenConditionsNeverSettle() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"]
        )
        for frameIndex in 0..<23 {
            let heistId = HeistId(rawValue: "id-\(frameIndex)")
            let step = state.advance(
                visibleIds: [heistId],
                newHeistIds: [heistId]
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) churns, should continue")
        }
        let finalStep = state.advance(
            visibleIds: [HeistId(rawValue: "id-final")],
            newHeistIds: [HeistId(rawValue: "id-final")]
        )
        XCTAssertEqual(finalStep, .done, "Must exit at maxFrames=24 even if never settles")
        XCTAssertEqual(state.frame, 24)
    }

    func testSettleLoopMovedLatchesAndNeverClears() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"]
        )
        XCTAssertFalse(state.moved)

        _ = state.advance(
            visibleIds: ["b"],
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Visible-id changes flag motion")

        _ = state.advance(
            visibleIds: ["a"],
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "moved only latches true, never clears back to false")
    }

    func testSettleLoopUsesViewportDiffAsMotionSignal() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"]
        )
        _ = state.advance(
            visibleIds: ["b"],
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Viewport set difference signals motion")
    }

    func testSwipeTargetKeyEquatesSameCoarseGeometry() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        let contentSize = CGSize(width: 300, height: 1_200)

        let lhs = brains.navigation.swipeTargetKey(frame: frame, contentSize: contentSize)
        let rhs = brains.navigation.swipeTargetKey(frame: frame, contentSize: contentSize)

        XCTAssertEqual(lhs, rhs)
    }

    func testSwipeTargetKeyDistinguishesDifferentCoarseGeometry() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        let contentSize = CGSize(width: 300, height: 1_200)

        let lhs = brains.navigation.swipeTargetKey(frame: frame, contentSize: contentSize)
        let rhs = brains.navigation.swipeTargetKey(
            frame: frame.offsetBy(dx: 0, dy: 1),
            contentSize: contentSize
        )

        XCTAssertNotEqual(lhs, rhs)
    }

    func testSwipeDirectionCacheUsesEquivalentTypedKeyForDirectionChangeLookup() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        let contentSize = CGSize(width: 300, height: 1_200)
        let originalKey = brains.navigation.swipeTargetKey(frame: frame, contentSize: contentSize)
        let lookupKey = brains.navigation.swipeTargetKey(frame: frame, contentSize: contentSize)

        brains.navigation.lastSwipeDirectionByTarget[originalKey] = .down

        let changesToUp = brains.navigation.lastSwipeDirectionByTarget[lookupKey].map { $0 != .up } ?? false
        let changesToDown = brains.navigation.lastSwipeDirectionByTarget[lookupKey].map { $0 != .down } ?? false
        XCTAssertTrue(changesToUp)
        XCTAssertFalse(changesToDown)
    }

    // MARK: - safeSwipeFrame

    func testScrollableTargetUsesAccessibilityContainerFrameForSemanticOnlySwipeFallback() throws {
        let captureFrame = CGRect(x: 40, y: 120, width: 240, height: 360)
        let contentSize = AccessibilitySize(width: 320, height: 2000)
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: contentSize),
            frame: AccessibilityRect(captureFrame)
        )
        let path = TreePath([0])
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            firstResponderHeistId: nil
        ))

        let target = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        guard case .swipeable(let frame, let resolvedContentSize) = target else {
            XCTFail("Expected semantic-only scroll container to use swipeable accessibility geometry")
            return
        }
        XCTAssertEqual(frame, captureFrame)
        XCTAssertEqual(resolvedContentSize, contentSize.cgSize)
    }

    func testScrollableTargetUsesPathKeyedLiveScrollView() throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let contentSize = AccessibilitySize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        let path = TreePath([0])
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [path: "main_scroll"],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: scrollView)]
        ))

        let target = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        guard case .uiScrollView(let resolvedScrollView) = target else {
            XCTFail("Expected path-keyed UIScrollView target, got \(target)")
            return
        }
        XCTAssertTrue(resolvedScrollView === scrollView)
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
        brains.stash.installScreenForTesting(Screen(
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

    // MARK: - Clear Cache

    func testClearCacheClearsLastSwipeDirectionCache() {
        let key = brains.navigation.swipeTargetKey(
            frame: CGRect(x: 10, y: 20, width: 300, height: 400),
            contentSize: CGSize(width: 300, height: 1_200)
        )
        brains.navigation.lastSwipeDirectionByTarget[key] = .down
        XCTAssertFalse(brains.navigation.lastSwipeDirectionByTarget.isEmpty)
        brains.clearCache()
        XCTAssertTrue(
            brains.navigation.lastSwipeDirectionByTarget.isEmpty,
            "clearCache must drop the swipe direction cache so a new session starts fresh"
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

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 320, height: 2000),
        frame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 400)
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(contentSize)),
            frame: AccessibilityRect(frame)
        )
    }

    private func installScrollableContainers(_ containers: [AccessibilityContainer]) {
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: containers.map { .container($0, children: []) },
            firstResponderHeistId: nil,
        ))
    }

    private func installLiveScrollTarget(
        _ screenElement: TheStash.ScreenElement,
        scrollView: UIScrollView,
        containerName: ContainerName
    ) {
        let container = makeScrollableContainer(
            contentSize: scrollView.contentSize,
            frame: scrollView.frame
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [screenElement.heistId: screenElement],
            hierarchy: [
                .container(container, children: [
                    .element(screenElement.element, traversalIndex: 0)
                ])
            ],
            containerNamesByPath: [TreePath([0]): containerName],
            heistIdsByPath: [TreePath([0, 0]): screenElement.heistId],
            elementRefs: [
                screenElement.heistId: .init(object: nil, scrollView: scrollView)
            ],
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

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
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

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            setContentOffsetAnimations.append(animated)
            super.setContentOffset(contentOffset, animated: animated)
        }
    }
}

#endif
