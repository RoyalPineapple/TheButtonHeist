#if canImport(UIKit)
import XCTest
import ThePlans

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class ElementInflationProductTests: XCTestCase {

    var brains: TheBrains!
    var visibleObservationSource: VisibleObservationSourceFixture!

    override func setUp() async throws {
        try await super.setUp()
        visibleObservationSource = VisibleObservationSourceFixture()
        brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
    }

    override func tearDown() async throws {
        brains?.stopSemanticObservation()
        brains?.tripwire.stopPulse()
        if let brains {
            assertRuntimeStopped(brains)
        }
        brains = nil
        visibleObservationSource = nil
        try await super.tearDown()
    }

    func assertRuntimeStopped(
        _ brains: TheBrains,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let observationStream = brains.vault.semanticObservationStream
        XCTAssertFalse(brains.semanticObservationIsActive, file: file, line: line)
        XCTAssertFalse(brains.tripwire.isPulseRunning, file: file, line: line)
        XCTAssertFalse(observationStream.isActive, file: file, line: line)
        XCTAssertEqual(observationStream.observationWaiterCount, 0, file: file, line: line)
        XCTAssertEqual(observationStream.activeObservationDemandCount, 0, file: file, line: line)
    }

    func installOffscreenActivationFixture(
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

        let frameOrigin: CGPoint
        if nestedInGroup {
            let group = UIView(frame: CGRect(x: 24, y: 860, width: 272, height: 120))
            group.accessibilityLabel = "Payment Actions"
            group.accessibilityIdentifier = "payment_actions_\(identifier)"
            group.isAccessibilityElement = false
            target.frame = CGRect(x: 16, y: 40, width: 220, height: 44)
            group.addSubview(target)
            scrollView.addSubview(group)
            frameOrigin = CGPoint(x: group.frame.minX + target.frame.minX, y: group.frame.minY + target.frame.minY)
        } else {
            scrollView.addSubview(target)
            frameOrigin = target.frame.origin
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
            knownHeistId: HeistId(rawValue: identifier),
            frameOrigin: frameOrigin
        )
    }

    func seedOffViewportTarget(
        _ fixture: SemanticRevealFixture,
        in targetBrains: TheBrains? = nil,
        semanticIdentifier: String? = nil,
        semanticLabel: String? = nil,
        scrollContainerPathOverride: TreePath? = nil,
        refreshesFromUIKit: Bool = true
    ) throws {
        let targetBrains = targetBrains ?? brains!
        let screen = try XCTUnwrap(targetBrains.vault.refreshLiveCapture())
        let identifier = semanticIdentifier ?? fixture.identifier
        let label = semanticLabel ?? fixture.label
        let scrollContainerPath: TreePath
        if let scrollContainerPathOverride {
            scrollContainerPath = scrollContainerPathOverride
        } else {
            scrollContainerPath = try XCTUnwrap(
                firstLiveScrollableContainerPath(in: screen),
                "Expected fixture to expose a live scroll container. \(scrollContainerDiagnostics(in: screen))"
            )
        }
        let element = makeElement(
            label: label,
            identifier: identifier,
            frame: CGRect(
                origin: fixture.frameOrigin,
                size: fixture.target.bounds.size
            )
        )
        let observedActivationPoint = try observedContentActivationPoint(
            origin: fixture.frameOrigin,
            size: fixture.target.bounds.size,
            ownerPath: scrollContainerPath
        )
        let entry = InterfaceTree.Element(
            heistId: fixture.knownHeistId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: observedActivationPoint,
            element: element
        )
        var elements = screen.tree.elements
        elements[entry.heistId] = entry

        targetBrains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: screen.tree.containers),
            liveCapture: screen.liveCapture
        ))
        if refreshesFromUIKit, targetBrains === brains {
            visibleObservationSource.useLiveCapture()
        }
    }

    func observedContentActivationPoint(
        origin: CGPoint,
        size: CGSize,
        ownerPath: TreePath
    ) throws -> InterfaceTree.ObservedScrollContentActivationPoint {
        try XCTUnwrap(InterfaceTree.ObservedScrollContentActivationPoint(CGPoint(
            x: origin.x + size.width / 2,
            y: origin.y + size.height / 2
        ), ownerPath: ownerPath))
    }
    func firstLiveScrollableContainerPath(in observation: InterfaceObservation) -> TreePath? {
        for item in observation.liveCapture.hierarchy.scrollablePathIndexedContainers {
            guard observation.liveCapture.scrollView(forContainerPath: item.path) != nil else { continue }
            return item.path
        }
        return nil
    }

    func liveScrollableContainerPath(
        for scrollView: UIScrollView,
        in observation: InterfaceObservation
    ) -> TreePath? {
        let matchingPaths = observation.liveCapture.scrollableContainerViewsByPath
            .compactMap { path, ref -> TreePath? in
                guard ref.view === scrollView else { return nil }
                return path
            }
            .sorted { $0.indices.lexicographicallyPrecedes($1.indices) }
        return matchingPaths.first {
            observation.liveCapture.containerObject(forPath: $0) === scrollView
        } ?? matchingPaths.first
    }

    func scrollContainerDiagnostics(in observation: InterfaceObservation) -> String {
        let summaries = observation.liveCapture.hierarchy.scrollablePathIndexedContainers
            .map { item -> String in
                let name = observation.tree.containers[item.path]?.containerName
                let hasLiveScroll = observation.liveCapture.scrollView(forContainerPath: item.path) != nil
                return "path=\(item.path.indices) name=\(name ?? "<nil>") liveScroll=\(hasLiveScroll)"
            }
        return "scrollContainers=[\(summaries.joined(separator: "; "))]"
    }

    func makeElement(
        label: String,
        identifier: String,
        traits: UIAccessibilityTraits = .button,
        frame: CGRect = CGRect(x: 20, y: 20, width: 160, height: 44)
    ) -> AccessibilityElement {
        .make(
            label: label,
            identifier: identifier,
            traits: traits,
            frame: frame,
            respondsToUserInteraction: true
        )
    }
}

struct SemanticRevealFixture {
    let window: UIWindow
    let scrollView: RevealingScrollView
    let target: SemanticActivationView
    let identifier: String
    let label: String
    let knownHeistId: HeistId
    let frameOrigin: CGPoint

    @MainActor
    func cleanup() {
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}
final class SemanticActivationView: UIView {
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
final class RevealingScrollView: UIScrollView {
    var revealedElements: [UIView] = []
    var revealedContainers: [UIView] = []
    var onFirstRevealRequest: (() -> Void)?
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
            if revealRequestCount == 0 {
                onFirstRevealRequest?()
            }
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

#endif // canImport(UIKit)
