#if canImport(UIKit)
import XCTest
import ThePlans

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

private extension AccessibilityTrace.Delta {
    var testCaptureEdge: AccessibilityTrace.CaptureEdge? {
        switch self {
        case .noChange(let payload):
            return payload.captureEdge
        case .elementsChanged(let payload):
            return payload.captureEdge
        case .screenChanged(let payload):
            return payload.captureEdge
        }
    }
}

@MainActor
final class ElementInflationProductTests: XCTestCase {

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

    func testSemanticActivateRevealsOffscreenScrollTargetWithoutManualPreScroll() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "semantic_checkout_submit",
            label: "Submit Order"
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(fixture)

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)

        let result = await brains.executeRuntimeAction(.activate(
            .predicate(ElementPredicate(identifier: "semantic_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(result.success, result.message ?? "semantic activate failed")
        guard result.success else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
    }

    func testSemanticActivateRevealsNestedContainerTarget() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "nested_semantic_checkout_submit",
            label: "Confirm Payment",
            nestedInGroup: true
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(fixture)

        let result = await brains.executeRuntimeAction(.activate(
            .predicate(ElementPredicate(identifier: "nested_semantic_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(result.success, result.message ?? "nested semantic activate failed")
        guard result.success else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
    }

    func testSemanticActivateRevealsTargetInsideNestedOffscreenScrollContainer() async throws {
        let fixture = try installNestedScrollActivationFixture(
            identifier: "nested_scroll_checkout_submit",
            label: "Confirm Nested Payment"
        )
        defer { fixture.cleanup() }
        try seedKnownNestedScrollTarget(fixture)

        XCTAssertEqual(fixture.outerScrollView.contentOffset, .zero)
        XCTAssertEqual(fixture.innerScrollView.contentOffset, .zero)

        let result = await brains.executeRuntimeAction(.activate(
            .predicate(ElementPredicate(identifier: "nested_scroll_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(result.success, result.message ?? "nested scroll semantic activate failed")
        guard result.success else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.outerScrollView.didReceiveRevealRequest)
        XCTAssertTrue(fixture.innerScrollView.didReceiveRevealRequest)
    }

    func testAmbiguousSemanticActivateFailsBeforeGeometryOrAction() async throws {
        let fixture = try installAmbiguousActivationFixture()
        defer { fixture.cleanup() }

        let result = await brains.executeRuntimeAction(.activate(
            .predicate(ElementPredicate(label: "Duplicate", traits: [.button]))
        ))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.errorKind, .elementNotFound)
        XCTAssertEqual(fixture.first.activationCount, 0)
        XCTAssertEqual(fixture.second.activationCount, 0)
        XCTAssertDiagnostic(result.message, contains: [
            "2 elements match",
            "use ordinal",
        ])
    }

    func testSemanticActivateIgnoresStaleUnreachableDuplicateWhenOneCandidateIsReachable() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "reachable_duplicate_submit",
            label: "Duplicate Submit"
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(fixture)
        seedKnownUnreachableDuplicate(
            label: fixture.label,
            identifier: "stale_\(fixture.identifier)",
            heistId: "stale_\(fixture.knownHeistId)"
        )

        let result = await brains.executeRuntimeAction(.activate(
            .predicate(ElementPredicate(label: .exact(fixture.label), traits: [.button]))
        ))

        XCTAssertTrue(result.success, result.message ?? "semantic activate failed")
        guard result.success else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
    }

    func testMissingRevealPathFailsAsInflationDiagnostic() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "unrevealable_submit",
            label: "Submit Order"
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(
            fixture,
            scrollContainerOverride: "missing_scroll"
        )

        let result = await brains.executeRuntimeAction(.activate(
            .predicate(ElementPredicate(identifier: "unrevealable_submit", traits: [.button]))
        ))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertDiagnostic(result.message, contains: [
            "element inflation failed [noRevealPath]",
            "no live scrollable ancestor",
        ])
        XCTAssertFalse(result.message?.localizedCaseInsensitiveContains("scroll first") ?? false)
        XCTAssertFalse(result.message?.contains("get_interface") ?? false)
    }

    func testHeistSemanticActivateMatchesSingleActionResultSemantics() async throws {
        let single = try await runSemanticActivateThroughCommand(
            identifier: "single_semantic_heist_parity",
            label: "Heist Parity Single",
            heist: false
        )
        let heist = try await runSemanticActivateThroughCommand(
            identifier: "heist_semantic_heist_parity",
            label: "Heist Parity Heist",
            heist: true
        )
        let heistPayload = try XCTUnwrap(heist.result.heistExecutionPayload)
        let step = try XCTUnwrap(heistPayload.steps.first)
        guard case .action(let actionEvidence)? = step.evidence else {
            return XCTFail("Expected heist action evidence, got \(String(describing: step.evidence))")
        }
        let stepResult = try XCTUnwrap(actionEvidence.actionResult)

        XCTAssertTrue(single.result.success, single.result.message ?? "single activate failed")
        XCTAssertTrue(heist.result.success, heistFailureDescription(heist.result))
        guard single.result.success, heist.result.success else { return }
        XCTAssertEqual(single.activationCount, 1)
        XCTAssertEqual(heist.activationCount, 1)
        XCTAssertEqual(step.kind, .action)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(single.result.method, .activate)
        XCTAssertEqual(stepResult.method, .activate)
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

        let result = await brains.executeRuntimeAction(.scroll(ScrollTarget(
            elementTarget: .predicate(ElementPredicate(identifier: "visible_anchor_explicit_scroll_revealed")),
            direction: .down
        )))

        XCTAssertTrue(result.success, result.message ?? "explicit scroll failed")
        XCTAssertEqual(result.method, .scroll)
        XCTAssertGreaterThan(fixture.scrollView.contentOffset.y, 0)
        XCTAssertNotNil(result.accessibilityTrace)
        let delta = try XCTUnwrap(result.accessibilityTrace?.endpointDelta)
        XCTAssertNotNil(delta.testCaptureEdge)
    }

    private func runSemanticActivateThroughCommand(
        identifier: String,
        label: String,
        heist: Bool
    ) async throws -> (result: ActionResult, activationCount: Int) {
        let localBrains = TheBrains(tripwire: TheTripwire())
        localBrains.tripwire.startPulse()
        localBrains.startSemanticObservation()
        defer {
            localBrains.stopSemanticObservation()
            localBrains.tripwire.stopPulse()
        }
        let fixture = try installOffscreenActivationFixture(
            identifier: identifier,
            label: label
        )
        defer { fixture.cleanup() }
        try seedKnownOffscreenTarget(fixture, in: localBrains)

        if heist {
            let plan = try HeistPlan(body: [
                .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(identifier: .exact(.literal(identifier)), traits: [.button]))))),
            ])
            let result = await localBrains.executeHeistPlan(plan)
            return (result, fixture.target.activationCount)
        }

        let result = await localBrains.executeRuntimeAction(.activate(
            .predicate(ElementPredicate(identifier: .exact(identifier), traits: [.button]))
        ))
        return (result, fixture.target.activationCount)
    }

    private func heistFailureDescription(_ result: ActionResult) -> String {
        guard let payload = result.heistExecutionPayload else {
            return result.message ?? "heist activate failed"
        }
        guard let failedStep = payload.firstFailedStep else {
            return result.message ?? "heist activate failed without a failed receipt step"
        }
        let actionMessage = failedStep.reportActionResult?.message
        return [
            result.message,
            "failedStep=\(failedStep.path)",
            "kind=\(failedStep.kind.rawValue)",
            failedStep.reportMessage.map { "message=\($0)" },
            actionMessage.map { "actionMessage=\($0)" },
        ]
        .compactMap(\.self)
        .joined(separator: "; ")
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

    private func installNestedScrollActivationFixture(
        identifier: String,
        label: String
    ) throws -> NestedScrollRevealFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let outerScrollView = RevealingScrollView(frame: CGRect(x: 24, y: 80, width: 320, height: 280))
        outerScrollView.contentSize = CGSize(width: 320, height: 1_400)
        outerScrollView.backgroundColor = .white
        outerScrollView.isAccessibilityElement = false

        let anchor = UILabel(frame: CGRect(x: 24, y: 24, width: 240, height: 44))
        anchor.text = "Visible Nested Anchor \(identifier)"
        anchor.accessibilityLabel = anchor.text
        anchor.accessibilityIdentifier = "visible_nested_anchor_\(identifier)"
        anchor.isAccessibilityElement = true
        outerScrollView.addSubview(anchor)

        let innerScrollView = RevealingScrollView(frame: CGRect(x: 20, y: 820, width: 280, height: 200))
        innerScrollView.contentSize = CGSize(width: 280, height: 900)
        innerScrollView.backgroundColor = .white
        innerScrollView.isAccessibilityElement = false

        let target = SemanticActivationView(frame: CGRect(x: 20, y: 640, width: 220, height: 44))
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityTraits = .button
        innerScrollView.addSubview(target)
        innerScrollView.revealedElements = [target]
        innerScrollView.updateAccessibilityVisibility()

        outerScrollView.addSubview(innerScrollView)
        outerScrollView.revealedContainers = [innerScrollView]
        outerScrollView.updateAccessibilityVisibility()
        viewController.view.addSubview(outerScrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return NestedScrollRevealFixture(
            window: window,
            outerScrollView: outerScrollView,
            innerScrollView: innerScrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: "known_\(identifier)",
            innerContainerPath: TreePath([9_001]),
            innerContentOrigin: innerScrollView.frame.origin,
            targetContentOrigin: target.frame.origin
        )
    }

    private func seedKnownOffscreenTarget(
        _ fixture: SemanticRevealFixture,
        in targetBrains: TheBrains? = nil,
        scrollContainerOverride: ContainerName? = nil
    ) throws {
        let targetBrains = targetBrains ?? brains!
        let screen = try XCTUnwrap(targetBrains.stash.refreshLiveCapture())
        let scrollContainerName: ContainerName
        if let scrollContainerOverride {
            scrollContainerName = scrollContainerOverride
        } else {
            scrollContainerName = try XCTUnwrap(
                firstLiveScrollableContainerName(in: screen),
                "Expected fixture to expose a live scroll container. \(scrollContainerDiagnostics(in: screen))"
            )
        }
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
            scrollContainerName: scrollContainerName,
            element: element
        )
        var elements = screen.semantic.elements
        elements[entry.heistId] = entry

        let liveCapture = LiveCapture(
            hierarchy: screen.liveCapture.hierarchy,
            containerNames: screen.liveCapture.containerNames,
            containerNamesByPath: screen.liveCapture.containerNamesByPath,
            heistIdByElement: screen.liveCapture.heistIdByElement,
            elementRefs: screen.liveCapture.elementRefs,
            containerRefsByPath: screen.liveCapture.containerRefsByPath,
            containerScrollContentLocationsByPath: screen.liveCapture.containerScrollContentLocationsByPath,
            firstResponderHeistId: screen.liveCapture.firstResponderHeistId,
            scrollableContainerViews: screen.liveCapture.scrollableContainerViews,
            scrollableContainerViewsByPath: screen.liveCapture.scrollableContainerViewsByPath
        )
        targetBrains.stash.installScreenForTesting(Screen(
            semantic: SemanticScreen(elements: elements, containers: screen.semantic.containers),
            liveCapture: liveCapture
        ))
    }

    private func seedKnownUnreachableDuplicate(
        label: String,
        identifier: String,
        heistId: HeistId
    ) {
        let screen = brains.stash.settledSemanticScreen
        let entry = Screen.ScreenElement(
            heistId: heistId,
            scrollContentLocation: nil,
            element: makeElement(label: label, identifier: identifier)
        )
        var elements = screen.semantic.elements
        elements[heistId] = entry
        brains.stash.installScreenForTesting(Screen(
            semantic: SemanticScreen(elements: elements, containers: screen.semantic.containers),
            liveCapture: screen.liveCapture
        ))
    }

    private func seedKnownNestedScrollTarget(
        _ fixture: NestedScrollRevealFixture
    ) throws {
        let screen = try XCTUnwrap(brains.stash.refreshLiveCapture())
        let outerContainerName = try XCTUnwrap(
            firstLiveScrollableContainerName(in: screen),
            "Expected nested fixture to expose a live outer scroll container. \(scrollContainerDiagnostics(in: screen))"
        )
        let innerContainer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(fixture.innerScrollView.contentSize)),
            frame: AccessibilityRect(fixture.innerScrollView.frame)
        )
        let innerContainerName = TheBurglar.containerName(
            for: innerContainer,
            contentFrame: CGRect(origin: .zero, size: fixture.innerScrollView.frame.size)
        )
        XCTAssertNil(
            screen.liveCapture.scrollView(forContainer: innerContainerName),
            "Nested scroll fixture should start with the inner scroll container absent from the live tree"
        )

        let element = makeElement(
            label: fixture.label,
            identifier: fixture.identifier,
            frame: CGRect(
                origin: fixture.targetContentOrigin,
                size: fixture.target.bounds.size
            )
        )
        let entry = Screen.ScreenElement(
            heistId: fixture.knownHeistId,
            contentSpaceOrigin: fixture.targetContentOrigin,
            scrollContainerName: innerContainerName,
            element: element
        )
        var elements = screen.semantic.elements
        elements[entry.heistId] = entry

        var containers = screen.semantic.containers
        containers[fixture.innerContainerPath] = SemanticScreen.Container(
            container: innerContainer,
            path: fixture.innerContainerPath,
            containerName: innerContainerName,
            contentFrame: CGRect(origin: .zero, size: fixture.innerScrollView.frame.size),
            scrollContentLocation: Screen.ScrollContentLocation(
                origin: fixture.innerContentOrigin,
                scrollContainer: outerContainerName
            )
        )

        brains.stash.installScreenForTesting(Screen(
            semantic: SemanticScreen(elements: elements, containers: containers),
            liveCapture: screen.liveCapture
        ))
    }

    private func firstLiveScrollableContainerName(in screen: Screen) -> ContainerName? {
        for item in screen.liveCapture.hierarchy.containerPaths where item.container.isScrollable {
            guard let containerName = screen.liveCapture.containerNamesByPath[item.path]
                ?? screen.liveCapture.containerNames[item.container],
                  screen.liveCapture.scrollView(forContainer: containerName) != nil
            else { continue }
            return containerName
        }
        return nil
    }

    private func scrollContainerDiagnostics(in screen: Screen) -> String {
        let summaries = screen.liveCapture.hierarchy.containerPaths
            .filter { $0.container.isScrollable }
            .map { item -> String in
                let name = screen.liveCapture.containerNamesByPath[item.path]
                    ?? screen.liveCapture.containerNames[item.container]
                let hasLiveScroll = name.flatMap { screen.liveCapture.scrollView(forContainer: $0) } != nil
                return "path=\(item.path.indices) name=\(name ?? "<nil>") liveScroll=\(hasLiveScroll)"
            }
        return "scrollContainers=[\(summaries.joined(separator: "; "))]"
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

private struct NestedScrollRevealFixture {
    let window: UIWindow
    let outerScrollView: RevealingScrollView
    let innerScrollView: RevealingScrollView
    let target: SemanticActivationView
    let identifier: String
    let label: String
    let knownHeistId: HeistId
    let innerContainerPath: TreePath
    let innerContentOrigin: CGPoint
    let targetContentOrigin: CGPoint

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

    override var accessibilityTraits: UIAccessibilityTraits {
        get { super.accessibilityTraits.union(.button) }
        set { super.accessibilityTraits = newValue.union(.button) }
    }

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

private final class RevealingScrollView: UIScrollView {
    var revealedElements: [UIView] = []
    var revealedContainers: [UIView] = []
    private(set) var revealRequestCount = 0
    var didReceiveRevealRequest: Bool { revealRequestCount > 0 }
    private let revealThreshold: CGFloat = 500

    override var contentOffset: CGPoint {
        didSet {
            updateAccessibilityVisibility()
        }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if contentOffset.y >= revealThreshold {
            revealRequestCount += 1
        }
        super.setContentOffset(contentOffset, animated: animated)
        updateAccessibilityVisibility(for: contentOffset)
    }

    func updateAccessibilityVisibility(for offset: CGPoint? = nil) {
        let isRevealed = (offset ?? contentOffset).y >= revealThreshold
        for container in revealedContainers {
            container.isHidden = !isRevealed
            container.accessibilityElementsHidden = !isRevealed
        }
        for element in revealedElements {
            element.isHidden = !isRevealed
            element.isAccessibilityElement = isRevealed
            element.accessibilityElementsHidden = !isRevealed
        }
    }
}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let payload) = payload else { return nil }
        return payload
    }
}

#endif // canImport(UIKit)
