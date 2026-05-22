#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Scroll Orchestration
//
// Finds scrollable containers from the accessibility hierarchy and
// drives TheSafecracker's scroll primitives. Two paths:
//
//   UIScrollView → setContentOffset (fast, precise)
//   Any scrollable → synthetic swipe gesture (universal fallback)

extension Navigation {

    /// One selected semantic scroll container plus the physical target used to move it.
    @MainActor struct ScrollPlan { // swiftlint:disable:this agent_main_actor_value_type
        let target: ScrollableTarget
        let container: AccessibilityContainer
        let axis: ScrollAxis

        init(target: ScrollableTarget, container: AccessibilityContainer) {
            self.target = target
            self.container = container
            self.axis = Navigation.scrollableAxis(of: container)
        }

        func supports(_ requiredAxis: ScrollAxis) -> Bool {
            axis.contains(requiredAxis)
        }

        func movement(for direction: ScrollSearchDirection) -> UIAccessibilityScrollDirection? {
            guard supports(Navigation.requiredAxis(for: direction)) else { return nil }
            return Navigation.uiScrollDirection(for: direction)
        }
    }

    struct ScrollProof: Equatable {
        let moved: Bool
        let previousVisibleIds: Set<HeistId>

        var atEdge: Bool {
            !moved
        }

        func visibleStateUnchanged(after visibleIds: Set<HeistId>) -> Bool {
            visibleIds == previousVisibleIds
        }
    }

    enum ScrollTargetResolution {
        case resolved(UIScrollView)
        case failed(ScrollTargetDiagnostic)
    }

    @MainActor enum ContainerScrollResolution { // swiftlint:disable:this agent_main_actor_value_type
        case resolved(ScrollableTarget)
        case failed(String)
    }

    enum ScrollTargetDiagnosticReason: Equatable {
        case noScrollView
        case unsafeProgrammaticScroll
        case axisMismatch(required: ScrollAxis, available: ScrollAxis)
    }

    struct ScrollTargetDiagnostic: Equatable {
        let reason: ScrollTargetDiagnosticReason

        func message(for screenElement: TheStash.ScreenElement) -> String {
            let element = Navigation.describeScrollTarget(screenElement)
            switch reason {
            case .noScrollView:
                return "scroll target failed: observed \(element) with no live scrollable ancestor; "
                    + "try \(ScrollMode.search.canonicalCommand) or target an element inside a scroll container"
            case .unsafeProgrammaticScroll:
                return "scroll target failed: observed \(element) inside a scroll view that is unsafe "
                    + "for programmatic scrolling; try \(ScrollMode.search.canonicalCommand) to use semantic search"
            case .axisMismatch(let required, let available):
                return "scroll target failed: observed \(element) inside a scroll view that supports "
                    + "\(Self.axisDescription(available)); expected \(Self.axisDescription(required)); "
                    + "try a matching scroll direction or target an element inside a matching scroll container"
            }
        }

        private static func axisDescription(_ axis: ScrollAxis) -> String {
            switch (axis.contains(.horizontal), axis.contains(.vertical)) {
            case (true, true): return "horizontal and vertical scrolling"
            case (true, false): return "horizontal scrolling"
            case (false, true): return "vertical scrolling"
            case (false, false): return "no scrolling"
            }
        }
    }

    private enum ScrollAxisSelection {
        case any
        case required(ScrollAxis)
    }

    // MARK: - Scroll Axis Detection

    static func scrollableAxis(of target: ScrollableTarget) -> ScrollAxis {
        scrollableAxis(contentSize: target.contentSize, frame: target.frame)
    }

    static func scrollableAxis(of container: AccessibilityContainer) -> ScrollAxis {
        guard case .scrollable(let contentSize) = container.type else { return [] }
        return scrollableAxis(contentSize: contentSize.cgSize, frame: container.frame.cgRect)
    }

    private static func scrollableAxis(contentSize: CGSize, frame: CGRect) -> ScrollAxis {
        var axis: ScrollAxis = []
        if contentSize.width > frame.width + 1 { axis.insert(.horizontal) }
        if contentSize.height > frame.height + 1 { axis.insert(.vertical) }
        return axis
    }

    static func requiredAxis(for direction: ScrollDirection) -> ScrollAxis {
        switch direction {
        case .up, .down, .next, .previous: return .vertical
        case .left, .right: return .horizontal
        }
    }

    static func requiredAxis(for edge: ScrollEdge) -> ScrollAxis {
        switch edge {
        case .top, .bottom: return .vertical
        case .left, .right: return .horizontal
        }
    }

    static func requiredAxis(for direction: ScrollSearchDirection) -> ScrollAxis {
        switch direction {
        case .up, .down: return .vertical
        case .left, .right: return .horizontal
        }
    }

