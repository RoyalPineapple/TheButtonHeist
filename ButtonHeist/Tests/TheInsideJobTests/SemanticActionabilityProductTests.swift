#if canImport(UIKit)
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticActionabilityProductTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains = nil
        try await super.tearDown()
    }

    func testSemanticActivateRevealsOffscreenScrollTargetWithoutManualPreScroll() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "semantic_checkout_submit",
            label: "Submit Order"
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(fixture)

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)

        let result = await brains.executeCommand(.activate(
            .matcher(ElementMatcher(identifier: "semantic_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(result.success, result.message ?? "semantic activate failed")
        guard result.success else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertGreaterThan(fixture.scrollView.contentOffset.y, 0)
    }

    func testSemanticActivateRevealsNestedContainerTarget() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "nested_semantic_checkout_submit",
            label: "Confirm Payment",
            nestedInGroup: true
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(fixture)

        let result = await brains.executeCommand(.activate(
            .matcher(ElementMatcher(identifier: "nested_semantic_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(result.success, result.message ?? "nested semantic activate failed")
        guard result.success else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertGreaterThan(fixture.scrollView.contentOffset.y, 0)
    }

    func testAmbiguousSemanticActivateFailsBeforeGeometryOrAction() async throws {
        let fixture = try installAmbiguousActivationFixture()
        defer { fixture.cleanup() }

        let result = await brains.executeCommand(.activate(
            .matcher(ElementMatcher(label: "Duplicate", traits: [.button]))
        ))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementNotFound)
        XCTAssertEqual(fixture.first.activationCount, 0)
        XCTAssertEqual(fixture.second.activationCount, 0)
        XCTAssertDiagnostic(result.message, contains: [
            "2 elements match",
            "use ordinal",
        ])
    }

    func testMissingRevealPathFailsAsActionabilityDiagnostic() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "unrevealable_submit",
            label: "Submit Order"
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(
            fixture,
            includeScrollView: false,
            scrollContainerOverride: "missing_scroll"
        )

        let result = await brains.executeCommand(.activate(
            .matcher(ElementMatcher(identifier: "unrevealable_submit", traits: [.button]))
        ))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertDiagnostic(result.message, contains: [
            "semantic actionability failed [noRevealPath]",
            "no live scrollable ancestor",
        ])
        XCTAssertFalse(result.message?.localizedCaseInsensitiveContains("scroll first") ?? false)
        XCTAssertFalse(result.message?.contains("get_interface") ?? false)
        XCTAssertFalse(result.message?.contains("element_search") ?? false)
    }

    func testBatchSemanticActivateMatchesSingleActionResultSemantics() async throws {
        let single = try await runSemanticActivateThroughCommand(
            identifier: "single_semantic_batch_parity",
            label: "Batch Parity Single",
            batch: false
        )
        let batch = try await runSemanticActivateThroughCommand(
            identifier: "batch_semantic_batch_parity",
            label: "Batch Parity Batch",
            batch: true
        )
        let batchPayload = try XCTUnwrap(batch.result.batchExecutionPayload)
        let stepResult = try XCTUnwrap(batchPayload.steps.first?.actionResult)

        XCTAssertTrue(single.result.success, single.result.message ?? "single activate failed")
        XCTAssertTrue(batch.result.success, batch.result.message ?? "batch activate failed")
        guard single.result.success, batch.result.success else { return }
        XCTAssertEqual(single.activationCount, 1)
        XCTAssertEqual(batch.activationCount, 1)
        XCTAssertEqual(stepResult.success, single.result.success)
        XCTAssertEqual(stepResult.method, single.result.method)
        XCTAssertEqual(stepResult.errorKind, single.result.errorKind)
    }

    func testExplicitViewportScrollCommandReportsViewportState() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "explicit_scroll_revealed",
            label: "Explicit Scroll Revealed"
        )
        defer { fixture.cleanup() }
        let initialScreen = try XCTUnwrap(brains.refresh())
        let stableId = try XCTUnwrap(firstScrollableStableId(in: initialScreen))

        let result = await brains.executeCommand(.scroll(ScrollTarget(
            containerTarget: ScrollContainerTarget(stableId: stableId),
            direction: .down
        )))

        XCTAssertTrue(result.success, result.message ?? "explicit scroll failed")
        XCTAssertEqual(result.method, .scroll)
        XCTAssertGreaterThan(fixture.scrollView.contentOffset.y, 0)
        XCTAssertNotNil(result.accessibilityTrace)
        XCTAssertNotNil(result.accessibilityDelta?.captureEdge)
    }

    private func runSemanticActivateThroughCommand(
        identifier: String,
        label: String,
        batch: Bool
    ) async throws -> (result: ActionResult, activationCount: Int) {
        let localBrains = TheBrains(tripwire: TheTripwire())
        let fixture = try installOffscreenActivationFixture(
            identifier: identifier,
            label: label
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(fixture, in: localBrains)

        if batch {
            let target = SemanticActionTarget(
                sourceHeistId: fixture.knownHeistId,
                matcher: ElementMatcher(identifier: identifier, traits: [.button])
            )
            let plan = BatchPlan(steps: [
                .action(.activate(target)),
            ])
            let result = await localBrains.executeBatchExecutionPlan(plan)
            return (result, fixture.target.activationCount)
        }

        let result = await localBrains.executeCommand(.activate(
            .matcher(ElementMatcher(identifier: identifier, traits: [.button]))
        ))
        return (result, fixture.target.activationCount)
    }

    private func installOffscreenActivationFixture(
        identifier: String,
        label: String,
        nestedInGroup: Bool = false
    ) throws -> SemanticRevealFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let scrollView = RevealingScrollView(frame: CGRect(x: 24, y: 80, width: 320, height: 280))
        scrollView.contentSize = CGSize(width: 320, height: 1_400)
        scrollView.backgroundColor = .white
        scrollView.isAccessibilityElement = false

        let anchor = UILabel(frame: CGRect(x: 24, y: 24, width: 240, height: 44))
        anchor.text = "Visible Anchor \(identifier)"
        anchor.accessibilityLabel = anchor.text
        anchor.accessibilityIdentifier = "visible_anchor_\(identifier)"
        anchor.isAccessibilityElement = true
        scrollView.addSubview(anchor)

        let target = SemanticActivationView(frame: CGRect(x: 40, y: 900, width: 220, height: 44))
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityTraits = .button

        let contentOrigin: CGPoint
        if nestedInGroup {
            let group = UIView(frame: CGRect(x: 24, y: 860, width: 272, height: 120))
            group.accessibilityLabel = "Payment Actions"
            group.accessibilityIdentifier = "payment_actions_\(identifier)"
            group.isAccessibilityElement = false
            target.frame = CGRect(x: 16, y: 40, width: 220, height: 44)
            group.addSubview(target)
            scrollView.addSubview(group)
            contentOrigin = CGPoint(x: group.frame.minX + target.frame.minX, y: group.frame.minY + target.frame.minY)
        } else {
            scrollView.addSubview(target)
            contentOrigin = target.frame.origin
        }

        scrollView.revealedElements = [target]
        scrollView.updateAccessibilityVisibility()
        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return SemanticRevealFixture(
            window: window,
            scrollView: scrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: "known_\(identifier)",
            contentOrigin: contentOrigin
        )
    }

    private func installAmbiguousActivationFixture() throws -> AmbiguousActivationFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let first = SemanticActivationView(frame: CGRect(x: 32, y: 120, width: 220, height: 44))
        first.accessibilityLabel = "Duplicate"
        first.accessibilityIdentifier = "duplicate_first"
        first.accessibilityTraits = .button
        first.isAccessibilityElement = true

        let second = SemanticActivationView(frame: CGRect(x: 32, y: 184, width: 220, height: 44))
        second.accessibilityLabel = "Duplicate"
        second.accessibilityIdentifier = "duplicate_second"
        second.accessibilityTraits = .button
        second.isAccessibilityElement = true

        viewController.view.addSubview(first)
        viewController.view.addSubview(second)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return AmbiguousActivationFixture(window: window, first: first, second: second)
    }

    private func seedKnownOffscreenTarget(
        _ fixture: SemanticRevealFixture,
        in targetBrains: TheBrains? = nil,
        includeScrollView: Bool = true,
        scrollContainerOverride: HeistContainer? = nil
    ) throws {
        let targetBrains = targetBrains ?? brains!
        let screen = try XCTUnwrap(targetBrains.refresh())
        let element = makeElement(
            label: fixture.label,
            identifier: fixture.identifier,
            frame: CGRect(
                origin: fixture.contentOrigin,
                size: fixture.target.bounds.size
            )
        )
        let entry = Screen.ScreenElement(
            heistId: fixture.knownHeistId,
            contentSpaceOrigin: fixture.contentOrigin,
            scrollContainerStableId: scrollContainerOverride ?? firstScrollableStableId(in: screen),
            element: element
        )
        var elements = screen.elements
        elements[entry.heistId] = entry

        var elementRefs = screen.liveInterface.elementRefs
        if includeScrollView {
            elementRefs[entry.heistId] = .init(object: nil, scrollView: fixture.scrollView)
        }
        let liveInterface = Screen.LiveInterface(
            hierarchy: screen.liveInterface.hierarchy,
            containerStableIds: screen.liveInterface.containerStableIds,
            containerStableIdsByPath: screen.liveInterface.containerStableIdsByPath,
            heistIdByElement: screen.liveInterface.heistIdByElement,
            heistIdByElementPath: screen.liveInterface.heistIdByElementPath,
            elementRefs: elementRefs,
            containerRefsByPath: screen.liveInterface.containerRefsByPath,
            firstResponderHeistId: screen.liveInterface.firstResponderHeistId,
            scrollableContainerViews: screen.liveInterface.scrollableContainerViews,
            scrollableContainerViewsByPath: screen.liveInterface.scrollableContainerViewsByPath
        )
        targetBrains.stash.currentScreen = Screen(elements: elements, liveInterface: liveInterface)
    }

    private func firstScrollableStableId(in screen: Screen) -> HeistContainer? {
        for item in screen.liveInterface.hierarchy.containerPaths where item.container.isScrollable {
            if let stableId = screen.liveInterface.containerStableIdsByPath[item.path]
                ?? screen.liveInterface.containerStableIds[item.container] {
                return stableId
            }
        }
        return nil
    }

    private func makeElement(
        label: String,
        identifier: String,
        frame: CGRect = CGRect(x: 20, y: 20, width: 160, height: 44)
    ) -> AccessibilityElement {
        .make(
            label: label,
            identifier: identifier,
            traits: .button,
            frame: frame,
            respondsToUserInteraction: true
        )
    }

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
    }

    private func XCTAssertDiagnostic(
        _ message: String?,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let message else {
            XCTFail("Expected diagnostic message", file: file, line: line)
            return
        }
        for fragment in fragments {
            XCTAssertTrue(
                message.contains(fragment),
                "Expected diagnostic to contain '\(fragment)'. Message: \(message)",
                file: file,
                line: line
            )
        }
    }
}

private struct SemanticRevealFixture {
    let window: UIWindow
    let scrollView: RevealingScrollView
    let target: SemanticActivationView
    let identifier: String
    let label: String
    let knownHeistId: HeistId
    let contentOrigin: CGPoint

    @MainActor
    func cleanup() {
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

private struct AmbiguousActivationFixture {
    let window: UIWindow
    let first: SemanticActivationView
    let second: SemanticActivationView

    @MainActor
    func cleanup() {
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

private final class SemanticActivationView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

private final class RevealingScrollView: UIScrollView {
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
            element.accessibilityElementsHidden = !isRevealed
        }
    }
}

private extension ActionResult {
    var batchExecutionPayload: BatchExecutionResult? {
        guard case .batchExecution(let payload) = payload else { return nil }
        return payload
    }
}

#endif // canImport(UIKit)
