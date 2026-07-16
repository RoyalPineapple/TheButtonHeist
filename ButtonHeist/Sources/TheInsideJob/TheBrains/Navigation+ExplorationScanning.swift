#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

extension Navigation {

    private enum TraversalResult: Equatable {
        case finished
        case completed
        case interrupted
    }

    private struct ObservedViewport {
        let event: SettledSemanticObservationEvent
        let decision: ViewportExplorationDecision

        var continuity: ScreenContinuity { event.continuity }
    }

    private enum OriginRestoreResult {
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

    private struct LiveScrollableTarget {
        let path: TreePath
        let target: ScrollableTarget
        let scrollViewID: ObjectIdentifier
    }

    private struct PendingContainer {
        let container: InterfaceTree.Container
        let overflow: CGFloat
    }

    @MainActor
    final class ViewportExplorer {
        private let navigation: Navigation
        private let revealRootScrollViewID: ObjectIdentifier?
        private let searchOrder: ViewportSearchOrder
        private var exploration: SemanticExploration
        private var latestEvent: SettledSemanticObservationEvent?
        private var didMoveViewport = false
        private var exploredScrollViewIDs = Set<ObjectIdentifier>()
        private var originByScrollViewID: [ObjectIdentifier: CGPoint] = [:]
        private var originOrder: [ObjectIdentifier] = []

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
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> ExploredScreen? {
            let startTime = CACurrentMediaTime()
            let result: TraversalResult

            if let initial = await observe(onObservation: onObservation) {
                if initial.decision == .finish {
                    exploration.manifest.clearPendingContainers()
                    result = .finished
                } else {
                    result = await scanPendingContainers(
                        onObservation: onObservation
                    )
                }
            } else {
                result = .interrupted
            }

            let didFinalize = await finalize(
                exitPosition: exitPosition,
                notifyObservation: result != .finished,
                onObservation: onObservation
            )
            guard didFinalize, result != .interrupted, let latestEvent else { return nil }
            return exploration.finish(
                startTime: startTime,
                event: latestEvent,
                didMoveViewport: didMoveViewport
            )
        }

        private func scanPendingContainers(
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> TraversalResult {
            while !exploration.manifest.pendingScrollPaths.isEmpty {
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return .interrupted }
                guard exploration.manifest.scrollCount < exploration.manifest.maxScrollsPerDiscovery else {
                    exploration.manifest.markDiscoveryLimitHit()
                    return .completed
                }

                let batch = sortedPendingContainers()
                guard !batch.isEmpty else {
                    exploration.manifest.clearPendingContainers()
                    return .completed
                }

                containerBatch: for container in batch {
                    guard !Task.isCancelled, exploration.hasTimeRemaining else { return .interrupted }
                    guard exploration.manifest.scrollCount < exploration.manifest.maxScrollsPerDiscovery else {
                        exploration.manifest.markDiscoveryLimitHit()
                        return .completed
                    }
                    guard let containerExploration = prepareContainerExploration(for: container) else {
                        exploration.markExplored(container)
                        continue
                    }
                    recordOrigin(of: containerExploration)

                    let result = await scanContainer(
                        containerExploration,
                        onObservation: onObservation
                    )
                    switch result {
                    case .finished:
                        markExplored(containerExploration)
                        return .finished
                    case .completed:
                        markExplored(containerExploration)
                    case .screenReplaced:
                        break containerBatch
                    case .omitted(let reason):
                        exploration.manifest.markOmitted(containerExploration.path, reason: reason)
                    case .interrupted:
                        return .interrupted
                    }
                }
            }
            return .completed
        }