    private static func axisDescription(_ axis: ScrollAxis) -> String {
        switch (axis.contains(.horizontal), axis.contains(.vertical)) {
        case (true, true): return "horizontal and vertical scrolling"
        case (true, false): return "horizontal scrolling"
        case (false, true): return "vertical scrolling"
        case (false, false): return "no scrolling"
        }
    }

    // MARK: - Unified Scroll Dispatch

    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) async -> ScrollProof {
        let before = stash.visibleIds
        let beforeAnchor = visibleAnchorSignature()

        switch target {
        case .uiScrollView(let sv):
            let moved = safecracker.scrollByPage(sv, direction: direction, animated: animated)
            guard moved else {
                return ScrollProof(moved: false, previousVisibleIds: before)
            }
            if animated {
                let screenFrame = sv.convert(sv.bounds, to: nil)
                await safecracker.animateScrollFingerprint(
                    frame: screenFrame, direction: direction
                )
            } else {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            }
            refresh()
            return ScrollProof(moved: true, previousVisibleIds: before)
        case .swipeable(let frame, let contentSize):
            let targetKey = swipeTargetKey(frame: frame, contentSize: contentSize)
            let isDirectionChange = lastSwipeDirectionByTarget[targetKey].map { $0 != direction } ?? false
            let dispatched = await safecracker.scrollBySwipe(
                frame: frame,
                direction: direction,
                duration: Self.swipeGestureDuration
            )
            guard dispatched else {
                return ScrollProof(moved: false, previousVisibleIds: before)
            }
            let moved = await settleSwipeMotion(
                previousVisibleIds: before,
                previousAnchor: beforeAnchor,
                requireDirectionChangeSettle: isDirectionChange
            )
            lastSwipeDirectionByTarget[targetKey] = direction
            return ScrollProof(moved: moved, previousVisibleIds: before)
        }
    }

    /// Parse through post-gesture spring/inertia and consider the swipe settled
    /// when no new elements are discovered for a short consecutive frame window.
    private func settleSwipeMotion(
        previousVisibleIds: Set<HeistId>,
        previousAnchor: Int?,
        requireDirectionChangeSettle: Bool
    ) async -> Bool {
        let profile: SettleSwipeProfile = requireDirectionChangeSettle
            ? .directionChange
            : .sameDirection
        var state = SettleSwipeLoopState(
            profile: profile,
            previousVisibleIds: previousVisibleIds,
            previousAnchor: previousAnchor
        )
        var seenVisibleIds = stash.visibleIds

        while true {
            refresh()
            let currentVisibleIds = stash.visibleIds
            let newHeistIds = currentVisibleIds.subtracting(seenVisibleIds)
            seenVisibleIds.formUnion(newHeistIds)

            let step = state.advance(
                visibleIds: currentVisibleIds,
                anchorSignature: visibleAnchorSignature(),
                newHeistIds: newHeistIds
            )
            if case .done = step { break }
            await tripwire.yieldFrames(1)
        }
        return state.moved
    }

    /// Stable signature for the viewport based on content-space origins.
    /// Avoids treating edge bounces/re-parses as true movement.
    ///
    /// The returned hash is **in-process only** — Swift's hash seed is
    /// randomized per launch, so never persist, log, or compare these values
    /// across processes.
    private func visibleAnchorSignature() -> Int? {
        let anchors = stash.visibleIds.compactMap { heistId -> String? in
            guard let entry = stash.currentScreen.findElement(heistId: heistId),
                  let origin = entry.contentSpaceOrigin else { return nil }
            return "\(heistId):\(Int(origin.x.rounded())):\(Int(origin.y.rounded()))"
        }.sorted()
        guard !anchors.isEmpty else { return nil }
        return anchors.joined(separator: "|").hashValue
    }

    private func swipeTargetKey(frame: CGRect, contentSize: CGSize) -> String {
        let values = [
            Int(frame.minX.rounded()),
            Int(frame.minY.rounded()),
            Int(frame.width.rounded()),
            Int(frame.height.rounded()),
            Int(contentSize.width.rounded()),
            Int(contentSize.height.rounded())
        ]
        return values.map(String.init).joined(separator: ":")
    }

    /// Clamp a swipe rectangle to the screen region outside accessibility-level
    /// chrome: above any `.tabBar` container, inset horizontally by the key
    /// window's layout margins. Returns the intersection when it's non-empty;
    /// otherwise the frame clipped to the screen so swipes at least stay
    /// on-screen.
    ///
    /// Nav bar detection is deliberately absent: UIKit does not expose an
    /// accessibility signal for `UINavigationBar`, and we refuse to walk the
    /// UIView hierarchy to infer one. Apps whose scrollable frame extends
    /// under a translucent nav bar will surface the bug (swipe misfires or
    /// doesn't scroll) — the honest failure mode per BH's thesis. The proper
    /// fix will come from AXRuntime attribute 2015 (`_accessibilityValueForAttribute:`),
    /// which every element carries as a back-reference to its owning nav bar;
    /// that path needs LLDB validation across OS versions before shipping.
    func safeSwipeFrame(from frame: CGRect) -> CGRect {
        let safeIntersection = frame.intersection(currentSwipeSafeBounds())
        if !safeIntersection.isNull, !safeIntersection.isEmpty {
            return safeIntersection
        }
        let screenIntersection = frame.intersection(ScreenMetrics.current.bounds)
        if !screenIntersection.isNull, !screenIntersection.isEmpty {
            return screenIntersection
        }
        return frame
    }

    /// Region of the screen safe for synthetic swipes. Bottom edge is the top
    /// of any `.tabBar` container in the accessibility hierarchy. Top edge is
    /// the window's `safeAreaInsets.top` — covers the status bar / notch but
    /// not nav bars (see `safeSwipeFrame`).
    private func currentSwipeSafeBounds() -> CGRect {
        let screen = ScreenMetrics.current.bounds
        let tabBarTop = stash.currentHierarchy
            .flattenToContainers()
            .compactMap { container -> CGFloat? in
                guard case .tabBar = container.type else { return nil }
                return container.frame.minY
            }
            .min()

        let window = Self.keyWindow
        let horizontalInset = window?.directionalLayoutMargins.leading ?? 0
        let insets = window?.safeAreaInsets ?? .zero
        let top = insets.top
        let bottom = tabBarTop ?? (screen.height - insets.bottom)

        return CGRect(
            x: screen.minX + horizontalInset,
            y: top,
            width: max(0, screen.width - horizontalInset * 2),
            height: max(0, bottom - top)
        )
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    // MARK: - Scroll Command Execution

    func executeScroll(_ target: ScrollTarget) async -> TheSafecracker.InteractionResult {
        let axis = Self.requiredAxis(for: target.direction)
        switch resolveContainerScrollTarget(
            containerTarget: target.containerTarget,
            elementTarget: target.elementTarget,
            axis: axis,
            method: .scroll,
            commandName: ScrollMode.page.canonicalCommand
        ) {
        case .resolved(let scrollTarget):
            let uiDirection = Self.uiScrollDirection(for: target.direction)
            let proof = await scrollOnePageAndSettle(
                scrollTarget, direction: uiDirection
            )
            return proof.moved
                ? .success(method: .scroll)
                : .failure(.scroll, message: "scroll failed: observed target already at edge; try the opposite direction")
        case .failed(let message):
            return .failure(.scroll, message: message)
        }
    }

    func executeScrollToEdge(_ target: ScrollToEdgeTarget) async -> TheSafecracker.InteractionResult {
        let axis = Self.requiredAxis(for: target.edge)
        switch resolveContainerScrollTarget(
            containerTarget: target.containerTarget,
            elementTarget: target.elementTarget,
            axis: axis,
            method: .scrollToEdge,
            commandName: ScrollMode.toEdge.canonicalCommand
        ) {
        case .resolved(let scrollTarget):
            guard case .uiScrollView(let scrollView) = scrollTarget else {
                return .failure(.scrollToEdge, message: "\(ScrollMode.toEdge.canonicalCommand) failed: selected container has no live UIScrollView")
            }
            let moved = safecracker.scrollToEdge(scrollView, edge: target.edge)

            return moved
                ? .success(method: .scrollToEdge)
                : .failure(
                    .scrollToEdge,
                    message: "\(ScrollMode.toEdge.canonicalCommand) failed: observed target already at requested edge"
                )
        case .failed(let message):
            return .failure(.scrollToEdge, message: message)
        }
    }

    static func edgeDirection(for edge: ScrollEdge) -> UIAccessibilityScrollDirection {
        switch edge {
        case .top: return .up
        case .bottom: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    // MARK: - Scroll To Visible (Inflation)

    /// Reveal a target. If already visible, nudge it into the comfort zone. If
    /// it is known-only, inflate it by scrolling a live parent derived from the
    /// current graph, then prove success through a fresh visible resolution.
    func executeScrollToVisible(
        _ target: ScrollToVisibleTarget,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for \(ScrollMode.toVisible.canonicalCommand)")
        }

        if recordedScreen == nil {
            stash.refresh()
        }

        let knownScreen = recordedScreen ?? stash.currentScreen
        let normalizedTarget = stash.normalizeTarget(elementTarget, in: knownScreen)
        let executableTarget = normalizedTarget.executableTarget
        let targetResolution = recordedScreen == nil
            ? resolvePositioningTarget(normalizedTarget)
            : stash.resolveTarget(executableTarget, in: knownScreen)
        switch targetResolution {
        case .resolved(let semanticTarget):
            let inflation = stash.inflateTarget(semanticTarget.screenElement)
            if case .failed = inflation {
                return .failure(
                    .scrollToVisible,
                    message: scrollToVisibleKnownTargetFailureMessage(semanticTarget.screenElement)
                )
            }
            if inflation.didScroll {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                refresh()
            }
            let liveResolution = stash.resolveVisibleTarget(executableTarget)
            guard let found = liveResolution.resolved else {
                let suffix = liveResolution.diagnostics.isEmpty ? "" : ": \(liveResolution.diagnostics)"
                return .failure(
                    .scrollToVisible,
                    message: normalizedTarget.diagnostics("Element not visible after inflation\(suffix)")
                )
            }
            let ensureResult = await ensureVisibleResolvedTarget(found)
            guard ensureResult.succeeded else {
                let failure = ensureResult.failure
                return .failure(
                    failure?.method ?? .scrollToVisible,
                    message: failure?.message ?? "Element is present but could not be scrolled fully on-screen"
                )
            }
            let refreshedResolution = stash.resolveVisibleTarget(executableTarget)
            guard refreshedResolution.resolved != nil else {
                let suffix = refreshedResolution.diagnostics.isEmpty ? "" : ": \(refreshedResolution.diagnostics)"
                return .failure(
                    .scrollToVisible,
                    message: normalizedTarget.diagnostics("Element disappeared after inflation\(suffix)")
                )
            }
            let message = inflation.didScroll ? nil : "Already visible"
            return .success(method: .scrollToVisible, message: message)
        case .notFound(let diagnostics), .ambiguous(_, let diagnostics):
            return .failure(.scrollToVisible, message: normalizedTarget.diagnostics(diagnostics))
        }
    }

    // MARK: - Element Search (Iterative)

    /// Iterative search: page through scroll content looking for an element.
    /// Used when the element has never been seen (not in the current screen).
    func executeElementSearch(_ target: ElementSearchTarget) async -> TheSafecracker.InteractionResult {
        guard let searchTarget = target.elementTarget else {
            return .failure(.elementSearch, message: "Element target required for \(ScrollMode.search.canonicalCommand)")
        }
        let searchDirection = target.resolvedDirection

        let requestedAxis = Self.requiredAxis(for: searchDirection)
        let knownScreen = stash.currentScreen
        var candidates = scrollSearchCandidates(requiredAxis: requestedAxis)
        var progress = ScrollSearchProgress(
            initialVisibleHeistIds: stash.visibleIds,
            knownContainers: Set(candidates.map(\.container)),
            maxScrolls: Self.scrollSearchMaxScrolls
        )

        let normalizedTarget = stash.normalizeTarget(searchTarget, in: knownScreen)
        if case .notFound = resolvePositioningTarget(normalizedTarget) {
            // Unknown targets still use iterative search below.
        } else {
            let direct = await executeScrollToVisible(
                ScrollToVisibleTarget(elementTarget: searchTarget),
                recordedScreen: knownScreen
            )
            stash.refresh()
            if direct.success, let found = stash.resolveFirstVisibleMatch(searchTarget) {
                return searchFoundResult(
                    found, scrollCount: progress.scrollCount,
                    uniqueElementsSeen: progress.uniqueElementsSeen
                )
            }
            return .failure(
                .elementSearch,
                message: direct.message ?? "\(ScrollMode.search.canonicalCommand) failed to reveal known target",
                payload: direct.payload
            )
        }

        // Check if already visible before searching
        if let found = stash.resolveFirstVisibleMatch(searchTarget) {
            // Element search succeeds once resolved; comfort-zone nudging is best-effort.
            _ = ensureOnScreenSync(found)
            return searchFoundResult(
                found, scrollCount: 0,
                uniqueElementsSeen: progress.uniqueElementsSeen
            )
        }

        // Iterative page-by-page search
        while progress.canScrollMore {
            refreshScrollSearchCandidates(
                requiredAxis: requestedAxis,
                candidates: &candidates,
                progress: &progress
            )

            guard let plan = candidates.first(where: {
                !progress.exhaustedContainers.contains($0.container)
            }) else { break }

            guard let direction = plan.movement(for: searchDirection) else {
                progress.markContainerExhausted(plan.container)
                continue
            }
            progress.markContainerSearched(plan.container)
            let proof = await scrollOnePageAndSettle(plan.target, direction: direction)

            if !proof.moved {
                progress.markContainerExhausted(plan.container)
                continue
            }

            progress.markScrolledPage(in: plan.container, visibleHeistIds: stash.visibleIds)
            refreshScrollSearchCandidates(
                requiredAxis: requestedAxis,
                candidates: &candidates,
                progress: &progress
            )
            if let found = stash.resolveFirstVisibleMatch(searchTarget) {
                if let result = await searchFineTuneAndResolve(
                    found, searchTarget: searchTarget,
                    scrollCount: progress.scrollCount, progress: &progress
                ) {
                    return result
                }
                return searchFoundResult(
                    found, scrollCount: progress.scrollCount,
                    uniqueElementsSeen: progress.uniqueElementsSeen
                )
            }

            if proof.visibleStateUnchanged(after: stash.visibleIds) {
                progress.markContainerExhausted(plan.container)
            }
        }

        return searchNotFoundResult(progress: progress)
    }

    private func searchFineTuneAndResolve(
        _ found: TheStash.ResolvedTarget,
        searchTarget: ElementTarget,
        scrollCount: Int,
        progress: inout ScrollSearchProgress
    ) async -> TheSafecracker.InteractionResult? {
        // Search already found the target; this only improves action ergonomics when possible.
        _ = ensureOnScreenSync(found)
        await tripwire.yieldRealFrames(Self.postJumpRealFrames)
        stash.refresh()
        progress.recordVisibleHeistIds(stash.visibleIds)
        guard let fresh = stash.resolveFirstVisibleMatch(searchTarget) else { return nil }
        return searchFoundResult(
            fresh, scrollCount: scrollCount,
            uniqueElementsSeen: progress.uniqueElementsSeen
        )
    }

    func findScrollTarget(
        requiredAxis axis: ScrollAxis?,
        excluding exhausted: Set<AccessibilityContainer> = []
    ) -> ScrollPlan? {
        scrollCandidates(
            selecting: axis.map(ScrollAxisSelection.required) ?? .any,
            excluding: exhausted
        )
        .first
    }

    private func resolveContainerScrollTarget(
        containerTarget: ScrollContainerTarget?,
        elementTarget: ElementTarget?,
        axis: ScrollAxis,
        method: ActionMethod,
        commandName: String
    ) -> ContainerScrollResolution {
        if let containerTarget {
            guard let plan = scrollPlan(for: containerTarget, requiredAxis: axis) else {
                return .failed("\(commandName) failed: no visible scroll container matched \(containerTarget.description)")
            }
            return .resolved(plan.target)
        }

        if let elementTarget {
            guard let resolved = stash.resolveVisibleTarget(elementTarget).resolved else {
                return .failed(liveScrollElementFailure(elementTarget, method: method, commandName: commandName).message ?? "Element target not visible")
            }
            switch resolveScrollTargetResult(screenElement: resolved.screenElement, axis: axis) {
            case .resolved(let scrollView):
                return .resolved(.uiScrollView(scrollView))
            case .failed(let diagnostic):
                return .failed(diagnostic.message(for: resolved.screenElement))
            }
        }

        let candidates = scrollSearchCandidates(requiredAxis: axis)
        guard !candidates.isEmpty else {
            return .failed("\(commandName) failed: no visible scroll container supports \(Self.axisDescription(axis))")
        }
        guard candidates.count == 1, let plan = candidates.first else {
            return .failed(
                "\(commandName) ambiguous: multiple visible scroll containers support \(Self.axisDescription(axis)); "
                    + "specify stableId. Candidates: \(candidateContainerRefs(candidates))"
            )
        }
        return .resolved(plan.target)
    }

    private func scrollPlan(for target: ScrollContainerTarget, requiredAxis axis: ScrollAxis) -> ScrollPlan? {
        let ids = [target.stableId, target.captureLocalRef].compactMap { $0 }
        guard !ids.isEmpty else { return nil }
        return scrollSearchCandidates(requiredAxis: axis).first { plan in
            guard let stableId = stableId(for: plan.container) else { return false }
            return ids.contains(stableId)
        }
    }

    private func stableId(for container: AccessibilityContainer) -> HeistContainer? {
        if let stableId = stash.currentScreen.liveInterface.containerStableIds[container] {
            return stableId
        }
        return stash.currentHierarchy.containerPaths.first { candidate, _ in
            candidate == container
        }.flatMap { _, path in
            stash.currentScreen.liveInterface.containerStableIdsByPath[path]
        }
    }

    private func candidateContainerRefs(_ candidates: [ScrollPlan]) -> String {
        candidates.enumerated().map { index, plan in
            stableId(for: plan.container) ?? "#\(index)"
        }.joined(separator: ", ")
    }

    func scrollSearchCandidates(
        requiredAxis axis: ScrollAxis?
    ) -> [ScrollPlan] {
        scrollCandidates(selecting: axis.map(ScrollAxisSelection.required) ?? .any)
    }

    private func refreshScrollSearchCandidates(
        requiredAxis axis: ScrollAxis?,
        candidates: inout [ScrollPlan],
        progress: inout ScrollSearchProgress
    ) {
        candidates = mergeScrollSearchCandidates(candidates, with: scrollSearchCandidates(requiredAxis: axis))
        progress.recordKnownContainers(candidates.map(\.container))
    }

    private func mergeScrollSearchCandidates(
        _ existing: [ScrollPlan],
        with discovered: [ScrollPlan]
    ) -> [ScrollPlan] {
        discovered.reduce(into: existing) { merged, candidate in
            if let index = merged.firstIndex(where: { $0.container == candidate.container }) {
                merged[index] = candidate
            } else {
                merged.append(candidate)
            }
        }
    }

    private func scrollCandidates(
        selecting axisSelection: ScrollAxisSelection,
        excluding exhausted: Set<AccessibilityContainer> = []
    ) -> [ScrollPlan] {
        stash.currentHierarchy.scrollableContainers.compactMap { container -> ScrollPlan? in
            guard !exhausted.contains(container),
                  case .scrollable(let contentSize) = container.type else { return nil }

            let axis = Self.scrollableAxis(of: container)
            if case .required(let requiredAxis) = axisSelection,
               !axis.contains(requiredAxis) {
                return nil
            }

            if let view = self.stash.scrollableContainerViews[container],
               view.window != nil,
               Self.isObscuredByPresentation(view: view) {
                return nil
            }
            guard let target = self.scrollableTarget(for: container, contentSize: contentSize) else {
                return nil
            }
            return ScrollPlan(target: target, container: container)
        }
    }

    /// Build a ScrollableTarget for a container, preferring the live UIView when attached
    /// to a window so that frames reflect the current screen position.
    func scrollableTarget(
        for container: AccessibilityContainer,
        contentSize: AccessibilitySize
    ) -> ScrollableTarget? {
        let cgContentSize = contentSize.cgSize
        if let scrollView = stash.scrollableContainerViews[container] as? UIScrollView {
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
            return .uiScrollView(scrollView)
        }
        if let view = stash.scrollableContainerViews[container], view.window != nil {
            if let scrollView = view as? UIScrollView, scrollView.bhIsUnsafeForProgrammaticScrolling {
                return nil
            }
            let screenFrame = safeSwipeFrame(from: view.convert(view.bounds, to: nil))
            return .swipeable(frame: screenFrame, contentSize: cgContentSize)
        }
        return .swipeable(frame: safeSwipeFrame(from: container.frame.cgRect), contentSize: cgContentSize)
    }

    private func searchNotFoundResult(progress: ScrollSearchProgress) -> TheSafecracker.InteractionResult {
        .failure(
            .elementSearch,
            message: searchNotFoundMessage(progress: progress),
            payload: .scrollSearch(ScrollSearchResult(
                scrollCount: progress.scrollCount,
                uniqueElementsSeen: progress.uniqueElementsSeen,
                totalItems: nil, exhaustive: progress.exhaustive
            ))
        )
    }

    private func searchFoundResult(
        _ found: TheStash.ResolvedTarget,
        scrollCount: Int,
        uniqueElementsSeen: Int
    ) -> TheSafecracker.InteractionResult {
        let wire = TheStash.WireConversion.toWire(found.screenElement)
        return .success(
            method: .elementSearch,
            payload: .scrollSearch(ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: uniqueElementsSeen,
                totalItems: nil, exhaustive: false, foundElement: wire
            ))
        )
    }

    private func searchNotFoundMessage(progress: ScrollSearchProgress) -> String {
        let containerLabel = progress.containersSearched == 1 ? "container" : "containers"
        let pageLabel = progress.pagesSearched == 1 ? "page" : "pages"
        let capSuffix = progress.didHitScrollCap
            ? " (capped at \(progress.maxScrolls) scrolls)"
            : ""
        return "Element not found after \(progress.scrollCount) scrolls across "
            + "\(progress.pagesSearched) \(pageLabel) in "
            + "\(progress.containersSearched) \(containerLabel)\(capSuffix)"
    }

    // MARK: - Ensure On Screen (Comfort Zone)

    private static let comfortMarginFraction: CGFloat = 1.0 / 6.0

    enum EnsureOnScreenResult {
        case alreadyUsable
        case adjustedVisibleTarget
        case recoveredKnownOffscreen
        case operationLocalRotorResult
        case failed(EnsureOnScreenFailure)

        var succeeded: Bool {
            if case .failed = self { return false }
            return true
        }

        var failure: EnsureOnScreenFailure? {
            if case .failed(let failure) = self { return failure }
            return nil
        }
    }

    struct EnsureOnScreenFailure {
        let method: ActionMethod?
        let message: String

        static func elementNotFound(_ message: String) -> EnsureOnScreenFailure {
            EnsureOnScreenFailure(method: .elementNotFound, message: message)
        }

        static func actionFailed(_ message: String) -> EnsureOnScreenFailure {
            EnsureOnScreenFailure(method: nil, message: message)
        }
    }

    private static var interactionComfortZone: CGRect {
        let bounds = ScreenMetrics.current.bounds
        return bounds.insetBy(
            dx: bounds.width * comfortMarginFraction,
            dy: bounds.height * comfortMarginFraction
        )
    }

    func ensureOnScreen(for target: ElementTarget, recordedScreen: Screen? = nil) async -> EnsureOnScreenResult {
        let normalizedTarget = stash.normalizeTarget(target, in: recordedScreen ?? stash.currentScreen)
        return await ensureOnScreen(for: normalizedTarget)
    }

    func ensureOnScreen(for normalizedTarget: TheStash.NormalizedTarget) async -> EnsureOnScreenResult {
        let target = normalizedTarget.executableTarget
        if stash.activePendingRotorResult(for: normalizedTarget.originalTarget) != nil {
            return .operationLocalRotorResult
        }

        switch resolvePositioningTarget(normalizedTarget) {
        case .resolved(let semanticTarget):
            let inflation = stash.inflateTarget(semanticTarget.screenElement)
            if case .failed = inflation {
                return .failed(.actionFailed(
                    "ensure_on_screen failed: \(scrollToVisibleKnownTargetFailureMessage(semanticTarget.screenElement))"
                ))
            }
            if inflation.didScroll {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                refresh()
            }
            let liveResolution = stash.resolveVisibleTarget(target)
            guard let liveTarget = liveResolution.resolved else {
                let suffix = liveResolution.diagnostics.isEmpty ? "" : ": \(liveResolution.diagnostics)"
                return .failed(.elementNotFound(
                    normalizedTarget.diagnostics(
                        "ensure_on_screen failed: target was not visible after inflation\(suffix)"
                    )
                ))
            }
            let ensureResult = await ensureVisibleResolvedTarget(liveTarget)
            guard ensureResult.succeeded else { return ensureResult }
            return inflation.didScroll ? .recoveredKnownOffscreen : ensureResult
        case .notFound(let diagnostics), .ambiguous(_, let diagnostics):
            return .failed(.elementNotFound(normalizedTarget.diagnostics(diagnostics)))
        }
    }

    private func resolvePositioningTarget(_ normalizedTarget: TheStash.NormalizedTarget) -> TheStash.TargetResolution {
        let currentResolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard case .notFound = currentResolution, normalizedTarget.didNormalizeHeistId else {
            return currentResolution
        }
        return stash.resolveTarget(normalizedTarget.executableTarget, in: normalizedTarget.sourceScreen)
    }

    func ensureFirstResponderOnScreen() async {
        guard let heistId = stash.firstResponderHeistId,
              let entry = stash.currentScreen.findElement(heistId: heistId),
              let geometry = stash.liveGeometry(for: entry),
              !ScreenMetrics.current.bounds.contains(geometry.frame),
              !Self.interactionComfortZone.contains(geometry.activationPoint) else { return }
        if safecracker.scrollToMakeVisible(
            geometry.frame, in: geometry.scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) {
            await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            refresh()
        }
    }

    @discardableResult
    private func ensureOnScreenSync(_ resolved: TheStash.ResolvedTarget, animated: Bool = true) -> Bool {
        guard let geometry = stash.liveGeometry(for: resolved.screenElement),
              !ScreenMetrics.current.bounds.contains(geometry.frame),
              !Self.interactionComfortZone.contains(geometry.activationPoint) else { return true }
        return safecracker.scrollToMakeVisible(
            geometry.frame, in: geometry.scrollView, animated: animated,
            comfortMarginFraction: Self.comfortMarginFraction
        )
    }

    private func ensureVisibleResolvedTarget(_ resolved: TheStash.ResolvedTarget) async -> EnsureOnScreenResult {
        guard let geometry = stash.liveGeometry(for: resolved.screenElement),
              !ScreenMetrics.current.bounds.contains(geometry.frame),
              !Self.interactionComfortZone.contains(geometry.activationPoint) else {
            return .alreadyUsable
        }
        guard safecracker.scrollToMakeVisible(
            geometry.frame,
            in: geometry.scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) else {
            return .failed(.actionFailed(
                "ensure_on_screen failed: visible target \(Self.describeScrollTarget(resolved.screenElement)) "
                    + "could not be scrolled fully on-screen"
            ))
        }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        refresh()
        return .adjustedVisibleTarget
    }

    // MARK: - Known Offscreen Lookup

    /// Find a known element that matches `target` but is NOT in the live
    /// viewport. This is a semantic lookup helper; runtime positioning goes
    /// through `inflateTarget` so visible targets no-op and off-screen targets
    /// use the same inflation path.
    ///
    /// Returns nil if the element is already on-screen or unknown. Callers that
    /// preserve a known semantic screen across a visible refresh pass it in
    /// directly so the refresh does not erase the offscreen target before the
    /// scroll decision.
    func knownOffscreenEntry(for target: ElementTarget, in screen: Screen? = nil) -> Screen.ScreenElement? {
        let screen = screen ?? stash.currentScreen
        let visible = stash.visibleIds
        guard let resolved = stash.resolveTarget(target, in: screen).resolved,
              !visible.contains(resolved.screenElement.heistId)
        else { return nil }
        return resolved.screenElement
    }

    func scrollToVisibleFailureMessage(for target: ElementTarget, in screen: Screen? = nil) -> String {
        let screen = screen ?? stash.currentScreen
        switch stash.resolveTarget(target, in: screen) {
        case .resolved(let resolved):
            return scrollToVisibleKnownTargetFailureMessage(resolved.screenElement)
        case .notFound(let diagnostics), .ambiguous(_, let diagnostics):
            return diagnostics
        }
    }

    private func scrollToVisibleKnownTargetFailureMessage(_ entry: Screen.ScreenElement) -> String {
        let description = Self.describeScrollTarget(entry)
        switch stash.resolveInflationScrollView(for: entry) {
        case .resolved:
            return "\(ScrollMode.toVisible.canonicalCommand) failed: known target \(description) could not be inflated; "
                + "use \(ScrollMode.search.canonicalCommand) to find it by scrolling"
        case .failed(.missingContentOrigin):
            return "\(ScrollMode.toVisible.canonicalCommand) failed: known target \(description) has no content-space position; "
                + "use \(ScrollMode.search.canonicalCommand) to find it by scrolling"
        case .failed(.noLiveScrollableAncestor):
            return "\(ScrollMode.toVisible.canonicalCommand) failed: known target \(description) is not inflated because no live "
                + "scrollable ancestor is available; use \(ScrollMode.search.canonicalCommand) to find it by scrolling"
        case .failed(.ambiguousLiveScrollableAncestor):
            return "\(ScrollMode.toVisible.canonicalCommand) failed: known target \(description) is not inflated because the "
                + "current graph does not identify a unique live scrollable ancestor; use "
                + "\(ScrollMode.search.canonicalCommand) to find it by scrolling"
        case .failed(.unsafeProgrammaticScroll):
            return "\(ScrollMode.toVisible.canonicalCommand) failed: known target \(description) is inside a scroll view that is "
                + "unsafe for programmatic scrolling; use \(ScrollMode.search.canonicalCommand) to use semantic search"
        }
    }

    /// Scroll either reveals the requested target or returns a reason it cannot.
    private func liveScrollElementFailure(
        _ target: ElementTarget,
        method: ActionMethod,
        commandName: String
    ) -> TheSafecracker.InteractionResult {
        switch stash.resolveTarget(target) {
        case .resolved:
            return .failure(
                method,
                message: "\(commandName) failed: target is known but not currently visible; "
                    + "use \(ScrollMode.toVisible.canonicalCommand) to reveal it, then retry \(commandName)."
            )
        case .ambiguous(_, let diagnostics):
            return .failure(
                method,
                message: "\(commandName) failed: target is not uniquely resolved in the visible hierarchy; "
                    + "\(diagnostics)\nNext: use \(ScrollMode.toVisible.canonicalCommand) with a heistId for a known off-screen "
                    + "target, or retarget from get_screen's visible interface."
            )
        case .notFound(let diagnostics):
            return .failure(.elementNotFound, message: diagnostics)
        }
    }

    nonisolated private static func describeScrollTarget(_ screenElement: TheStash.ScreenElement) -> String {
        if let label = screenElement.element.label, !label.isEmpty {
            return "\"\(label)\" (heistId: \(screenElement.heistId))"
        }
        if let identifier = screenElement.element.identifier, !identifier.isEmpty {
            return "identifier \"\(identifier)\" (heistId: \(screenElement.heistId))"
        }
        return "heistId \(screenElement.heistId)"
    }

    // MARK: - Scroll Target Resolution

    func resolveScrollTarget(
        screenElement: TheStash.ScreenElement,
        axis: ScrollAxis? = nil
    ) -> UIScrollView? {
        guard case .resolved(let scrollView) = resolveScrollTargetResult(
            screenElement: screenElement,
            axis: axis
        ) else { return nil }
        return scrollView
    }

    func resolveScrollTargetResult(
        screenElement: TheStash.ScreenElement,
        axis: ScrollAxis? = nil
    ) -> ScrollTargetResolution {
        guard let scrollView = stash.liveScrollView(for: screenElement) else {
            return .failed(ScrollTargetDiagnostic(reason: .noScrollView))
        }

        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else {
            return .failed(ScrollTargetDiagnostic(reason: .unsafeProgrammaticScroll))
        }

        guard let axis else { return .resolved(scrollView) }
        let availableAxis = Self.scrollableAxis(of: .uiScrollView(scrollView))
        guard availableAxis.contains(axis) else {
            return .failed(
                ScrollTargetDiagnostic(
                    reason: .axisMismatch(required: axis, available: availableAxis)
                )
            )
        }
        return .resolved(scrollView)
    }

    // MARK: - Direction Mapping

    static func uiScrollDirection(for direction: ScrollSearchDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .down: return .down
        case .up: return .up
        case .left: return .left
        case .right: return .right
        }
    }

    static func uiScrollDirection(for direction: ScrollDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .next: return .next
        case .previous: return .previous
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
