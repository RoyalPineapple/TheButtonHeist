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
        try await super.tearDown()
    }

    // MARK: - Programmatic Scroll Safety

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

        let unsafeTargets = brains.stash.scrollableContainerViews.compactMap { entry -> UIScrollView? in
            let (_, view) = entry
            guard let scrollView = view as? UIScrollView,
                  scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
            return scrollView
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

    func testScrollTargetOffsetCentersOnOrigin() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        scrollView.contentInset = .zero

        let origin = CGPoint(x: 100, y: 2500)
        let offset = ElementInflation.semanticRevealTargetOffset(for: origin, in: scrollView)

        XCTAssertEqual(offset.x, max(origin.x - 375.0 / 2, 0), accuracy: 0.01,
                       "X offset should center on origin horizontally")
        XCTAssertEqual(offset.y, origin.y - 667.0 / 2, accuracy: 0.01,
                       "Y offset should center on origin vertically")
    }

    func testScrollTargetOffsetClampsToTop() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)

        let origin = CGPoint(x: 100, y: 100)
        let offset = ElementInflation.semanticRevealTargetOffset(for: origin, in: scrollView)

        XCTAssertGreaterThanOrEqual(offset.y, 0,
                                    "Offset should not go above content start")
    }

    func testScrollTargetOffsetClampsToBottom() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)

        let origin = CGPoint(x: 100, y: 4900)
        let offset = ElementInflation.semanticRevealTargetOffset(for: origin, in: scrollView)

        let maxY = scrollView.contentSize.height - scrollView.bounds.height
        XCTAssertLessThanOrEqual(offset.y, maxY + 0.01,
                                 "Offset should not exceed maximum scrollable Y")
    }

    func testScrollTargetOffsetRespectsContentInsets() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        scrollView.contentInset = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)

        let origin = CGPoint(x: 100, y: 10)
        let offset = ElementInflation.semanticRevealTargetOffset(for: origin, in: scrollView)

        let minY = -scrollView.adjustedContentInset.top
        XCTAssertGreaterThanOrEqual(offset.y, minY,
                                    "Offset should respect top content inset")
    }

    func testScrollTargetOffsetCentersWithinAdjustedVisibleRect() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        scrollView.contentSize = CGSize(width: 3000, height: 5000)
        scrollView.contentInset = UIEdgeInsets(top: 100, left: 20, bottom: 50, right: 60)

        let origin = CGPoint(x: 1000, y: 1800)
        let offset = ElementInflation.semanticRevealTargetOffset(for: origin, in: scrollView)

        let insets = scrollView.adjustedContentInset
        let visibleWidth = scrollView.bounds.width - insets.left - insets.right
        let visibleHeight = scrollView.bounds.height - insets.top - insets.bottom
        XCTAssertEqual(offset.x + insets.left + visibleWidth / 2, origin.x, accuracy: 0.01)
        XCTAssertEqual(offset.y + insets.top + visibleHeight / 2, origin.y, accuracy: 0.01)
    }

    func testScrollTargetOffsetHorizontalClamping() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 2000, height: 667)

        let originNearStart = CGPoint(x: 50, y: 300)
        let offsetStart = ElementInflation.semanticRevealTargetOffset(for: originNearStart, in: scrollView)
        XCTAssertGreaterThanOrEqual(offsetStart.x, 0, "Should clamp to left edge")

        let originNearEnd = CGPoint(x: 1950, y: 300)
        let offsetEnd = ElementInflation.semanticRevealTargetOffset(for: originNearEnd, in: scrollView)
        let maxX = scrollView.contentSize.width - scrollView.bounds.width
        XCTAssertLessThanOrEqual(offsetEnd.x, maxX + 0.01, "Should clamp to right edge")
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
            contentSpaceOrigin: nil,
            element: AccessibilityElement.make(label: "Labeled", identifier: "labeled_id")
        )
        let identified = TheStash.ScreenElement(
            heistId: "identified_item",
            contentSpaceOrigin: nil,
            element: AccessibilityElement.make(identifier: "identified_id")
        )
        let anonymous = TheStash.ScreenElement(
            heistId: "anonymous_item",
            contentSpaceOrigin: nil,
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

    // MARK: - Known Offscreen Entry

    /// Install a Screen whose `elements` includes an entry that's not in the
    /// live hierarchy — simulating an element retained from a previous
    /// exploration commit that has since scrolled off.
    private func makeScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, String)],
        offViewport: [(AccessibilityElement, String, CGPoint?)]
    ) -> Screen {
        .makeForTests(
            elements: liveHierarchy.map { ($0.0, $0.1) },
            offViewport: offViewport.map {
                Screen.OffViewportEntry($0.0, heistId: $0.1, contentSpaceOrigin: $0.2)
            }
        )
    }

    private func installScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, String)],
        offViewport: [(AccessibilityElement, String, CGPoint?)]
    ) {
        brains.stash.installScreenForTesting(makeScreenWithOffViewportEntry(
            liveHierarchy: liveHierarchy,
            offViewport: offViewport
        ))
    }

    private func installScreenWithKnownOffscreen(
        visible: (AccessibilityElement, String),
        offscreen: (AccessibilityElement, String, CGPoint, UIScrollView),
        includeLiveScrollAncestor: Bool = true
    ) {
        let visibleEntry = Screen.ScreenElement(
            heistId: visible.1,
            contentSpaceOrigin: nil,
            element: visible.0
        )
        let scrollContainer = makeScrollableContainer(
            contentSize: offscreen.3.contentSize,
            frame: offscreen.3.frame
        )
        let scrollContainerName = "known_offscreen_scroll"
        let offscreenEntry = Screen.ScreenElement(
            heistId: offscreen.1,
            contentSpaceOrigin: offscreen.2,
            scrollContainerName: scrollContainerName,
            element: offscreen.0
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [
                visibleEntry.heistId: visibleEntry,
                offscreenEntry.heistId: offscreenEntry,
            ],
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(visible.0, traversalIndex: 0)
                ])
            ],
            containerNames: [scrollContainer: scrollContainerName],
            heistIdByElement: [visible.0: visible.1],
            elementRefs: includeLiveScrollAncestor ? [
                offscreenEntry.heistId: .init(object: nil, scrollView: offscreen.3)
            ] : [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: includeLiveScrollAncestor
                ? [scrollContainer: .init(view: offscreen.3)]
                : [:]
        ))
    }

    func testSemanticRevealNoOpsWhenAlreadyVisible() async {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visibleEntry = Screen.ScreenElement(
            heistId: "visible_element",
            contentSpaceOrigin: CGPoint(x: 0, y: 120),
            scrollContainerName: "visible_scroll",
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
        let scrollContainerName = "reused_cell_scroll"
        let target = makeElement(label: "Controls Demo", traits: .button)
        let currentlyVisibleReuse = makeElement(label: "Custom Rotors", traits: .button)
        let entry = Screen.ScreenElement(
            heistId: "reused_cell",
            contentSpaceOrigin: CGPoint(x: 0, y: 20),
            scrollContainerName: scrollContainerName,
            element: target
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [
                .container(container, children: [
                    .element(currentlyVisibleReuse, traversalIndex: 0)
                ])
            ],
            containerNames: [container: scrollContainerName],
            heistIdByElement: [currentlyVisibleReuse: entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: nil, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [
                container: .init(view: scrollView)
            ]
        ))

        let result = await brains.navigation.elementInflation.revealSemanticTarget(entry)

        guard case .revealed(let resolvedScrollView) = result else {
            return XCTFail("Expected reused visible id to trigger semantic reveal, got \(result)")
        }
        XCTAssertTrue(resolvedScrollView === scrollView)
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [false])
        XCTAssertLessThan(scrollView.contentOffset.y, 100)
    }

    func testSemanticRevealUsesNonAnimatedJumpForKnownOffscreenElement() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Settings")
        let contentOrigin = CGPoint(x: 0, y: 1_200)
        installScreenWithKnownOffscreen(
            visible: (visible, "visible_element"),
            offscreen: (offscreen, "settings_button", contentOrigin, scrollView)
        )

        let entry = try XCTUnwrap(
            brains.stash.settledSemanticScreen.findElement(heistId: "settings_button")
        )
        let result = await brains.navigation.elementInflation.revealSemanticTarget(entry)

        guard case .revealed(let resolvedScrollView) = result else {
            return XCTFail("Expected semantic reveal to resolve, got \(result)")
        }
        XCTAssertTrue(resolvedScrollView === scrollView)
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [false])
        let expectedOffset = ElementInflation.semanticRevealTargetOffset(for: contentOrigin, in: scrollView)
        XCTAssertEqual(scrollView.contentOffset.x, expectedOffset.x, accuracy: 0.01)
        XCTAssertEqual(scrollView.contentOffset.y, expectedOffset.y, accuracy: 0.01)
    }

    func testSemanticRevealFailsWithoutProvenLiveScrollAncestor() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Settings")
        installScreenWithKnownOffscreen(
            visible: (visible, "visible_element"),
            offscreen: (offscreen, "settings_button", CGPoint(x: 0, y: 1_200), scrollView),
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
            elements: [(visible, "visible_element")]
        ))

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Missing Button")))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
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
            offViewport: [(offscreen, "offscreen_button", nil)]
        )

        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Offscreen")),
            method: .activate,
            deallocatedBoundary: "test inflation"
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected element inflation failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.noRevealPath)
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
        XCTAssertTrue(failure.message.contains("has no content-space position"))
    }

    func testKnownOffscreenTargetWithoutLiveScrollParentFailsNoRevealPath() async {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithKnownOffscreen(
            visible: (visible, "visible_element"),
            offscreen: (offscreen, "offscreen_button", CGPoint(x: 0, y: 1_200), scrollView),
            includeLiveScrollAncestor: false
        )
        let result = await brains.navigation.elementInflation.inflate(
            for: .predicate(ElementPredicate(label: "Offscreen")),
            method: .scrollToVisible,
            deallocatedBoundary: "scroll_to_visible dispatch"
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected no-reveal-path inflation failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.noRevealPath)
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
            contentSpaceOrigin: nil,
            element: element
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            containerNames: [:],
            heistIdByElement: [element: entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
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
            contentSpaceOrigin: nil,
            element: element
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            containerNames: [:],
            heistIdByElement: [element: entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
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
            offViewport: [(offscreen, "offscreen_button", nil)]
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
            visible: (staleVisible, "old_visible"),
            offscreen: (staleOffscreen, "old_offscreen", CGPoint(x: 0, y: 1_200), staleScrollView)
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
            visible: (staleVisible, "root_visible"),
            offscreen: (staleRootButton, "stale_controls_button", CGPoint(x: 0, y: 1_200), staleScrollView)
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

    func testKnownSemanticRevealIgnoresStaleDetachedScrollView() async {
        let staleScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(visible, "visible_element")]
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
            visible: (visible, "visible_element"),
            offscreen: (staleTarget, "target_button", CGPoint(x: 0, y: 1_200), staleScrollView)
        )

        let recoveredFrame = CGRect(x: 40, y: 160, width: 240, height: 44)
        let recoveredTarget = AccessibilityElement.make(
            label: "Target",
            traits: .button,
            frame: recoveredFrame
        )
        let recoveredObject = NSObject()
        let recoveredEntry = TheStash.ScreenElement(
            heistId: "target_button",
            contentSpaceOrigin: nil,
            element: recoveredTarget
        )
        let recoveredScreen = Screen(
            elements: [recoveredEntry.heistId: recoveredEntry],
            hierarchy: [.element(recoveredTarget, traversalIndex: 0)],
            containerNames: [:],
            heistIdByElement: [recoveredTarget: recoveredEntry.heistId],
            elementRefs: [
                recoveredEntry.heistId: .init(object: recoveredObject, scrollView: nil)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
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

    func testScrollReturnsReasonInsteadOfRevealingKnownOffscreenTarget() async {
        // Contract: Scroll either reveals the requested target or returns a reason it cannot.
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithKnownOffscreen(
            visible: (visible, "visible_element"),
            offscreen: (offscreen, "offscreen_button", CGPoint(x: 0, y: 1_200), scrollView)
        )

        let result = await brains.navigation.executeScroll(
            ScrollTarget(elementTarget: .predicate(ElementPredicate(label: "Offscreen")), direction: .down)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scroll)
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
            visible: (visible, "visible_element"),
            offscreen: (offscreen, "offscreen_button", CGPoint(x: 0, y: 1_200), scrollView)
        )

        let result = await brains.navigation.executeScrollToEdge(
            ScrollToEdgeTarget(elementTarget: .predicate(ElementPredicate(label: "Offscreen")), edge: .bottom)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToEdge)
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
            containerNames: [container: "main_scroll"],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [container: .init(view: scrollView)]
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
            containerNames: [container: "main_scroll"],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [container: .init(view: scrollView)]
        ))

        let result = await brains.navigation.executeScrollToEdge(ScrollToEdgeTarget())

        XCTAssertTrue(result.success, "Expected default edge scroll to pick the only visible container: \(String(describing: result.message))")
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
            containerNames: [
                firstContainer: "first_scroll",
                secondContainer: "second_scroll",
            ],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [
                firstContainer: .init(view: firstScrollView),
                secondContainer: .init(view: secondScrollView),
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
            containerNames: [
                firstContainer: "first_scroll",
                secondContainer: "second_scroll",
            ],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [
                firstContainer: .init(view: firstScrollView),
                secondContainer: .init(view: secondScrollView),
            ]
        ))

        let result = await brains.navigation.executeScrollToEdge(
            ScrollToEdgeTarget(selection: .container("second_scroll"), edge: .top)
        )

        XCTAssertTrue(result.success, "Expected named container edge scroll to succeed: \(String(describing: result.message))")
        XCTAssertEqual(firstScrollView.contentOffset.y, 500, accuracy: 0.01)
        XCTAssertEqual(secondScrollView.contentOffset.y, 0, accuracy: 0.01)
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
            containerNames: [
                firstContainer: "first_scroll",
                secondContainer: "second_scroll",
            ],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
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
            contentSpaceOrigin: nil,
            element: first
        )
        let secondEntry = Screen.ScreenElement(
            heistId: "duplicate_2",
            contentSpaceOrigin: nil,
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
            scrollableContainerViews: [:]
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
        guard brains.stash.refreshLiveCapture() != nil else {
            throw XCTSkip("No live hierarchy available for scroll_to_visible post-reveal regression test")
        }
        if !brains.stash.matchScreenElements(ElementPredicate(label: "Jump Target"), limit: 1).isEmpty {
            throw XCTSkip("Parser exposed offscreen scroll content before semantic reveal")
        }

        let knownElement = makeElement(label: "Jump Target", traits: .button)
        let knownEntry = TheStash.ScreenElement(
            heistId: "known_reveal_target",
            contentSpaceOrigin: CGPoint(x: 40, y: 900),
            scrollContainerName: "known_scroll",
            element: knownElement
        )
        let scrollContainer = makeScrollableContainer(
            contentSize: scrollView.contentSize,
            frame: scrollView.frame
        )
        let knownScreen = Screen(
            elements: [knownEntry.heistId: knownEntry],
            hierarchy: [.container(scrollContainer, children: [])],
            containerNames: [scrollContainer: "known_scroll"],
            heistIdByElement: [:],
            elementRefs: [
                knownEntry.heistId: .init(object: nil, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [
                scrollContainer: .init(view: scrollView)
            ]
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
            contentSpaceOrigin: nil,
            element: makeElement(label: "Item")
        )
        brains.stash.installScreenForTesting(Screen(
            elements: [screenElement.heistId: screenElement],
            hierarchy: [.element(screenElement.element, traversalIndex: 0)],
            containerNames: [:],
            heistIdByElement: [screenElement.element: screenElement.heistId],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
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
            contentSpaceOrigin: nil,
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
            contentSpaceOrigin: nil,
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
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        let step1 = state.advance(
            visibleIds: ["b"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertEqual(step1, .continue, "Viewport change resets stable counter")
        XCTAssertTrue(state.moved, "Anchor differs, motion detected")

        let step2 = state.advance(
            visibleIds: ["b"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertEqual(step2, .done, "Same-direction profile exits once stable visible count hits 1")
        XCTAssertTrue(state.moved)
    }

    func testSettleLoopDirectionChangeHonorsMinFrames() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        for frameIndex in 0..<5 {
            let step = state.advance(
                visibleIds: ["a"],
                anchorSignature: 100,
                newHeistIds: []
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) must not exit before minFrames=6")
        }
        let finalStep = state.advance(
            visibleIds: ["a"],
            anchorSignature: 100,
            newHeistIds: []
        )
        XCTAssertEqual(finalStep, .done, "Direction-change profile exits at frame 6")
        XCTAssertEqual(state.frame, 6)
    }

    func testSettleLoopExitsAtMaxFramesWhenConditionsNeverSettle() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        for frameIndex in 0..<23 {
            let step = state.advance(
                visibleIds: ["id-\(frameIndex)"],
                anchorSignature: 200 + frameIndex,
                newHeistIds: ["id-\(frameIndex)"]
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) churns, should continue")
        }
        let finalStep = state.advance(
            visibleIds: ["id-final"],
            anchorSignature: 999,
            newHeistIds: ["id-final"]
        )
        XCTAssertEqual(finalStep, .done, "Must exit at maxFrames=24 even if never settles")
        XCTAssertEqual(state.frame, 24)
    }

    func testSettleLoopMovedLatchesAndNeverClears() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        XCTAssertFalse(state.moved)

        _ = state.advance(
            visibleIds: ["a"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Differing anchor flags motion")

        _ = state.advance(
            visibleIds: ["a"],
            anchorSignature: 100,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "moved only latches true, never clears back to false")
    }

    func testSettleLoopFallsBackToViewportDiffWhenAnchorsUnavailable() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: nil
        )
        _ = state.advance(
            visibleIds: ["b"],
            anchorSignature: nil,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Without anchors, viewport set difference signals motion")
    }

    func testSettleLoopEdgeBounceDoesNotReportMotion() {
        // Regression guard for the claim that visibleAnchorSignature
        // filters out edge-bounce false positives. When content-space
        // anchors are unchanged across frames, viewport id shuffles
        // (element reorder, reparse flicker) must NOT count as motion.
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a", "b"],
            previousAnchor: 500
        )
        _ = state.advance(
            visibleIds: ["a", "c"],
            anchorSignature: 500,
            newHeistIds: ["c"]
        )
        XCTAssertFalse(
            state.moved,
            "Matching anchor must suppress viewport-set differences as motion signal"
        )
    }

    // MARK: - safeSwipeFrame

    func testScrollableTargetUsesAccessibilityContainerFrameWhenBackingViewFrameDiffers() throws {
        let windowScene = try requireForegroundWindowScene()
        let captureFrame = CGRect(x: 40, y: 120, width: 240, height: 360)
        let backingViewFrame = CGRect(x: 12, y: 520, width: 80, height: 90)
        let contentSize = AccessibilitySize(width: 320, height: 2000)
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: contentSize),
            frame: AccessibilityRect(captureFrame)
        )
        let backingView = UIView(frame: backingViewFrame)
        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.addSubview(backingView)
        window.isHidden = false
        defer {
            window.isHidden = true
        }
        brains.stash.installScreenForTesting(Screen(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            firstResponderHeistId: nil,
            scrollableContainerViews: [container: .init(view: backingView)]
        ))

        let target = try XCTUnwrap(brains.navigation.scrollableTarget(for: container, contentSize: contentSize))

        guard case .swipeable(let frame, let resolvedContentSize) = target else {
            XCTFail("Expected non-UIScrollView container to use swipeable accessibility geometry")
            return
        }
        XCTAssertEqual(frame, captureFrame)
        XCTAssertEqual(resolvedContentSize, contentSize.cgSize)
        XCTAssertNotEqual(frame, backingViewFrame)
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
            containerNames: [:],
            containerNamesByPath: [path: "main_scroll"],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:],
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
            scrollableContainerViews: [:]
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
        brains.navigation.lastSwipeDirectionByTarget["key"] = .down
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
            scrollableContainerViews: [:]
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
            hierarchy: [.element(screenElement.element, traversalIndex: 0)],
            containerNames: [container: containerName],
            heistIdByElement: [screenElement.element: screenElement.heistId],
            elementRefs: [
                screenElement.heistId: .init(object: nil, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [
                container: .init(view: scrollView)
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

    private final class AccessibilityRevealingScrollView: UIScrollView {
        var revealedElements: [UIView] = []
        private let revealThreshold: CGFloat = 500

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
            let isRevealed = (offset ?? contentOffset).y >= revealThreshold
            for element in revealedElements {
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