        private func sortedPendingContainers() -> [InterfaceTree.Container] {
            var admittedScrollViewIDs = exploredScrollViewIDs
            let liveTargetsByPath = Dictionary(uniqueKeysWithValues: currentLiveScrollableTargets().map {
                ($0.path, $0)
            })
            return exploration.manifest.pendingScrollPaths
                .sorted()
                .compactMap { navigation.stash.latestObservation.tree.containers[$0] }
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
            guard !exploredScrollViewIDs.contains(ObjectIdentifier(scrollView)),
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
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> ScrollContainerScanResult {
            for (index, direction) in searchOrder.directions.enumerated() {
                switch await runScrollScan(
                    container,
                    direction: direction,
                    onObservation: onObservation
                ) {
                case .finished:
                    return .finished
                case .screenReplaced:
                    return .screenReplaced
                case .limitHit(let reason):
                    return .omitted(reason)
                case .interrupted:
                    return .interrupted
                case .exhausted:
                    break
                }

                guard index == 0 else { return .completed }
                switch await restoreOrigin(of: container, onObservation: onObservation) {
                case .observed(let observation):
                    if observation.decision == .finish { return .finished }
                    if observation.continuity.isReplacement { return .screenReplaced }
                case .unchanged:
                    break
                case .unavailable, .interrupted:
                    return .interrupted
                }
            }
            return .completed
        }

        private func runScrollScan(
            _ container: ActiveContainerExploration,
            direction: ScrollScanDirection,
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> ScrollScanOutcome {
            while true {
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return .interrupted }
                if let reason = exploration.manifest.recordScrollAttempt(in: container.path) {
                    return .limitHit(reason)
                }
                guard let target = currentProgrammaticScrollTarget(for: container) else { return .exhausted }

                let transition = await navigation.performViewportTransition(
                    .page(
                        target,
                        direction: pageDirection(for: container, scanDirection: direction),
                        animated: false
                    ),
                    deadline: exploration.deadline,
                    discoveryCommitPolicy: exploration.discoveryCommitPolicy
                )
                switch transition.result {
                case .unchanged, .unavailable:
                    return .exhausted
                case .moved:
                    didMoveViewport = true
                }
                guard let event = transition.event else { return .interrupted }
                let observation = record(event, notifyObservation: true, onObservation: onObservation)
                if observation.decision == .finish { return .finished }
                if observation.continuity.isReplacement { return .screenReplaced }
                if let nestedOutcome = await scanNewlyVisibleNestedContainers(
                    inside: container,
                    onObservation: onObservation
                ) {
                    return nestedOutcome
                }
            }
        }

        private func scanNewlyVisibleNestedContainers(
            inside parent: ActiveContainerExploration,
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> ScrollScanOutcome? {
            guard let parentTarget = currentLiveScrollableTarget(for: parent.scrollViewID),
                  case .uiScrollView(_, let parentScrollView) = parentTarget.target else {
                return .interrupted
            }
            let nestedContainers = sortedPendingContainers().filter {
                guard let target = currentProgrammaticScrollTarget(for: $0.path),
                      case .uiScrollView(_, let scrollView) = target else { return false }
                return nearestScrollableSuperview(of: scrollView) === parentScrollView
            }
            for semanticContainer in nestedContainers {
                guard !Task.isCancelled, exploration.hasTimeRemaining else { return .interrupted }
                guard let nested = prepareContainerExploration(for: semanticContainer) else {
                    exploration.markExplored(semanticContainer)
                    continue
                }
                recordOrigin(of: nested)
                let result = await scanContainer(
                    nested,
                    onObservation: onObservation
                )
                switch result {
                case .finished:
                    markExplored(nested)
                    return .finished
                case .completed:
                    markExplored(nested)
                case .screenReplaced:
                    return .screenReplaced
                case .omitted(let reason):
                    exploration.manifest.markOmitted(nested.path, reason: reason)
                    if reason == .discoveryScrollLimit { return .limitHit(reason) }
                case .interrupted:
                    return .interrupted
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
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> ObservedViewport? {
            guard let event = await navigation.settledExplorationPage(
                deadline: exploration.deadline,
                discoveryCommitPolicy: exploration.discoveryCommitPolicy
            ) else { return nil }
            return record(event, notifyObservation: true, onObservation: onObservation)
        }

        private func record(
            _ event: SettledSemanticObservationEvent,
            notifyObservation: Bool,
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) -> ObservedViewport {
            latestEvent = event
            if event.continuity.isReplacement {
                exploredScrollViewIDs.removeAll()
                originByScrollViewID.removeAll()
                originOrder.removeAll()
            }
            exploration.recordCommittedObservation(
                continuity: event.continuity,
                scrollableContainers: currentScrollableContainers()
            )
            return ObservedViewport(
                event: event,
                decision: notifyObservation ? onObservation(event) : .continue
            )
        }

        private func finalize(
            exitPosition: ViewportExitPosition,
            notifyObservation: Bool,
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> Bool {
            guard exitPosition == .origin else { return true }
            for scrollViewID in originOrder.reversed() {
                guard let origin = originByScrollViewID[scrollViewID] else { continue }
                switch await restoreOrigin(
                    origin,
                    scrollViewID: scrollViewID,
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
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> OriginRestoreResult {
            await restoreOrigin(
                container.savedVisualOrigin,
                scrollViewID: container.scrollViewID,
                onObservation: onObservation
            )
        }

        private func restoreOrigin(
            _ origin: CGPoint,
            scrollViewID: ObjectIdentifier,
            notifyObservation: Bool = true,
            onObservation: (SettledSemanticObservationEvent) -> ViewportExplorationDecision
        ) async -> OriginRestoreResult {
            guard let target = currentProgrammaticScrollTarget(for: scrollViewID),
                  case .uiScrollView = target else {
                return .unavailable
            }
            let transition = await navigation.performViewportTransition(
                .restoreVisualOrigin(origin, in: target),
                deadline: exploration.deadline,
                discoveryCommitPolicy: exploration.discoveryCommitPolicy
            )
            switch transition.result {
            case .unavailable:
                return .unavailable
            case .unchanged:
                return .unchanged
            case .moved:
                didMoveViewport = true
                guard let event = transition.event else { return .interrupted }
                return .observed(record(
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
            currentLiveScrollableTarget(for: scrollViewID)?.target
        }

        private func currentProgrammaticScrollTarget(for path: TreePath) -> ScrollableTarget? {
            guard let semanticContainer = navigation.stash.latestObservation.tree.containers[path]
                    ?? navigation.stash.interfaceTree.containers[path],
                  case .resolved(let liveContainer) = navigation.stash.resolveLiveContainerTarget(
                      for: semanticContainer
                  ),
                  let scrollView = navigation.stash.liveScrollableContainerView(forPath: path),
                  !scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
            return .uiScrollView(
                container: liveContainer,
                scrollView: scrollView
            )
        }

        private func currentLiveScrollableTargets() -> [LiveScrollableTarget] {
            let containers = navigation.stash.latestObservation.tree.orderedContainers
            var targetByScrollViewID: [ObjectIdentifier: LiveScrollableTarget] = [:]
            for container in containers {
                guard let target = currentProgrammaticScrollTarget(for: container.path),
                      case .uiScrollView(_, let scrollView) = target else { continue }
                let candidate = LiveScrollableTarget(
                    path: container.path,
                    target: target,
                    scrollViewID: ObjectIdentifier(scrollView)
                )
                if let current = targetByScrollViewID[candidate.scrollViewID],
                   current.path <= candidate.path {
                    continue
                }
                targetByScrollViewID[candidate.scrollViewID] = candidate
            }
            let liveTargets = targetByScrollViewID.values.sorted { $0.path < $1.path }
            guard let revealRootScrollViewID else { return liveTargets }

            var eligibleIDs: Set<ObjectIdentifier> = [revealRootScrollViewID]
            var didAddNestedScrollView = true
            while didAddNestedScrollView {
                didAddNestedScrollView = false
                for liveTarget in liveTargets where !eligibleIDs.contains(liveTarget.scrollViewID) {
                    guard case .uiScrollView(_, let scrollView) = liveTarget.target,
                          let parent = nearestScrollableSuperview(of: scrollView),
                          eligibleIDs.contains(ObjectIdentifier(parent)) else { continue }
                    eligibleIDs.insert(liveTarget.scrollViewID)
                    didAddNestedScrollView = true
                }
            }
            return liveTargets.filter { eligibleIDs.contains($0.scrollViewID) }
        }

        private func currentLiveScrollableTarget(
            for scrollViewID: ObjectIdentifier
        ) -> LiveScrollableTarget? {
            let matches = currentLiveScrollableTargets().filter { $0.scrollViewID == scrollViewID }
            guard matches.count == 1 else { return nil }
            return matches[0]
        }

        private func currentScrollableContainers() -> [InterfaceTree.Container] {
            currentLiveScrollableTargets().compactMap { target in
                navigation.stash.latestObservation.tree.containers[target.path]
            }
        }

        private func nearestScrollableSuperview(of view: UIView) -> UIScrollView? {
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView { return scrollView }
                ancestor = current.superview
            }
            return nil
        }

        private func markExplored(_ container: ActiveContainerExploration) {
            exploredScrollViewIDs.insert(container.scrollViewID)
            exploration.markExplored(container.semanticContainer)
        }

        private func recordOrigin(of container: ActiveContainerExploration) {
            guard originByScrollViewID[container.scrollViewID] == nil else { return }
            originByScrollViewID[container.scrollViewID] = container.savedVisualOrigin
            originOrder.append(container.scrollViewID)
        }

        private func totalOverflow(of container: AccessibilityContainer) -> CGFloat {
            guard let contentSize = container.scrollableContentSize else { return 0 }
            return max(0, contentSize.width - container.frame.width)
                + max(0, contentSize.height - container.frame.height)
        }

    }

    func scanForHeistId(
        _ heistId: HeistId,
        deadline: SemanticObservationDeadline,
    ) async -> ExploredScreen? {
        guard let rootScrollViewID = revealRootScrollViewID(for: heistId) else { return nil }
        var didFindTarget = false
        let explorer = ViewportExplorer(
            navigation: self,
            exploration: SemanticExploration(
                baseline: .interfaceMemory(stash.actionDiscoveryBaseline()),
                deadline: deadline
            ),
            searchOrder: .backwardFirst,
            revealRootScrollViewID: rootScrollViewID,
        )
        let explored = await explorer.exploreViewports(exitPosition: .current) { event in
            didFindTarget = event.observation.screen.liveCapture.contains(heistId: heistId)
            return didFindTarget ? .finish : .continue
        }
        return didFindTarget ? explored : nil
    }

    private func revealRootScrollViewID(for heistId: HeistId) -> ObjectIdentifier? {
        guard let membership = stash.interfaceElement(heistId: heistId)?.scrollMembership else { return nil }
        var visitedPaths = Set<TreePath>()
        var path: TreePath? = membership.containerPath
        while let currentPath = path, visitedPaths.insert(currentPath).inserted {
            if let scrollView = liveProgrammaticScrollView(at: currentPath) {
                return ObjectIdentifier(scrollView)
            }
            guard let container = stash.interfaceTree.containers[currentPath] else { return nil }
            path = container.scrollMembership?.containerPath
        }
        return nil
    }

    private func liveProgrammaticScrollView(at path: TreePath) -> UIScrollView? {
        guard let scrollView = stash.liveScrollableContainerView(forPath: path),
              stash.liveContainerObject(forPath: path) != nil,
              stash.liveContainer(forPath: path) != nil,
              !scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
        return scrollView
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
