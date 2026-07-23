#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    private enum TraversalOutcome: Equatable {
        case goalSatisfied
        case exhausted
        case interrupted
    }

    private struct ObservedViewport {
        let event: Observation.SnapshotEvent
        let decision: ViewportExplorationDecision

        var continuity: ScreenContinuity { event.continuity }
    }

    private enum OriginRestoreOutcome {
        case observed(ObservedViewport)
        case unchanged
        case unavailable
        case interrupted
    }

    private struct ActiveContainerExploration {
        let semantic: ContainerExploration
        let scrollViewID: ObjectIdentifier

        var semanticContainer: InterfaceTree.Container { semantic.semanticContainer }
        var savedVisualOrigin: CGPoint { semantic.savedVisualOrigin }
        var hasHOverflow: Bool { semantic.hasHOverflow }
        var hasVOverflow: Bool { semantic.hasVOverflow }
        var path: TreePath { semantic.path }
    }

    private struct PendingContainer {
        let container: InterfaceTree.Container
        let overflow: CGFloat
    }

    private struct ViewportExplorationState {
        var latestEvent: Observation.SnapshotEvent?
        var didMoveViewport = false
        var exploredScrollViewIDs = Set<ObjectIdentifier>()
        var originByScrollViewID: [ObjectIdentifier: CGPoint] = [:]
        var originOrder: [ObjectIdentifier] = []

        mutating func resetLiveViewportMemory() {
            exploredScrollViewIDs.removeAll()
            originByScrollViewID.removeAll()
            originOrder.removeAll()
        }

        mutating func recordOrigin(
            _ origin: CGPoint,
            scrollViewID: ObjectIdentifier
        ) {
            guard originByScrollViewID[scrollViewID] == nil else { return }
            originByScrollViewID[scrollViewID] = origin
            originOrder.append(scrollViewID)
        }
    }

    @MainActor
    final class ViewportExplorer {
        private let navigation: Navigation
        private let revealRootScrollViewID: ObjectIdentifier?
        private let searchOrder: ViewportSearchOrder
        private var exploration: SemanticExploration
        private var state = ViewportExplorationState()

        init(
            navigation: Navigation,
            exploration: SemanticExploration,
            searchOrder: ViewportSearchOrder,
            revealRootScrollViewID: ObjectIdentifier? = nil,
        ) {
            self.navigation = navigation
            self.exploration = exploration
            self.searchOrder = searchOrder
            self.revealRootScrollViewID = revealRootScrollViewID
        }

        func exploreViewports(
            exitPosition: ViewportExitPosition,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> InterfaceExplorationResult? {
            let startTime = CACurrentMediaTime()
            let outcome: TraversalOutcome

            if let initial = await observe(onObservation: onObservation) {
                if initial.decision == .goalSatisfied {
                    exploration.progress.clearPendingContainers()
                    outcome = .goalSatisfied
                } else {
                    outcome = await scanPendingContainers(
                        onObservation: onObservation
                    )
                }
            } else {
                outcome = .interrupted
            }

            let didFinalize = await finalize(
                exitPosition: exitPosition,
                notifyObservation: outcome != .goalSatisfied,
                onObservation: onObservation
            )
            guard didFinalize, outcome != .interrupted, let latestEvent = state.latestEvent else { return nil }
            return exploration.finish(
                startTime: startTime,
                event: latestEvent,
                didMoveViewport: state.didMoveViewport
            )
        }

        private func scanPendingContainers(
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> TraversalOutcome {
            while !exploration.progress.pendingScrollPaths.isEmpty {
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return .interrupted }
                guard exploration.progress.scrollCount < exploration.progress.maxScrollsPerDiscovery else {
                    exploration.progress.markLimitHit(.discoveryScrollLimit)
                    return .exhausted
                }

                let batch = sortedPendingContainers()
                guard !batch.isEmpty else {
                    exploration.progress.clearPendingContainers()
                    return .exhausted
                }

                containerBatch: for container in batch {
                    guard !Task.isCancelled, exploration.hasTimeRemaining else { return .interrupted }
                    guard exploration.progress.scrollCount < exploration.progress.maxScrollsPerDiscovery else {
                        exploration.progress.markLimitHit(.discoveryScrollLimit)
                        return .exhausted
                    }
                    guard let containerExploration = prepareContainerExploration(for: container) else {
                        exploration.markExplored(container)
                        continue
                    }
                    recordOrigin(of: containerExploration)

                    let outcome = await scanContainer(
                        containerExploration,
                        onObservation: onObservation
                    )
                    switch outcome {
                    case .goalSatisfied:
                        markExplored(containerExploration)
                        return .goalSatisfied
                    case .exhausted:
                        markExplored(containerExploration)
                    case .screenReplaced:
                        break containerBatch
                    case .limitHit(let reason):
                        exploration.progress.markOmitted(containerExploration.path, reason: reason)
                    case .interrupted:
                        return .interrupted
                    }
                }
            }
            return .exhausted
        }

        private func sortedPendingContainers() -> [InterfaceTree.Container] {
            var admittedScrollViewIDs = state.exploredScrollViewIDs
            let liveTargetsByPath = Dictionary(uniqueKeysWithValues: currentLiveScrollableTargets().map {
                ($0.path, $0)
            })
            return exploration.progress.pendingScrollPaths
                .sorted()
                .compactMap { navigation.vault.latestObservation.tree.containers[$0] }
                .compactMap { container -> PendingContainer? in
                    guard let liveTarget = liveTargetsByPath[container.path],
                          admittedScrollViewIDs.insert(liveTarget.scrollViewID).inserted else { return nil }
                    return PendingContainer(
                        container: container,
                        overflow: totalOverflow(of: container.container)
                    )
                }
                .sorted {
                    $0.overflow == $1.overflow
                        ? $0.container.path < $1.container.path
                        : $0.overflow > $1.overflow
                }
                .map(\.container)
        }

        private func prepareContainerExploration(
            for semanticContainer: InterfaceTree.Container
        ) -> ActiveContainerExploration? {
            let container = semanticContainer.container
            guard let contentSize = container.scrollableContentSize else { return nil }
            guard let target = currentProgrammaticScrollTarget(for: semanticContainer.path),
                  case .uiScrollView(_, let scrollView) = target else { return nil }
            guard !state.exploredScrollViewIDs.contains(ObjectIdentifier(scrollView)),
                  scrollView.window != nil,
                  !scrollView.bhIsUnsafeForProgrammaticScrolling,
                  !Navigation.isObscuredByPresentation(view: scrollView) else { return nil }

            let savedVisualOrigin = Navigation.visualOrigin(in: scrollView)

            let hasHOverflow = contentSize.width > container.frame.width + 1
            let hasVOverflow = contentSize.height > container.frame.height + 1
            guard hasHOverflow || hasVOverflow else { return nil }

            return ActiveContainerExploration(
                semantic: ContainerExploration(
                    semanticContainer: semanticContainer,
                    savedVisualOrigin: savedVisualOrigin,
                    hasHOverflow: hasHOverflow,
                    hasVOverflow: hasVOverflow
                ),
                scrollViewID: ObjectIdentifier(scrollView)
            )
        }

        private func scanContainer(
            _ container: ActiveContainerExploration,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> ScrollScanOutcome {
            for (index, direction) in searchOrder.directions.enumerated() {
                let outcome = await runScrollScan(
                    container,
                    direction: direction,
                    onObservation: onObservation
                )
                guard outcome == .exhausted else { return outcome }

                guard index == 0 else { return .exhausted }
                switch await restoreOrigin(of: container, onObservation: onObservation) {
                case .observed(let observation):
                    if observation.decision == .goalSatisfied { return .goalSatisfied }
                    if observation.continuity.isReplacement { return .screenReplaced }
                case .unchanged:
                    break
                case .unavailable, .interrupted:
                    return .interrupted
                }
            }
            return .exhausted
        }

        private func runScrollScan(
            _ container: ActiveContainerExploration,
            direction: ScrollScanDirection,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> ScrollScanOutcome {
            while exploration.hasTimeRemaining {
                guard !Task.isCancelled else { return .interrupted }
                if let reason = exploration.progress.recordScrollAttempt(in: container.path) {
                    return .limitHit(reason)
                }
                guard let target = currentProgrammaticScrollTarget(for: container) else { return .exhausted }

                await navigation.tripwire.yieldFrames(1)
                let transition = await navigation.performViewportTransition(
                    .page(
                        target,
                        direction: pageDirection(for: container, scanDirection: direction),
                        animated: false
                    ),
                    deadline: exploration.deadline,
                    discoveryCommitPolicy: exploration.discoveryCommitPolicy
                )
                switch transition.outcome {
                case .unchanged, .unavailable:
                    return .exhausted
                case .moved:
                    state.didMoveViewport = true
                }
                guard let event = transition.event else { return .interrupted }
                let observation = await record(event, notifyObservation: true, onObservation: onObservation)
                if observation.decision == .goalSatisfied { return .goalSatisfied }
                if observation.continuity.isReplacement { return .screenReplaced }
                if let nestedOutcome = await scanNewlyVisibleNestedContainers(
                    inside: container,
                    onObservation: onObservation
                ) {
                    return nestedOutcome
                }
            }
            return .interrupted
        }

        private func scanNewlyVisibleNestedContainers(
            inside parent: ActiveContainerExploration,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> ScrollScanOutcome? {
            guard let parentTarget = currentLiveScrollableTarget(for: parent.scrollViewID) else {
                return .interrupted
            }
            let nestedContainers = sortedPendingContainers().filter {
                guard currentProgrammaticScrollTarget(for: $0.path) != nil else { return false }
                return navigation.vault.isDirectLiveScrollChild(
                    at: $0.path,
                    of: parentTarget.scrollView
                )
            }
            for semanticContainer in nestedContainers {
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return .interrupted }
                guard let nested = prepareContainerExploration(for: semanticContainer) else {
                    exploration.markExplored(semanticContainer)
                    continue
                }
                recordOrigin(of: nested)
                let outcome = await scanContainer(
                    nested,
                    onObservation: onObservation
                )
                switch outcome {
                case .goalSatisfied:
                    markExplored(nested)
                    return outcome
                case .exhausted:
                    markExplored(nested)
                case .screenReplaced, .interrupted:
                    return outcome
                case .limitHit(let reason):
                    exploration.progress.markOmitted(nested.path, reason: reason)
                    if reason == .discoveryScrollLimit { return outcome }
                }
            }
            return nil
        }

        private func pageDirection(
            for container: ActiveContainerExploration,
            scanDirection: ScrollScanDirection
        ) -> UIAccessibilityScrollDirection {
            switch (container.hasVOverflow, scanDirection) {
            case (true, .forward):
                .down
            case (true, .back):
                .up
            case (false, .forward):
                .right
            case (false, .back):
                .left
            }
        }

        private func observe(
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> ObservedViewport? {
            guard let event = await navigation.settledExplorationPage(
                deadline: exploration.deadline,
                discoveryCommitPolicy: exploration.discoveryCommitPolicy
            ) else { return nil }
            return await record(event, notifyObservation: true, onObservation: onObservation)
        }

        private func record(
            _ event: Observation.SnapshotEvent,
            notifyObservation: Bool,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> ObservedViewport {
            state.latestEvent = event
            if event.continuity.isReplacement {
                state.resetLiveViewportMemory()
            }
            exploration.recordCommittedObservation(
                continuity: event.continuity,
                scrollableContainers: currentScrollableContainers()
            )
            return ObservedViewport(
                event: event,
                decision: notifyObservation ? await onObservation(event) : .continue
            )
        }

        private func finalize(
            exitPosition: ViewportExitPosition,
            notifyObservation: Bool,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> Bool {
            guard exitPosition == .origin else { return true }
            let restorationDeadline = exploration.hasTimeRemaining
                ? exploration.deadline
                : SemanticObservationDeadline(
                    start: RuntimeElapsed.now,
                    timeoutMs: SettleSession.viewportTransitionTimeoutMs
                )
            for scrollViewID in state.originOrder.reversed() {
                guard let origin = state.originByScrollViewID[scrollViewID] else { continue }
                switch await restoreOrigin(
                    origin,
                    scrollViewID: scrollViewID,
                    deadline: restorationDeadline,
                    notifyObservation: notifyObservation,
                    onObservation: onObservation
                ) {
                case .observed, .unchanged:
                    continue
                case .unavailable, .interrupted:
                    return false
                }
            }
            return true
        }

        private func restoreOrigin(
            of container: ActiveContainerExploration,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> OriginRestoreOutcome {
            await restoreOrigin(
                container.savedVisualOrigin,
                scrollViewID: container.scrollViewID,
                onObservation: onObservation
            )
        }

        private func restoreOrigin(
            _ origin: CGPoint,
            scrollViewID: ObjectIdentifier,
            deadline: SemanticObservationDeadline? = nil,
            notifyObservation: Bool = true,
            onObservation: (Observation.SnapshotEvent) async -> ViewportExplorationDecision
        ) async -> OriginRestoreOutcome {
            guard let target = currentProgrammaticScrollTarget(for: scrollViewID),
                  case .uiScrollView = target else {
                return .unavailable
            }
            let transition = await navigation.performViewportTransition(
                .restoreVisualOrigin(origin, in: target),
                deadline: deadline ?? exploration.deadline,
                discoveryCommitPolicy: exploration.discoveryCommitPolicy
            )
            switch transition.outcome {
            case .unavailable:
                return .unavailable
            case .unchanged:
                return .unchanged
            case .moved:
                state.didMoveViewport = true
                guard let event = transition.event else { return .interrupted }
                return .observed(await record(
                    event,
                    notifyObservation: notifyObservation,
                    onObservation: onObservation
                ))
            }
        }

        private func currentProgrammaticScrollTarget(
            for container: ActiveContainerExploration
        ) -> ScrollableTarget? {
            if let exactTarget = currentProgrammaticScrollTarget(for: container.path),
               case .uiScrollView(_, let scrollView) = exactTarget,
               ObjectIdentifier(scrollView) == container.scrollViewID {
                return exactTarget
            }
            return currentProgrammaticScrollTarget(for: container.scrollViewID)
        }

        private func currentProgrammaticScrollTarget(
            for scrollViewID: ObjectIdentifier
        ) -> ScrollableTarget? {
            currentLiveScrollableTarget(for: scrollViewID).map(Self.scrollableTarget)
        }

        private func currentProgrammaticScrollTarget(for path: TreePath) -> ScrollableTarget? {
            guard let target = navigation.vault.liveScrollTarget(at: path),
                  !target.scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
            return Self.scrollableTarget(target)
        }

        private func currentLiveScrollableTargets() -> [TheVault.LiveScrollTarget] {
            navigation.vault.liveProgrammaticScrollTargets(
                descendedFrom: revealRootScrollViewID
            )
        }

        private func currentLiveScrollableTarget(
            for scrollViewID: ObjectIdentifier
        ) -> TheVault.LiveScrollTarget? {
            currentLiveScrollableTargets().first { $0.scrollViewID == scrollViewID }
        }

        private func currentScrollableContainers() -> [InterfaceTree.Container] {
            currentLiveScrollableTargets().compactMap { target in
                navigation.vault.latestObservation.tree.containers[target.path]
            }
        }

        private static func scrollableTarget(_ target: TheVault.LiveScrollTarget) -> ScrollableTarget {
            .uiScrollView(container: target.container, scrollView: target.scrollView)
        }

        private func markExplored(_ container: ActiveContainerExploration) {
            state.exploredScrollViewIDs.insert(container.scrollViewID)
            exploration.markExplored(container.semanticContainer)
        }

        private func recordOrigin(of container: ActiveContainerExploration) {
            state.recordOrigin(
                container.savedVisualOrigin,
                scrollViewID: container.scrollViewID
            )
        }

        private func totalOverflow(of container: AccessibilityContainer) -> CGFloat {
            guard let contentSize = container.scrollableContentSize else { return 0 }
            return max(0, contentSize.width - container.frame.width)
                + max(0, contentSize.height - container.frame.height)
        }

    }

    private enum SemanticTargetScanMatch {
        case visible(InterfaceTree.Element)
        case offscreen
        case failed(ElementInflation.SemanticTargetResolutionFailure)
    }

    func scanForSemanticTarget(
        _ request: ElementInflation.SemanticTargetRevealRequest
    ) async -> ElementInflation.SemanticTargetScanResult {
        var visibleTarget: InterfaceTree.Element?
        var resolutionFailure: ElementInflation.SemanticTargetResolutionFailure?
        let searchOrder: ViewportSearchOrder = request.observedScrollContentActivationPoint == nil
            ? .backwardFirst
            : .forwardFirst
        if let observedPoint = request.observedScrollContentActivationPoint {
            if let seededResult = await moveToFallbackSeed(observedPoint, request: request) {
                return seededResult
            }
        }
        let explorer = ViewportExplorer(
            navigation: self,
            exploration: SemanticExploration(
                baseline: .interfaceMemory(vault.interfaceMemoryBaseline()),
                deadline: request.deadline
            ),
            searchOrder: searchOrder,
            revealRootScrollViewID: request.revealRootScrollViewID,
        )
        let explored = await explorer.exploreViewports(exitPosition: .current) { _ in
            switch self.semanticTargetScanMatch(request.target) {
            case .visible(let current):
                visibleTarget = current
                return .goalSatisfied
            case .failed(let failure):
                resolutionFailure = failure
                return .goalSatisfied
            case .offscreen:
                return .continue
            }
        }
        if let resolutionFailure {
            return .failed(resolutionFailure)
        }
        guard let visibleTarget, let explored else { return .unavailable }
        return .revealed(visibleTarget, explored)
    }

    private func moveToFallbackSeed(
        _ observedPoint: InterfaceTree.ObservedScrollContentActivationPoint,
        request: ElementInflation.SemanticTargetRevealRequest
    ) async -> ElementInflation.SemanticTargetScanResult? {
        guard let ownerPath = request.target.scrollContainerPath,
              let point = observedPoint.admit(ownerPath: ownerPath),
              let target = vault.liveScrollTarget(at: ownerPath),
              !target.scrollView.bhIsUnsafeForProgrammaticScrolling
        else { return nil }
        let transition = await performViewportTransition(
            .revealContentPoint(
                point,
                in: .uiScrollView(container: target.container, scrollView: target.scrollView)
            ),
            deadline: request.deadline
        )
        guard transition.outcome.didMove,
              let event = transition.event
        else { return nil }
        let exploration = InterfaceExplorationResult(
            event: event,
            progress: .init(),
            didMoveViewport: true
        )
        switch semanticTargetScanMatch(request.target) {
        case .visible(let current):
            return .revealed(current, exploration)
        case .failed(let failure):
            return .failed(failure)
        case .offscreen:
            return nil
        }
    }

    private func semanticTargetScanMatch(
        _ target: ElementInflation.AdmittedSemanticTarget
    ) -> SemanticTargetScanMatch {
        switch vault.resolveTarget(target.target) {
        case .resolved(.element(let current)):
            return vault.visibleLiveElementAliasing(current) == nil
                ? .offscreen
                : .visible(current)
        case .resolved(.container):
            return .failed(.containerTarget)
        case .notFound(let facts):
            return .failed(.notFound(
                TargetResolutionDiagnostics.message(for: .notFound(facts))
            ))
        case .ambiguous(let facts):
            return .failed(.ambiguous(
                TargetResolutionDiagnostics.message(for: .ambiguous(facts))
            ))
        }
    }

    static func visualOrigin(in scrollView: UIScrollView) -> CGPoint {
        CGPoint(
            x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
            y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        )
    }

    static func hasContentBeyondFrame(
        of container: AccessibilityContainer,
        in hierarchy: [AccessibilityHierarchy],
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let path = hierarchy.pathIndexedContainers.first(where: { $0.container == container })?.path else {
            return false
        }
        return hasDescendantBeyondFrame(of: path, in: hierarchy, tolerance: tolerance)
    }

    private static func hasDescendantBeyondFrame(
        of containerPath: TreePath,
        in hierarchy: [AccessibilityHierarchy],
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let subtree = hierarchy.node(at: containerPath),
              case .container(let container, _) = subtree
        else {
            return false
        }
        let containerFrame = container.frame
        let hits: [Bool] = subtree.compactMapSubtrees(path: containerPath) { node, path -> Bool? in
            guard path != containerPath,
                  case .element(let element, _) = node
            else {
                return nil
            }
            let elementFrame = element.shape.frame
            let extendsBeyond =
                elementFrame.minX < containerFrame.minX - tolerance
                || elementFrame.minY < containerFrame.minY - tolerance
                || elementFrame.maxX > containerFrame.maxX + tolerance
                || elementFrame.maxY > containerFrame.maxY + tolerance
            return extendsBeyond ? true : nil
        }
        return !hits.isEmpty
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
