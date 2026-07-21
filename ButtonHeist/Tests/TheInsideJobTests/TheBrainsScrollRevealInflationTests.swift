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
        visibleObservationSource.observation = InterfaceObservation.makeForTests([
            .init(
                makeElement(label: "Replacement Target", traits: .button),
                heistId: targetId,
                object: retainedLiveObject()
            ),
        ])
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        scrollView.setContentOffsetAnimations.removeAll()
        let treeElement = try XCTUnwrap(brains.vault.interfaceElement(heistId: targetId))

        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            treeElement,
            deadline: semanticRevealDeadline()
        )

        guard case .targetResolutionFailed(.notFound) = result else {
            return XCTFail("Expected direct reused-ID evidence to fail as not found, got \(result)")
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
            brains.vault.interfaceTree.findElement(heistId: "settings_button")
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

    func testSemanticRevealPassesObservedContentPointToFallbackScan() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let observedPoint = CGPoint(x: 160, y: 1_200)
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Settings", traits: .button),
                heistId: "settings_button",
                contentActivationPoint: observedPoint,
                scrollView: scrollView
            )
        )
        let entry = try XCTUnwrap(brains.vault.interfaceTree.findElement(heistId: "settings_button"))
        let currentEvent = brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            brains.vault.latestObservation
        )
        let originalMoveViewport = brains.navigation.elementInflation.exploration.moveViewport
        var fallbackRequest: ElementInflation.SemanticTargetRevealRequest?
        brains.navigation.elementInflation.exploration.moveViewport = { _ in
            Navigation.ViewportTransition(
                outcome: .moved,
                previousVisibleIds: [],
                event: currentEvent
            )
        }
        brains.navigation.elementInflation.exploration.revealKnownTarget = { request in
            fallbackRequest = request
            return nil
        }
        defer {
            brains.navigation.elementInflation.exploration.moveViewport = originalMoveViewport
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        }

        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            entry,
            deadline: semanticRevealDeadline()
        )

        guard case .failed(.noLiveScrollableAncestor) = result else {
            return XCTFail("Expected fallback scan miss, got \(result)")
        }
        XCTAssertEqual(
            fallbackRequest?.target.target,
            try resolvedTarget(.label("Settings"))
        )
        XCTAssertEqual(
            fallbackRequest?.observedScrollContentActivationPoint,
            InterfaceTree.ObservedScrollContentActivationPoint(
                try ScrollContentPoint(validating: observedPoint),
                ownerPath: TreePath([0])
            )
        )
    }

    func testSemanticRevealDispatchesPointOnlyToMatchingOwner() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let observedPoint = CGPoint(x: 160, y: 1_200)
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Settings", traits: .button),
                heistId: "settings_button",
                contentActivationPoint: observedPoint,
                scrollView: scrollView
            )
        )
        let matchingObservation = brains.vault.latestObservation
        let matchingElement = try XCTUnwrap(
            matchingObservation.tree.findElement(heistId: "settings_button")
        )
        let mismatchedElement = InterfaceTree.Element(
            heistId: matchingElement.heistId,
            path: matchingElement.path,
            scrollMembership: matchingElement.scrollMembership,
            observedScrollContentActivationPoint: observedContentActivationPoint(
                observedPoint,
                ownerPath: TreePath([1])
            ),
            element: matchingElement.element
        )
        var mismatchedElements = matchingObservation.tree.elements
        mismatchedElements[mismatchedElement.heistId] = mismatchedElement
        let mismatchedObservation = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: mismatchedElements,
                containers: matchingObservation.tree.containers
            ),
            liveCapture: matchingObservation.liveCapture
        )
        let sourceTarget = try resolvedTarget(.label("Settings").and(.traits([.button])))
        var dispatchedPoints: [ScrollContentPoint] = []
        var dispatchedOwnerPaths: [TreePath] = []
        brains.navigation.elementInflation.exploration.moveViewport = { intent in
            if case .revealContentPoint(let point, let target) = intent {
                dispatchedPoints.append(point)
                dispatchedOwnerPaths.append(target.containerTarget.path)
            }
            return .unavailable()
        }
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }

        installSyntheticObservation(mismatchedObservation)
        guard case .admitted(let mismatchedTarget) = brains.navigation.elementInflation.admitSemanticTarget(
            sourceTarget,
            selectedElement: mismatchedElement
        ) else {
            return XCTFail("Expected mismatched fixture target to retain semantic admission")
        }
        _ = await brains.navigation.elementInflation.revealSemanticTarget(
            mismatchedTarget,
            initialElement: mismatchedElement,
            deadline: semanticRevealDeadline()
        )

        XCTAssertTrue(dispatchedPoints.isEmpty)
        XCTAssertTrue(dispatchedOwnerPaths.isEmpty)

        installSyntheticObservation(matchingObservation)
        guard case .admitted(let matchingTarget) = brains.navigation.elementInflation.admitSemanticTarget(
            sourceTarget,
            selectedElement: matchingElement
        ) else {
            return XCTFail("Expected matching fixture target to retain semantic admission")
        }
        _ = await brains.navigation.elementInflation.revealSemanticTarget(
            matchingTarget,
            initialElement: matchingElement,
            deadline: semanticRevealDeadline()
        )

        XCTAssertEqual(dispatchedPoints, [try ScrollContentPoint(validating: observedPoint)])
        XCTAssertEqual(dispatchedOwnerPaths, [TreePath([0])])
    }

    func testKnownTargetMissingOwnerContinuesAncestorPaging() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = RecordingScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        scrollView.contentSize = CGSize(width: 320, height: 1_200)
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let ancestorPath = TreePath([0])
        let missingOwnerPath = ancestorPath.appending(0)
        let container = makeScrollableContainer(
            contentSize: scrollView.contentSize,
            frame: scrollView.frame
        )
        let visibleElement = makeElement(label: "Visible")
        let visibleEntry = InterfaceTree.Element(
            heistId: "visible_element",
            scrollMembership: .init(containerPath: ancestorPath, index: nil),
            element: visibleElement
        )
        let knownElement = makeElement(label: "Paged Target", traits: .button)
        let knownEntry = InterfaceTree.Element(
            heistId: "known_paged_target",
            scrollMembership: .init(containerPath: missingOwnerPath, index: nil),
            observedScrollContentActivationPoint: observedContentActivationPoint(
                CGPoint(x: 160, y: 1_000),
                ownerPath: missingOwnerPath
            ),
            element: knownElement
        )
        let initialObservation = InterfaceObservation.makeForTests(
            elements: [
                visibleEntry.heistId: visibleEntry,
                knownEntry.heistId: knownEntry,
            ],
            hierarchy: [
                .container(container, children: [
                    .element(visibleElement, traversalIndex: 0),
                ]),
            ],
            heistIdsByPath: [ancestorPath.appending(0): visibleEntry.heistId],
            containerRefsByPath: [ancestorPath: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [ancestorPath: .init(view: scrollView)]
        )
        let revealedElement = makeElement(label: "Paged Target", traits: .button)
        let revealedEntry = InterfaceTree.Element(
            heistId: knownEntry.heistId,
            scrollMembership: .init(containerPath: ancestorPath, index: nil),
            element: revealedElement
        )
        let revealedObservation = InterfaceObservation.makeForTests(
            elements: [revealedEntry.heistId: revealedEntry],
            hierarchy: [
                .container(container, children: [
                    .element(revealedElement, traversalIndex: 0),
                ]),
            ],
            heistIdsByPath: [ancestorPath.appending(0): revealedEntry.heistId],
            elementRefs: [revealedEntry.heistId: .init(object: retainedLiveObject(), scrollView: scrollView)],
            containerRefsByPath: [ancestorPath: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [ancestorPath: .init(view: scrollView)]
        )
        installSyntheticObservation(initialObservation)
        scrollView.onSetContentOffset = { _ in
            self.visibleObservationSource.observation = revealedObservation
        }
        let sourceTarget = try resolvedTarget(.label("Paged Target").and(.traits([.button])))
        guard case .admitted(let admittedTarget) = brains.navigation.elementInflation.admitSemanticTarget(
            sourceTarget,
            selectedElement: knownEntry
        ) else {
            return XCTFail("Expected known target with missing owner to admit")
        }

        let result = await brains.navigation.scanForSemanticTarget(.init(
            target: admittedTarget,
            revealRootScrollViewID: ObjectIdentifier(scrollView),
            deadline: semanticRevealDeadline(),
            observedScrollContentActivationPoint: knownEntry.observedScrollContentActivationPoint
        ))

        guard case .revealed(_, let exploration) = result else {
            return XCTFail("Expected ancestor paging to reveal the target, got \(result)")
        }
        XCTAssertEqual(exploration.progress.scrollCount, 1)
        XCTAssertEqual(
            scrollView.contentOffset.y,
            -scrollView.adjustedContentInset.top
                + scrollView.bounds.height
                - CGFloat(ScrollContainerMetrics.pageOverlap),
            accuracy: 0.01
        )
    }

    func testSeededKnownTargetScanCanSatisfyWithoutPaging() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let targetId: HeistId = "settings_button"
        let observedPoint = observedContentActivationPoint(
            CGPoint(x: 160, y: 1_200),
            ownerPath: TreePath([0])
        )
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Settings", traits: .button),
                heistId: targetId,
                contentActivationPoint: observedPoint.point.cgPoint,
                scrollView: scrollView
            )
        )

        let visibleTarget = AccessibilityElement.make(
            label: "Settings",
            traits: .button,
            frame: CGRect(x: 40, y: 160, width: 220, height: 44)
        )
        let currentTargetId = targetId
        let visibleEntry = InterfaceTree.Element(
            heistId: currentTargetId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: visibleTarget
        )
        let revealedObservation = InterfaceObservation.makeForTests(
            elements: [currentTargetId: visibleEntry],
            hierarchy: [
                .container(makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame), children: [
                    .element(visibleTarget, traversalIndex: 0)
                ])
            ],
            containerNamesByPath: [TreePath([0]): "known_offscreen_scroll"],
            heistIdsByPath: [TreePath([0, 0]): currentTargetId],
            elementRefs: [currentTargetId: .init(object: retainedLiveObject(), scrollView: scrollView)],
            containerRefsByPath: [TreePath([0]): .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [TreePath([0]): .init(view: scrollView)]
        )
        scrollView.onSetContentOffset = { _ in
            self.visibleObservationSource.observation = revealedObservation
        }

        let initialElement = try XCTUnwrap(brains.vault.interfaceElement(heistId: targetId))
        let sourceTarget = try resolvedTarget(.label("Settings").and(.traits([.button])))
        guard case .admitted(let admittedTarget) = brains.navigation.elementInflation.admitSemanticTarget(
            sourceTarget,
            selectedElement: initialElement
        ) else {
            return XCTFail("Expected Settings to admit a portable semantic target")
        }
        let rootScrollViewID = try XCTUnwrap(
            brains.vault.liveScrollViewIDForRevealing(heistId: targetId)
        )

        let result = await brains.navigation.scanForSemanticTarget(.init(
            target: admittedTarget,
            revealRootScrollViewID: rootScrollViewID,
            deadline: semanticRevealDeadline(),
            observedScrollContentActivationPoint: observedPoint
        ))

        guard case .revealed(let currentElement, let exploration) = result else {
            return XCTFail("Expected seeded semantic scan to reveal the target, got \(result)")
        }
        XCTAssertEqual(currentElement.heistId, currentTargetId)
        XCTAssertEqual(exploration.progress.scrollCount, 0)
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [false])
    }

    func testSemanticRevealAdoptsCurrentIdAfterCandidateReordering() async throws {
        let selectedObject = SemanticActivationView()
        let siblingObject = SemanticActivationView()
        let postRevealObservation = InterfaceObservation.makeForTests([
            .init(
                reviewPRElement(priority: "P2"),
                heistId: "current_priority_one",
                object: siblingObject
            ),
            .init(
                reviewPRElement(priority: "P1"),
                heistId: "stabilized_priority_one",
                object: selectedObject
            ),
        ])

        let result = try await inflateSemanticDuplicate(
            postRevealObservation: postRevealObservation
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected semantic identity to survive geometry stabilization, got \(result)")
        }
        XCTAssertEqual(inflatedTarget.treeElement.heistId, "stabilized_priority_one")
        XCTAssertTrue(inflatedTarget.liveTarget.object === selectedObject)
        _ = AccessibilityActionDispatcher().activate(inflatedTarget.liveTarget)
        XCTAssertEqual(selectedObject.activationCount, 1)
        XCTAssertEqual(siblingObject.activationCount, 0)
    }

    func testSemanticRevealFailsWhenTargetDisappearsAtGeometryCapture() async throws {
        let siblingObject = SemanticActivationView()
        let result = try await inflateSemanticDuplicate(
            postRevealObservation: .makeForTests([
                .init(
                    reviewPRElement(priority: "P2"),
                    heistId: "current_priority_one",
                    object: siblingObject
                ),
            ])
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected the missing admitted target to fail, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, .notFound)
        XCTAssertEqual(siblingObject.activationCount, 0)
    }

    func testSemanticRevealFailsWhenTargetBecomesAmbiguousAtGeometryCapture() async throws {
        let firstObject = SemanticActivationView()
        let secondObject = SemanticActivationView()
        let result = try await inflateSemanticDuplicate(
            postRevealObservation: .makeForTests([
                .init(
                    reviewPRElement(priority: "P1"),
                    heistId: "current_priority_one",
                    object: firstObject
                ),
                .init(
                    reviewPRElement(priority: "P1"),
                    heistId: "stabilized_priority_one",
                    object: secondObject
                ),
            ])
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected the ambiguous admitted target to fail, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, .ambiguous)
        XCTAssertEqual(firstObject.activationCount, 0)
        XCTAssertEqual(secondObject.activationCount, 0)
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
        let entry = try XCTUnwrap(brains.vault.interfaceTree.findElement(heistId: "settings_button"))
        var knownTargetAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            knownTargetAttempts += 1
            return nil
        }
        let deadline = SemanticObservationDeadline(
            start: RuntimeElapsed.now,
            timeoutSeconds: 0
        )

        let state = await brains.navigation.elementInflation.stateAfterReveal(
            entry,
            target: try resolvedTarget(.label("Settings")),
            deadline: deadline,
            resolution: ActionSubjectResolution(origin: .known),
            transaction: .init(vault: brains.vault)
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
        let entry = try XCTUnwrap(brains.vault.interfaceTree.findElement(heistId: "settings_button"))
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
                transaction: .init(vault: self.brains.vault)
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
        brains.vault.installObservationForTesting(.makeForTests(
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

    private func inflateSemanticDuplicate(
        postRevealObservation: InterfaceObservation
    ) async throws -> ElementInflation.ElementInflationResult {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        installScreenWithOffViewport(
            visible: .init(reviewPRElement(priority: "P2"), heistId: "initial_priority_two"),
            offscreen: .init(
                reviewPRElement(
                    priority: "P1",
                    frame: CGRect(x: 40, y: 1_200, width: 240, height: 44)
                ),
                heistId: "initial_priority_one",
                contentActivationPoint: CGPoint(x: 160, y: 1_200),
                scrollView: scrollView
            )
        )
        let revealedObject = SemanticActivationView()
        let revealedObservation = InterfaceObservation.makeForTests([
            .init(
                reviewPRElement(priority: "P1"),
                heistId: "current_priority_one",
                object: revealedObject
            ),
            .init(
                reviewPRElement(priority: "P2"),
                heistId: "current_priority_two",
                object: SemanticActivationView()
            ),
        ])
        let originalMoveViewport = brains.navigation.elementInflation.exploration.moveViewport
        let originalGeometryEnvironment = brains.navigation.elementInflation.geometryEnvironment
        brains.navigation.elementInflation.exploration.moveViewport = { _ in .unavailable() }
        brains.navigation.elementInflation.geometryEnvironment = .init(
            now: { RuntimeElapsed.now },
            awaitFrame: {}
        )
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            self.brains.vault.observeInterface(revealedObservation)
            let event = self.brains.vault.semanticObservationStream
                .commitDiscoveryObservationForTesting(revealedObservation)
            self.visibleObservationSource.observation = postRevealObservation
            guard let current = self.brains.vault.interfaceElement(heistId: "current_priority_one") else {
                return .unavailable
            }
            return .revealed(
                current,
                Navigation.InterfaceExplorationResult(
                    event: event,
                    progress: .init(),
                    didMoveViewport: true
                )
            )
        }
        defer {
            brains.navigation.elementInflation.exploration.moveViewport = originalMoveViewport
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in .unavailable }
            brains.navigation.elementInflation.geometryEnvironment = originalGeometryEnvironment
        }
        let target = try resolvedTarget(
            .label("Review PR").and(
                .traits([.button]),
                .customContent(.init(label: "Priority", value: "P1"))
            )
        )
        return await brains.navigation.elementInflation.inflate(
            for: target,
            method: .activate,
            activationPointPolicy: .liveObjectOnly
        )
    }

    private func reviewPRElement(
        priority: String,
        frame: CGRect = CGRect(x: 40, y: 120, width: 240, height: 44)
    ) -> AccessibilityElement {
        .make(
            label: "Review PR",
            traits: .button,
            shape: .frame(AccessibilityRect(frame)),
            customContent: [
                .init(label: "Category", value: "Infrastructure", isImportant: true),
                .init(label: "Priority", value: priority, isImportant: true),
            ]
        )
    }

}

#endif
