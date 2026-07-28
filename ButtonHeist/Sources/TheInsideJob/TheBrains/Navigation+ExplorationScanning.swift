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
        let current: TheVault.State.Current
        let decision: ViewportExplorationDecision

        var continuity: ScreenContinuity { current.continuity }
    }

    private enum OriginRestoreOutcome {
        case observed(ObservedViewport)
        case unchanged
        case unavailable
        case interrupted
    }

    @MainActor
    private final class ViewportOrigin {
        let scrollViewID: ObjectIdentifier
        let origin: CGPoint
        weak var originalScrollView: UIScrollView?

        init(scrollView: UIScrollView, origin: CGPoint) {
            scrollViewID = ObjectIdentifier(scrollView)
            self.origin = origin
            originalScrollView = scrollView
        }
    }

    @MainActor
    private struct ActiveContainerExploration {
        let semantic: ContainerExploration
        let scrollView: UIScrollView

        var semanticContainer: InterfaceTree.Container { semantic.semanticContainer }
        var savedVisualOrigin: CGPoint { semantic.savedVisualOrigin }
        var hasHOverflow: Bool { semantic.hasHOverflow }
        var hasVOverflow: Bool { semantic.hasVOverflow }
        var path: TreePath { semantic.path }
        var scrollViewID: ObjectIdentifier { ObjectIdentifier(scrollView) }
    }

    private struct PendingContainer {
        let container: InterfaceTree.Container
        let overflow: CGFloat
    }

    @MainActor
    private struct ViewportExplorationState {
        var latestCurrent: TheVault.State.Current?
        var didMoveViewport = false
        var originWasSuperseded = false
        var exploredScrollViewIDs = Set<ObjectIdentifier>()
        var origins: [ViewportOrigin] = []

        mutating func resetSemanticViewportMemory() {
            exploredScrollViewIDs.removeAll()
        }

        mutating func recordOrigin(
            scrollView: UIScrollView,
            origin: CGPoint
        ) {
            let scrollViewID = ObjectIdentifier(scrollView)
            guard !origins.contains(where: { $0.scrollViewID == scrollViewID }) else { return }
            origins.append(ViewportOrigin(scrollView: scrollView, origin: origin))
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
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
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

            // Only a found element earns its scroll position, because the caller
            // is about to act on it. A pass that ended any other way leaves the
            // screen as it found it: a discovery walked the containers to read
            // them, and a search that came back empty moved them for nothing.
            let viewportExit = await finalize(
                exitPosition: outcome == .goalSatisfied ? exitPosition : .origin,
                notifyObservation: outcome != .goalSatisfied,
                onObservation: onObservation
            )
            guard let latestCurrent = state.latestCurrent else { return nil }
            return exploration.finish(
                startTime: startTime,
                current: latestCurrent,
                didMoveViewport: state.didMoveViewport,
                viewportExit: viewportExit
            )
        }

        private func scanPendingContainers(
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
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

                for container in batch {
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
                        return .exhausted
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
                scrollView: scrollView
            )
        }

        private func scanContainer(
            _ container: ActiveContainerExploration,
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
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
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
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
                guard let current = transition.current else { return .interrupted }
                let observation = await record(
                    current,
                    notifyObservation: true,
                    onObservation: onObservation
                )
                if container.scrollView.window == nil {
                    state.originWasSuperseded = true
                }
                if observation.decision == .goalSatisfied { return .goalSatisfied }
                if state.originWasSuperseded { return .screenReplaced }
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
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
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
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
        ) async -> ObservedViewport? {
            guard let current = await navigation.settledExplorationPage(
                deadline: exploration.deadline,
                discoveryCommitPolicy: exploration.discoveryCommitPolicy
            ) else { return nil }
            return await record(
                current,
                establishesBaseline: true,
                notifyObservation: true,
                onObservation: onObservation
            )
        }

        private func record(
            _ current: TheVault.State.Current,
            establishesBaseline: Bool = false,
            notifyObservation: Bool,
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
        ) async -> ObservedViewport {
            state.latestCurrent = current
            if current.continuity.isReplacement {
                if !establishesBaseline {
                    state.originWasSuperseded = true
                }
                state.resetSemanticViewportMemory()
            }
            exploration.recordCommittedObservation(
                continuity: current.continuity,
                scrollableContainers: currentScrollableContainers()
            )
            return ObservedViewport(
                current: current,
                decision: notifyObservation ? await onObservation(current) : .continue
            )
        }

        private func finalize(
            exitPosition: ViewportExitPosition,
            notifyObservation: Bool,
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
        ) async -> ViewportExit.Outcome {
            if state.originWasSuperseded { return .superseded }
            guard exitPosition == .origin else { return .retained }
            guard !state.origins.isEmpty else { return .restored }

            let restorationDeadline = SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeout: SemanticObservationTiming.defaultTimeout
            )
            for viewportOrigin in state.origins.reversed() {
                switch await restoreOrigin(
                    viewportOrigin.origin,
                    scrollViewID: viewportOrigin.scrollViewID,
                    originalScrollView: viewportOrigin.originalScrollView,
                    deadline: restorationDeadline,
                    notifyObservation: notifyObservation,
                    onObservation: onObservation
                ) {
                case .observed(let observation):
                    if observation.continuity.isReplacement { return .superseded }
                case .unchanged:
                    continue
                case .unavailable, .interrupted:
                    return .failed(.originUnavailable)
                }
            }
            return .restored
        }

        private func restoreOrigin(
            of container: ActiveContainerExploration,
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
        ) async -> OriginRestoreOutcome {
            await restoreOrigin(
                container.savedVisualOrigin,
                scrollViewID: container.scrollViewID,
                originalScrollView: container.scrollView,
                onObservation: onObservation
            )
        }

        private func restoreOrigin(
            _ origin: CGPoint,
            scrollViewID: ObjectIdentifier,
            originalScrollView: UIScrollView?,
            deadline: SemanticObservationDeadline? = nil,
            notifyObservation: Bool = true,
            onObservation: (TheVault.State.Current) async -> ViewportExplorationDecision
        ) async -> OriginRestoreOutcome {
            let intent: ViewportMovementIntent
            if let target = currentProgrammaticScrollTarget(for: scrollViewID),
               case .uiScrollView = target {
                intent = .restoreVisualOrigin(origin, in: .semantic(target))
            } else if let originalScrollView,
                      ObjectIdentifier(originalScrollView) == scrollViewID,
                      originalScrollView.window != nil,
                      !originalScrollView.bhIsUnsafeForProgrammaticScrolling,
                      !Navigation.isObscuredByPresentation(view: originalScrollView) {
                intent = .restoreVisualOrigin(origin, in: .original(originalScrollView))
            } else {
                return .unavailable
            }
            let transition = await navigation.performViewportTransition(
                intent,
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
                guard let current = transition.current else { return .interrupted }
                return .observed(await record(
                    current,
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
            guard case .success(let target) = navigation.vault.liveScrollTarget(at: path),
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
                scrollView: container.scrollView,
                origin: container.savedVisualOrigin
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

    /// What one stored seed did for a reveal request.
    private enum StoredSeedOutcome {
        /// The seed put the target on screen.
        case revealed(InterfaceTree.Element, InterfaceExplorationResult)
        /// The target could not be resolved at all.
        case failed(ElementInflation.SemanticTargetResolutionFailure)
        /// No seed applies to where the target sits now, and nothing moved.
        case noSeed(StoredSeedRejection)
        /// The seed was spent and the target is still off screen, so the
        /// viewport is somewhere other than where the caller left it.
        case missed
    }

    /// Why a stored seed does not apply.
    ///
    /// Each of these leaves the viewport where the caller left it, so the caller
    /// sweeps either way. They are named because a seed silently declining to
    /// apply reads exactly like one that applied and found nothing.
    private enum StoredSeedRejection {
        /// The target the seed was stored for is no longer in the reading.
        case targetUnresolved
        /// The target sits outside any scroll container now.
        case targetHasNoScrollOwner
        /// The seed remembers a point in a container the target has since left.
        case seedBelongsToAnotherOwner(TreePath)
        /// The owner is in the reading and names no live scroll view.
        case ownerNotLiveScrollable(TheVault.LiveScrollTargetFailure)
        /// The owner is a scroll view Button Heist will not drive itself.
        case ownerUnsafeForProgrammaticScrolling
        /// The seed was spent and the viewport stayed where it was.
        case viewportDidNotMove
    }

    func scanForSemanticTarget(
        _ request: ElementInflation.SemanticTargetRevealRequest
    ) async -> ElementInflation.SemanticTargetScanResult {
        var visibleTarget: InterfaceTree.Element?
        var resolutionFailure: ElementInflation.SemanticTargetResolutionFailure?
        let searchOrder: ViewportSearchOrder = request.viewSpace.activationPoint == nil
            ? .backwardFirst
            : .forwardFirst
        if request.viewSpace.activationPoint != nil {
            switch await moveToStoredSeed(request.viewSpace, request: request) {
            case .revealed(let current, let exploration):
                return .revealed(current, exploration)
            case .failed(let failure):
                return .failed(failure)
            case .noSeed, .missed:
                // Both leave the sweep below as the answer; they differ in where
                // the viewport starts it from, which the sweep reads for itself.
                break
            }
        }
        let explorer = ViewportExplorer(
            navigation: self,
            exploration: SemanticExploration(
                startingFresh: false,
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

    /// Scrolls straight to where the target was last seen.
    ///
    /// A seed is one remembered content point in one scroll container, so it is
    /// spent in a single move and either puts the target on screen or does not.
    /// Sweeping every viewport is the slower answer the caller falls back on.
    private func moveToStoredSeed(
        _ viewSpace: HeistElement.Geometry.ViewSpace,
        request: ElementInflation.SemanticTargetRevealRequest
    ) async -> StoredSeedOutcome {
        // Spending the seed is a live-geometry question, so the live capture is
        // taken here rather than inherited from whenever one last happened.
        vault.refreshLiveCapture()
        // The owner is looked up where the target sits now. `scrollContainerPath`
        // names where it sat in the reading that admitted the target, and the
        // seed is spent against whatever the app has reached since; admitting
        // the seed against the current owner is what makes the two one screen.
        guard case .resolved(.element(let currentElement)) = vault.resolveTarget(request.target.target) else {
            return .noSeed(.targetUnresolved)
        }
        guard let ownerPath = currentElement.scrollContainerPath else {
            return .noSeed(.targetHasNoScrollOwner)
        }
        guard let point = viewSpace.activationPoint(ownedBy: ownerPath) else {
            return .noSeed(.seedBelongsToAnotherOwner(ownerPath))
        }
        let target: TheVault.LiveScrollTarget
        switch vault.liveScrollTarget(at: ownerPath) {
        case .success(let resolved):
            target = resolved
        case .failure(let failure):
            return .noSeed(.ownerNotLiveScrollable(failure))
        }
        guard !target.scrollView.bhIsUnsafeForProgrammaticScrolling else {
            return .noSeed(.ownerUnsafeForProgrammaticScrolling)
        }
        let transition = await performViewportTransition(
            .revealViewPoint(
                point,
                in: .uiScrollView(container: target.container, scrollView: target.scrollView)
            ),
            deadline: request.deadline
        )
        guard transition.outcome.didMove,
              let current = transition.current
        else { return .noSeed(.viewportDidNotMove) }
        let exploration = InterfaceExplorationResult(
            current: current,
            progress: .init(),
            didMoveViewport: true,
            viewportExit: .retained
        )
        switch semanticTargetScanMatch(request.target) {
        case .visible(let current):
            return .revealed(current, exploration)
        case .failed(let failure):
            return .failed(failure)
        case .offscreen:
            return .missed
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
