#if canImport(UIKit)
import XCTest
import ThePlans

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension ElementInflationProductTests {

    // MARK: - Reveal and Nested Scrolling

    func testMissingTargetSettlesBeforeViewportDiscovery() async throws {
        enum Event: Equatable {
            case settled
            case discovered
        }

        var events: [Event] = []
        brains.navigation.elementInflation.exploration.settleForDiscovery = {
            events.append(.settled)
        }
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in
            events.append(.discovered)
            return nil
        }

        _ = await brains.navigation.elementInflation.findTargetInTree(
            try AccessibilityTarget.label("Offscreen Target").resolve(in: .empty)
        )

        XCTAssertEqual(events, [.settled, .discovered])
    }

    func testSemanticActivateRevealsOffscreenScrollTargetWithoutManualPreScroll() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "semantic_checkout_submit",
            label: "Submit Order"
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(fixture)

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier("semantic_checkout_submit"), traits: [.button])
            ).resolve(in: .empty)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "semantic activate failed")
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.subjectEvidence?.source, .resolvedSemanticTarget)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(
            result.subjectEvidence?.resolution,
            ActionSubjectResolution(origin: .known, adjustments: [.semanticReveal])
        )
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
    }

    func testLiveCaptureUsesDirectScrollContainerAsMovementOwner() throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "direct_scroll_owner",
            label: "Direct Scroll Owner"
        )
        defer { fixture.cleanup() }

        let screen = try XCTUnwrap(brains.vault.refreshLiveCapture())
        let paths = screen.liveCapture.scrollableContainerViewsByPath.compactMap { path, reference in
            reference.view === fixture.scrollView ? path : nil
        }

        XCTAssertEqual(paths.count, 1)
        let path = try XCTUnwrap(paths.first)
        XCTAssertTrue(screen.liveCapture.containerObject(forPath: path) === fixture.scrollView)
    }

    func testSemanticActivateRevealsNestedContainerTarget() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "nested_semantic_checkout_submit",
            label: "Confirm Payment",
            nestedInGroup: true
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(fixture)

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier("nested_semantic_checkout_submit"), traits: [.button])
            ).resolve(in: .empty)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "nested semantic activate failed")
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
    }

    func testSemanticTypeTextRevealsOffscreenTextTargetWithoutManualPreScroll() async throws {
        let fixture = try installOffscreenTextInputFixture(
            identifier: "semantic_delivery_note",
            label: "Delivery Note"
        )
        defer { fixture.cleanup() }

        let keyboardImpl = ProductTextInputKeyboardImpl(textField: fixture.target) { [weak self] in
            self?.brains.vault.invalidateSettledObservationFromTripwire()
        }
        brains.stopSemanticObservation()
        brains.tripwire.stopPulse()
        brains = TheBrains(
            tripwire: TheTripwire(),
            keyboardInput: SafecrackerKeyboardInput(
                keyboardBridgeProvider: { keyboardImpl.bridge() }
            ),
            visibleObservationSource: visibleObservationSource.capture
        )
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
        try seedOffViewportTextInputTarget(fixture)

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)
        XCTAssertFalse(fixture.target.isFirstResponder)

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.typeText(
                text: "leave at desk",
                target: .identifier(fixture.identifier)
            ).resolve(in: .empty)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "semantic type_text failed")
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.source, .textInputTarget)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(fixture.target.text, "leave at desk")
        XCTAssertTrue(fixture.target.isFirstResponder)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
        guard case .typeText(let value?) = result.payload else {
            return XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
        }
        XCTAssertEqual(value, "leave at desk")
    }

    func testActivateVisibleTextFieldFallsBackToTapWithoutDiscoveryScroll() async throws {
        let fixture = try installVisibleTextInputFixture(
            identifier: "visible_activation_text_field",
            label: "Customer Name"
        )
        defer { fixture.cleanup() }

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)
        XCTAssertFalse(fixture.target.isFirstResponder)

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier(fixture.identifier), traits: [.textEntry])
            ).resolve(in: .empty)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "visible text field activate failed")
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(
            result.subjectEvidence?.resolution,
            ActionSubjectResolution(origin: .visible)
        )
        XCTAssertTrue(fixture.target.isFirstResponder)
        XCTAssertEqual(fixture.scrollView.revealRequestCount, 0)
        XCTAssertEqual(result.activationTrace?.axActivateReturned, false)
        XCTAssertEqual(result.activationTrace?.tapActivationDispatched, true)
        XCTAssertEqual(result.activationTrace?.tapActivationSucceeded, true)
    }

    func testSemanticActivateRevealsTargetInsideNestedOffscreenScrollContainer() async throws {
        let fixture = try installNestedScrollActivationFixture(
            identifier: "nested_scroll_checkout_submit",
            label: "Confirm Nested Payment"
        )
        defer { fixture.cleanup() }
        try seedKnownNestedScrollTarget(fixture)
        var revealOrder: [ObjectIdentifier] = []
        fixture.outerScrollView.onFirstRevealRequest = {
            revealOrder.append(ObjectIdentifier(fixture.outerScrollView))
        }
        fixture.innerScrollView.onFirstRevealRequest = {
            revealOrder.append(ObjectIdentifier(fixture.innerScrollView))
        }

        XCTAssertEqual(fixture.outerScrollView.contentOffset, .zero)
        XCTAssertEqual(fixture.innerScrollView.contentOffset, .zero)

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier("nested_scroll_checkout_submit"), traits: [.button])
            ).resolve(in: .empty)
        )

        XCTAssertTrue(
            result.outcome.isSuccess,
            nestedScrollFailureDescription(result, fixture: fixture)
        )
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertEqual(revealOrder, [
            ObjectIdentifier(fixture.outerScrollView),
            ObjectIdentifier(fixture.innerScrollView),
        ])
        XCTAssertTrue(fixture.outerScrollView.didReceiveRevealRequest)
        XCTAssertTrue(fixture.innerScrollView.didReceiveRevealRequest)
    }

    func testSemanticActivateRevealsNestedScrollTargetWhenOtherWindowHasSameSizedScrollView() async throws {
        let fixture = try installNestedScrollActivationFixture(
            identifier: "nested_scroll_with_decoy_submit",
            label: "Confirm Decoy Payment"
        )
        defer { fixture.cleanup() }
        let decoy = try installScrollDecoyWindow(contentSize: fixture.innerScrollView.contentSize)
        defer { decoy.cleanup() }
        try seedKnownNestedScrollTarget(fixture, decoy: .separate(decoy.scrollView))
        XCTAssertTrue(brains.vault.scrollableContainerViewsByPath.values.contains { $0 === decoy.scrollView })
        let decoyRevealCount = decoy.scrollView.revealRequestCount
        let decoyOffset = decoy.scrollView.contentOffset

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier("nested_scroll_with_decoy_submit"), traits: [.button])
            ).resolve(in: .empty)
        )

        XCTAssertTrue(
            result.outcome.isSuccess,
            nestedScrollFailureDescription(result, fixture: fixture)
        )
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.outerScrollView.didReceiveRevealRequest)
        XCTAssertTrue(fixture.innerScrollView.didReceiveRevealRequest)
        XCTAssertEqual(decoy.scrollView.contentOffset, decoyOffset)
        XCTAssertEqual(decoy.scrollView.revealRequestCount, decoyRevealCount)
    }

    func testNestedRevealDoesNotTreatDuplicateOuterScrollViewPathAsInnerAlias() async throws {
        let fixture = try installNestedScrollActivationFixture(
            identifier: "nested_scroll_duplicate_outer_path_submit",
            label: "Confirm Duplicate Path Payment"
        )
        defer { fixture.cleanup() }
        let decoy = try installScrollDecoyWindow(contentSize: fixture.innerScrollView.contentSize)
        defer { decoy.cleanup() }
        try seedKnownNestedScrollTarget(
            fixture,
            decoy: .duplicateOuterReferenceAtDecoyPath(decoy.scrollView)
        )
        XCTAssertGreaterThanOrEqual(
            brains.vault.scrollableContainerViewsByPath.values.filter { $0 === fixture.outerScrollView }.count,
            2
        )

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier(fixture.identifier), traits: [.button])
            ).resolve(in: .empty)
        )

        XCTAssertTrue(
            result.outcome.isSuccess,
            nestedScrollFailureDescription(result, fixture: fixture)
        )
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.outerScrollView.didReceiveRevealRequest)
        XCTAssertTrue(fixture.innerScrollView.didReceiveRevealRequest)
        XCTAssertEqual(decoy.scrollView.contentOffset, .zero)
    }

    private func nestedScrollFailureDescription(
        _ result: ActionResult,
        fixture: NestedScrollRevealFixture
    ) -> String {
        [
            result.message ?? "nested scroll semantic activate failed",
            "outerOffset=\(fixture.outerScrollView.contentOffset)",
            "innerOffset=\(fixture.innerScrollView.contentOffset)",
            "outerReveals=\(fixture.outerScrollView.revealRequestCount)",
            "innerReveals=\(fixture.innerScrollView.revealRequestCount)",
            "targetHidden=\(fixture.target.isHidden)",
            "targetAccessible=\(fixture.target.isAccessibilityElement)",
            "liveIds=\(brains.vault.liveHeistIds().map(\.rawValue).sorted())",
            "semanticPath=\(brains.vault.interfaceElement(heistId: fixture.knownHeistId)?.scrollContainerPath?.indices ?? [])",
            brains.vault.liveScrollContainerDiagnostics(),
        ].joined(separator: "; ")
    }
    private func installOffscreenTextInputFixture(
        identifier: String,
        label: String
    ) throws -> TextInputRevealFixture {
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

        let target = ActivatingTextField(frame: CGRect(x: 40, y: 900, width: 220, height: 44))
        target.borderStyle = .roundedRect
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityValue = ""
        target.isAccessibilityElement = true
        scrollView.addSubview(target)

        scrollView.revealedElements = [target]
        scrollView.updateAccessibilityVisibility()
        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return TextInputRevealFixture(
            window: window,
            scrollView: scrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: HeistId(rawValue: identifier),
            frameOrigin: target.frame.origin
        )
    }

    private func installVisibleTextInputFixture(
        identifier: String,
        label: String
    ) throws -> TextInputRevealFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let scrollView = RevealingScrollView(frame: CGRect(x: 24, y: 80, width: 320, height: 280))
        scrollView.contentSize = CGSize(width: 320, height: 1_400)
        scrollView.backgroundColor = .white
        scrollView.isAccessibilityElement = false

        let target = RefusingActivationTextField(frame: CGRect(x: 40, y: 24, width: 220, height: 44))
        target.borderStyle = .roundedRect
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityValue = ""
        target.accessibilityTraits = target.accessibilityTraits.union(.textEntry)
        target.isAccessibilityElement = true
        scrollView.addSubview(target)

        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return TextInputRevealFixture(
            window: window,
            scrollView: scrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: HeistId(rawValue: identifier),
            frameOrigin: target.frame.origin
        )
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

        let innerAnchor = UILabel(frame: CGRect(x: 20, y: 20, width: 220, height: 44))
        innerAnchor.text = "Visible Inner Anchor \(identifier)"
        innerAnchor.accessibilityLabel = innerAnchor.text
        innerAnchor.accessibilityIdentifier = "visible_inner_anchor_\(identifier)"
        innerAnchor.isAccessibilityElement = true
        innerScrollView.addSubview(innerAnchor)

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
            knownHeistId: HeistId(rawValue: identifier),
            innerFrameOrigin: innerScrollView.frame.origin,
            targetFrameOrigin: target.frame.origin
        )
    }

    private func installScrollDecoyWindow(contentSize: CGSize) throws -> ScrollDecoyFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear

        let scrollView = RevealingScrollView(frame: CGRect(x: 12, y: 120, width: 280, height: 200))
        scrollView.contentSize = contentSize
        scrollView.backgroundColor = .clear
        scrollView.isAccessibilityElement = false
        let anchor = UILabel(frame: CGRect(x: 20, y: 20, width: 220, height: 44))
        anchor.text = "Separate Window Scroll Decoy"
        anchor.accessibilityLabel = anchor.text
        anchor.isAccessibilityElement = true
        scrollView.addSubview(anchor)
        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 90
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()
        return ScrollDecoyFixture(window: window, scrollView: scrollView)
    }

    private func seedOffViewportTextInputTarget(
        _ fixture: TextInputRevealFixture
    ) throws {
        let screen = try XCTUnwrap(brains.vault.refreshLiveCapture())
        let scrollContainerPath = try XCTUnwrap(
            firstLiveScrollableContainerPath(in: screen),
            "Expected fixture to expose a live scroll container. \(scrollContainerDiagnostics(in: screen))"
        )
        let element = makeElement(
            label: fixture.label,
            identifier: fixture.identifier,
            traits: UIAccessibilityTraits.fromNames(["textEntry"]),
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

        let discoveryObservation = InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: screen.tree.containers),
            liveCapture: screen.liveCapture
        )
        brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(discoveryObservation)
        visibleObservationSource.useLiveCapture()
    }
    private func seedKnownNestedScrollTarget(
        _ fixture: NestedScrollRevealFixture,
        decoy: NestedScrollDecoy = .absent
    ) throws {
        let screen = try XCTUnwrap(brains.vault.refreshLiveCapture())
        let outerContainerPath = try XCTUnwrap(
            liveScrollableContainerPath(for: fixture.outerScrollView, in: screen),
            "Expected nested fixture to expose the live outer scroll view. \(scrollContainerDiagnostics(in: screen))"
        )
        let decoyContainerPath: TreePath?
        switch decoy {
        case .absent:
            decoyContainerPath = nil
        case .separate(let scrollView), .duplicateOuterReferenceAtDecoyPath(let scrollView):
            decoyContainerPath = try XCTUnwrap(
                liveScrollableContainerPath(for: scrollView, in: screen),
                "Expected separate-window decoy in the parser capture. \(scrollContainerDiagnostics(in: screen))"
            )
        }
        let innerContainerPath = nestedInnerScrollContainerPath(
            for: fixture.innerScrollView,
            below: outerContainerPath,
            in: screen
        )
        let capturedInnerContainer = screen.tree.containers[innerContainerPath]
        let innerContainer = capturedInnerContainer?.container ?? AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(fixture.innerScrollView.contentSize),
            frame: AccessibilityRect(fixture.innerScrollView.frame)
        )
        let innerContainerName: ContainerName
        if let capturedName = capturedInnerContainer?.containerName {
            innerContainerName = capturedName
        } else {
            innerContainerName = TheVault.containerName(
                for: innerContainer,
                contentFrame: try ContentRect(
                    validating: CGRect(origin: .zero, size: fixture.innerScrollView.frame.size)
                )
            )
        }
        let element = makeElement(
            label: fixture.label,
            identifier: fixture.identifier,
            frame: CGRect(
                origin: fixture.targetFrameOrigin,
                size: fixture.target.bounds.size
            )
        )
        let observedTargetActivationPoint = try observedContentActivationPoint(
            origin: fixture.targetFrameOrigin,
            size: fixture.target.bounds.size,
            ownerPath: innerContainerPath
        )
        let entry = InterfaceTree.Element(
            heistId: fixture.knownHeistId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: innerContainerPath, index: nil),
            observedScrollContentActivationPoint: observedTargetActivationPoint,
            element: element
        )
        var elements = screen.tree.elements
        elements[entry.heistId] = entry

        var containers = screen.tree.containers
        let observedContainerActivationPoint = try capturedInnerContainer?.observedScrollContentActivationPoint
            ?? observedContentActivationPoint(
            origin: fixture.innerFrameOrigin,
            size: fixture.innerScrollView.frame.size,
            ownerPath: outerContainerPath
        )
        containers[innerContainerPath] = InterfaceTree.Container(
            container: innerContainer,
            path: innerContainerPath,
            containerName: innerContainerName,
            contentFrame: CGRect(origin: .zero, size: fixture.innerScrollView.frame.size),
            scrollMembership: capturedInnerContainer?.scrollMembership
                ?? InterfaceTree.ScrollMembership(containerPath: outerContainerPath, index: nil),
            observedScrollContentActivationPoint: observedContainerActivationPoint
        )

        let liveCapture: LiveCapture
        switch decoy {
        case .absent, .separate:
            liveCapture = screen.liveCapture
        case .duplicateOuterReferenceAtDecoyPath:
            var scrollableViews = screen.liveCapture.scrollableContainerViewsByPath
            scrollableViews[try XCTUnwrap(decoyContainerPath)] = .init(view: fixture.outerScrollView)
            liveCapture = LiveCapture.makeForTests(
                snapshot: screen.liveCapture.snapshot,
                dispatchReferences: .init(
                    elementRefs: screen.liveCapture.elementRefs,
                    containerRefsByPath: screen.liveCapture.containerRefsByPath,
                    scrollableContainerViewsByPath: scrollableViews
                )
            )
        }

        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: containers),
            liveCapture: liveCapture
        ))
        visibleObservationSource.useLiveCapture()
    }
    private func nestedInnerScrollContainerPath(
        for scrollView: UIScrollView,
        below outerContainerPath: TreePath,
        in observation: InterfaceObservation
    ) -> TreePath {
        if let path = liveScrollableContainerPath(for: scrollView, in: observation) {
            return path
        }

        // Hidden nested scroll views are absent before reveal; the parser assigns
        // the revealed inner scroll view as the first child container.
        return outerContainerPath.appending(0)
    }
}

