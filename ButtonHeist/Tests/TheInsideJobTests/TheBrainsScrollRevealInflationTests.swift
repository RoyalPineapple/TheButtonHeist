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

    func testMissingInnerOwnerPagesAncestorWithoutReusingInnerContentPoint() async throws {
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
        let innerContentPoint = CGPoint(x: 160, y: 1_000)
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
                innerContentPoint,
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
        var movementTargets: [ObjectIdentifier] = []
        scrollView.onSetContentOffset = { scrollView in
            movementTargets.append(ObjectIdentifier(scrollView))
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
        let expectedPageOffset = scrollView.bounds.height
            - CGFloat(ScrollContainerMetrics.pageOverlap) - scrollView.adjustedContentInset.top
        let innerSeedOffset = innerContentPoint.y - scrollView.bounds.height / 2
        XCTAssertEqual(exploration.progress.scrollCount, 1)
        XCTAssertEqual(movementTargets, [ObjectIdentifier(scrollView)])
        XCTAssertEqual(scrollView.requestedContentOffsets, [CGPoint(x: 0, y: expectedPageOffset)])
        XCTAssertNotEqual(scrollView.requestedContentOffsets[0].y, innerSeedOffset, accuracy: 0.01)
        XCTAssertEqual(scrollView.contentOffset.y, expectedPageOffset, accuracy: 0.01)
    }

    func testSiblingOwnerMismatchDoesNotDispatchSeed() async throws {
        let fixture = siblingOwnerMismatchFixture()
        let window = try installModalWindow(rootView: fixture.rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        installSyntheticObservation(fixture.initialObservation)
        fixture.siblingScrollView.onSetContentOffset = { _ in
            self.visibleObservationSource.observation = fixture.revealedObservation
        }
        let sourceTarget = try resolvedTarget(
            .label("Sibling Target").and(.traits([.button]))
        )
        guard case .admitted(let admittedTarget) = brains.navigation.elementInflation.admitSemanticTarget(
            sourceTarget,
            selectedElement: fixture.targetEntry
        ) else {
            return XCTFail("Expected sibling target to admit")
        }

        let result = await brains.navigation.scanForSemanticTarget(.init(
            target: admittedTarget,
            revealRootScrollViewID: ObjectIdentifier(fixture.ancestorScrollView),
            deadline: semanticRevealDeadline(),
            observedScrollContentActivationPoint: fixture.targetEntry.observedScrollContentActivationPoint
        ))

        guard case .revealed(_, let exploration) = result else {
            return XCTFail("Expected sibling paging to reveal the target, got \(result)")
        }
        let expectedPageOffset = -fixture.siblingScrollView.adjustedContentInset.top
            + fixture.siblingScrollView.bounds.height
            - CGFloat(ScrollContainerMetrics.pageOverlap)
        let storedSeedOffset = fixture.storedInnerPoint.y
            - fixture.siblingScrollView.bounds.height / 2
        XCTAssertEqual(exploration.progress.scrollCount, 1)
        XCTAssertTrue(fixture.ancestorScrollView.requestedContentOffsets.isEmpty)
        XCTAssertEqual(fixture.siblingScrollView.requestedContentOffsets.count, 1)
        XCTAssertEqual(fixture.siblingScrollView.requestedContentOffsets[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(fixture.siblingScrollView.requestedContentOffsets[0].y, expectedPageOffset, accuracy: 0.01)
        XCTAssertNotEqual(fixture.siblingScrollView.requestedContentOffsets[0].y, storedSeedOffset, accuracy: 0.01)
    }

    func testLaterOwnerMatchConsumesStoredSeed() async throws {
        let fixture = laterOwnerMatchFixture()
        installSyntheticObservation(fixture.unavailableObservation)
        let sourceTarget = try resolvedTarget(
            .label("Later Owner Target").and(.traits([.button]))
        )
        guard case .admitted(let admittedTarget) = brains.navigation.elementInflation.admitSemanticTarget(
            sourceTarget,
            selectedElement: fixture.targetEntry
        ) else {
            return XCTFail("Expected later owner target to admit")
        }

        let unavailableResult = await brains.navigation.scanForSemanticTarget(.init(
            target: admittedTarget,
            revealRootScrollViewID: ObjectIdentifier(fixture.ownerScrollView),
            deadline: semanticRevealDeadline(),
            observedScrollContentActivationPoint: fixture.observedPoint
        ))

        guard case .unavailable = unavailableResult else {
            return XCTFail("Expected absent owner request to remain unavailable, got \(unavailableResult)")
        }
        XCTAssertTrue(fixture.ownerScrollView.requestedContentOffsets.isEmpty)
        XCTAssertTrue(fixture.decoyScrollView.requestedContentOffsets.isEmpty)

        installSyntheticObservation(fixture.matchingObservation)
        fixture.ownerScrollView.onSetContentOffset = { _ in
            self.visibleObservationSource.observation = fixture.revealedObservation
        }

        let result = await brains.navigation.scanForSemanticTarget(.init(
            target: admittedTarget,
            revealRootScrollViewID: ObjectIdentifier(fixture.ownerScrollView),
            deadline: semanticRevealDeadline(),
            observedScrollContentActivationPoint: fixture.observedPoint
        ))

        guard case .revealed(let currentElement, let exploration) = result else {
            return XCTFail("Expected restored owner to consume the seed, got \(result)")
        }
        XCTAssertEqual(currentElement.heistId, fixture.targetEntry.heistId)
        XCTAssertEqual(exploration.progress.scrollCount, 0)
        XCTAssertEqual(fixture.ownerScrollView.setContentOffsetAnimations, [false])
        XCTAssertEqual(fixture.ownerScrollView.requestedContentOffsets.count, 1)
        XCTAssertEqual(fixture.ownerScrollView.requestedContentOffsets[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(fixture.ownerScrollView.requestedContentOffsets[0].y, 1_000, accuracy: 0.01)
        XCTAssertTrue(fixture.decoyScrollView.requestedContentOffsets.isEmpty)
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

    private struct SiblingOwnerMismatchFixture {
        let rootView: UIView
        let ancestorScrollView: RecordingScrollView
        let siblingScrollView: RecordingScrollView
        let storedInnerPoint: CGPoint
        let targetEntry: InterfaceTree.Element
        let initialObservation: InterfaceObservation
        let revealedObservation: InterfaceObservation
    }

    private func siblingOwnerMismatchFixture() -> SiblingOwnerMismatchFixture {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let ancestorScrollView = RecordingScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        ancestorScrollView.contentSize = CGSize(width: 320, height: 1_200)
        let siblingScrollView = RecordingScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 300)
        )
        siblingScrollView.contentSize = CGSize(width: 320, height: 1_800)
        ancestorScrollView.addSubview(siblingScrollView)
        rootView.addSubview(ancestorScrollView)

        let ancestorPath = TreePath([0])
        let siblingPath = ancestorPath.appending(0)
        let storedOwnerPath = ancestorPath.appending(1)
        let storedInnerPoint = CGPoint(x: 160, y: 1_300)
        let ancestorContainer = makeScrollableContainer(
            contentSize: ancestorScrollView.contentSize,
            frame: ancestorScrollView.frame
        )
        let siblingContainer = makeScrollableContainer(
            contentSize: siblingScrollView.contentSize,
            frame: siblingScrollView.frame
        )
        let targetElement = makeElement(label: "Sibling Target", traits: .button)
        let targetEntry = InterfaceTree.Element(
            heistId: "sibling_target",
            scrollMembership: .init(containerPath: siblingPath, index: nil),
            observedScrollContentActivationPoint: observedContentActivationPoint(
                storedInnerPoint,
                ownerPath: storedOwnerPath
            ),
            element: targetElement
        )
        let containerRefs: [TreePath: LiveCapture.ContainerRef] = [
            ancestorPath: .init(object: ancestorScrollView),
            siblingPath: .init(object: siblingScrollView),
        ]
        let containerMemberships: [TreePath: InterfaceTree.ScrollMembership] = [
            siblingPath: .init(containerPath: ancestorPath, index: nil),
        ]
        let scrollableViews: [TreePath: LiveCapture.ScrollableViewRef] = [
            ancestorPath: .init(view: ancestorScrollView),
            siblingPath: .init(view: siblingScrollView),
        ]
        let initialObservation = InterfaceObservation.makeForTests(
            elements: [targetEntry.heistId: targetEntry],
            hierarchy: [
                .container(ancestorContainer, children: [
                    .container(siblingContainer, children: []),
                ]),
            ],
            containerRefsByPath: containerRefs,
            containerScrollMembershipsByPath: containerMemberships,
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: scrollableViews
        )
        let revealedEntry = InterfaceTree.Element(
            heistId: targetEntry.heistId,
            scrollMembership: .init(containerPath: siblingPath, index: nil),
            element: targetElement
        )
        let revealedObservation = InterfaceObservation.makeForTests(
            elements: [revealedEntry.heistId: revealedEntry],
            hierarchy: [
                .container(ancestorContainer, children: [
                    .container(siblingContainer, children: [
                        .element(targetElement, traversalIndex: 0),
                    ]),
                ]),
            ],
            heistIdsByPath: [siblingPath.appending(0): revealedEntry.heistId],
            elementRefs: [
                revealedEntry.heistId: .init(
                    object: retainedLiveObject(),
                    scrollView: siblingScrollView
                ),
            ],
            containerRefsByPath: containerRefs,
            containerScrollMembershipsByPath: containerMemberships,
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: scrollableViews
        )
        return SiblingOwnerMismatchFixture(
            rootView: rootView,
            ancestorScrollView: ancestorScrollView,
            siblingScrollView: siblingScrollView,
            storedInnerPoint: storedInnerPoint,
            targetEntry: targetEntry,
            initialObservation: initialObservation,
            revealedObservation: revealedObservation
        )
    }

    private struct LaterOwnerMatchFixture {
        let ownerScrollView: RecordingScrollView
        let decoyScrollView: RecordingScrollView
        let observedPoint: InterfaceTree.ObservedScrollContentActivationPoint
        let targetEntry: InterfaceTree.Element
        let unavailableObservation: InterfaceObservation
        let matchingObservation: InterfaceObservation
        let revealedObservation: InterfaceObservation
    }

    private func laterOwnerMatchFixture() -> LaterOwnerMatchFixture {
        let ownerPath = TreePath([0])
        let decoyPath = TreePath([1])
        let ownerScrollView = RecordingScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        ownerScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let decoyScrollView = RecordingScrollView(
            frame: CGRect(x: 0, y: 420, width: 320, height: 400)
        )
        decoyScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let ownerContainer = makeScrollableContainer(
            contentSize: ownerScrollView.contentSize,
            frame: ownerScrollView.frame
        )
        let decoyContainer = makeScrollableContainer(
            contentSize: decoyScrollView.contentSize,
            frame: decoyScrollView.frame
        )
        let targetId: HeistId = "later_owner_target"
        let targetElement = makeElement(label: "Later Owner Target", traits: .button)
        let observedPoint = observedContentActivationPoint(
            CGPoint(x: 160, y: 1_200),
            ownerPath: ownerPath
        )
        let targetEntry = InterfaceTree.Element(
            heistId: targetId,
            scrollMembership: .init(containerPath: ownerPath, index: nil),
            observedScrollContentActivationPoint: observedPoint,
            element: targetElement
        )
        let unavailableObservation = InterfaceObservation.makeForTests(
            elements: [targetId: targetEntry],
            hierarchy: [
                .container(ownerContainer, children: []),
                .container(decoyContainer, children: []),
            ],
            firstResponderHeistId: nil
        )
        let containerRefs: [TreePath: LiveCapture.ContainerRef] = [
            ownerPath: .init(object: ownerScrollView),
            decoyPath: .init(object: decoyScrollView),
        ]
        let scrollableViews: [TreePath: LiveCapture.ScrollableViewRef] = [
            ownerPath: .init(view: ownerScrollView),
            decoyPath: .init(view: decoyScrollView),
        ]
        let matchingObservation = InterfaceObservation.makeForTests(
            elements: [targetId: targetEntry],
            hierarchy: [
                .container(ownerContainer, children: []),
                .container(decoyContainer, children: []),
            ],
            containerRefsByPath: containerRefs,
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: scrollableViews
        )
        let visibleEntry = InterfaceTree.Element(
            heistId: targetId,
            scrollMembership: .init(containerPath: ownerPath, index: nil),
            element: targetElement
        )
        let revealedObservation = InterfaceObservation.makeForTests(
            elements: [targetId: visibleEntry],
            hierarchy: [
                .container(ownerContainer, children: [
                    .element(targetElement, traversalIndex: 0),
                ]),
                .container(decoyContainer, children: []),
            ],
            heistIdsByPath: [ownerPath.appending(0): targetId],
            elementRefs: [
                targetId: .init(object: retainedLiveObject(), scrollView: ownerScrollView),
            ],
            containerRefsByPath: containerRefs,
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: scrollableViews
        )
        return LaterOwnerMatchFixture(
            ownerScrollView: ownerScrollView,
            decoyScrollView: decoyScrollView,
            observedPoint: observedPoint,
            targetEntry: targetEntry,
            unavailableObservation: unavailableObservation,
            matchingObservation: matchingObservation,
            revealedObservation: revealedObservation
        )
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