private struct TextInputRevealFixture {
    let window: UIWindow
    let scrollView: RevealingScrollView
    let target: UITextField
    let identifier: String
    let label: String
    let knownHeistId: HeistId
    let frameOrigin: CGPoint

    @MainActor
    func cleanup() {
        _ = target.resignFirstResponder()
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
    let innerFrameOrigin: CGPoint
    let targetFrameOrigin: CGPoint

    @MainActor
    func cleanup() {
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

private enum NestedScrollDecoy {
    case absent
    case separate(RevealingScrollView)
    case duplicateOuterReferenceAtDecoyPath(RevealingScrollView)
}

private struct ScrollDecoyFixture {
    let window: UIWindow
    let scrollView: RevealingScrollView

    @MainActor
    func cleanup() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
private final class RefusingActivationTextField: UITextField {
    private(set) var resignationCount = 0

    override func accessibilityActivate() -> Bool {
        false
    }

    override func resignFirstResponder() -> Bool {
        resignationCount += 1
        return super.resignFirstResponder()
    }
}

private final class ActivatingTextField: UITextField {
    override func accessibilityActivate() -> Bool {
        becomeFirstResponder()
    }
}

@MainActor
private final class ProductTextInputKeyboardImpl: NSObject {
    private final class TextInputDelegate: NSObject, UIKeyInput {
        var hasText: Bool { false }
        func insertText(_ text: String) {}
        func deleteBackward() {}
    }

    private let inputDelegate = TextInputDelegate()
    private weak var textField: UITextField?
    private let onInput: @MainActor () -> Void

    init(textField: UITextField, onInput: @escaping @MainActor () -> Void) {
        self.textField = textField
        self.onInput = onInput
    }

    @objc(delegate)
    func delegate() -> AnyObject? {
        guard textField?.isFirstResponder == true else { return nil }
        return inputDelegate
    }

    @objc(addInputString:withFlags:)
    func addInputString(_ text: NSString, flags: UInt) {
        guard textField?.isFirstResponder == true else { return }
        let nextValue = (textField?.text ?? "") + (text as String)
        textField?.text = nextValue
        textField?.accessibilityValue = nextValue
        onInput()
    }

    @objc(taskQueue)
    func taskQueue() -> AnyObject? {
        self
    }

    @objc(waitUntilAllTasksAreFinished)
    func waitUntilAllTasksAreFinished() {}

    func bridge() -> KeyboardBridge {
        KeyboardBridge(
            impl: self,
            textInjection: UIKeyboardImplTextInjection(impl: self)
        )
    }
}

#endif // canImport(UIKit)
