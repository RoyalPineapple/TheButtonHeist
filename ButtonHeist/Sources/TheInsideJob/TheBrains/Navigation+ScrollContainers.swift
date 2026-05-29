#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore

// MARK: - Scroll Container Resolution

extension Navigation {

    /// One selected semantic scroll container plus the physical target used to move it.
    @MainActor struct ScrollPlan { // swiftlint:disable:this agent_main_actor_value_type
        let target: ScrollableTarget
        let container: AccessibilityContainer
    }

    @MainActor enum ContainerScrollResolution { // swiftlint:disable:this agent_main_actor_value_type
        case resolved(ScrollableTarget)
        case failed(String)
    }

    nonisolated private static func axisDescription(_ axis: ScrollAxis) -> String {
        switch (axis.contains(.horizontal), axis.contains(.vertical)) {
        case (true, true): return "horizontal and vertical scrolling"
        case (true, false): return "horizontal scrolling"
        case (false, true): return "vertical scrolling"
        case (false, false): return "no scrolling"
        }
    }

    func resolveContainerScrollTarget(
        selection: ScrollContainerSelection,
        axis: ScrollAxis,
        commandName: String
    ) -> ContainerScrollResolution {
        switch selection {
        case .container(let containerTarget):
            guard let plan = scrollPlan(for: containerTarget, requiredAxis: axis) else {
                return .failed("\(commandName) failed: no visible scroll container matched \(containerTarget.description)")
            }
            return .resolved(plan.target)
        case .element(let elementTarget):
            guard let resolved = stash.resolveVisibleTarget(elementTarget).resolved else {
                return .failed(liveScrollElementFailureMessage(.currentCapture(elementTarget), commandName: commandName))
            }
            let targetDescription = Self.describeScrollTarget(resolved)
            guard let scrollView = stash.liveScrollView(for: resolved) else {
                return .failed(
                    "scroll target failed: observed \(targetDescription) with no live scrollable ancestor; "
                        + "try element_search or target an element inside a scroll container"
                )
            }
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else {
                return .failed(
                    "scroll target failed: observed \(targetDescription) inside a scroll view that is unsafe "
                        + "for programmatic scrolling; try element_search to use semantic search"
                )
            }
            let availableAxis = Self.scrollableAxis(contentSize: scrollView.contentSize, frame: scrollView.frame)
            guard availableAxis.contains(axis) else {
                return .failed(
                    "scroll target failed: observed \(targetDescription) inside a scroll view that supports "
                        + "\(Self.axisDescription(availableAxis)); expected \(Self.axisDescription(axis)); "
                        + "try a matching scroll direction or target an element inside a matching scroll container"
                )
            }
            return .resolved(.uiScrollView(scrollView))
        case .visibleContainer:
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
    }

    func scrollPlan(for target: ScrollContainerTarget, requiredAxis axis: ScrollAxis) -> ScrollPlan? {
        let ids = [target.stableId, target.captureLocalRef].compactMap { $0 }
        guard !ids.isEmpty else { return nil }
        return scrollSearchCandidates(requiredAxis: axis).first { plan in
            guard let stableId = stableId(for: plan.container) else { return false }
            return ids.contains(stableId)
        }
    }

    func scrollSearchCandidates(
        requiredAxis axis: ScrollAxis?
    ) -> [ScrollPlan] {
        stash.currentHierarchy.scrollableContainers.compactMap { container -> ScrollPlan? in
            guard case .scrollable(let contentSize) = container.type else { return nil }

            if let axis, !Self.scrollableAxis(of: container).contains(axis) {
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

    func scrollSearchSeedCandidate(
        for target: SemanticElementTarget,
        requiredAxis axis: ScrollAxis
    ) -> ScrollPlan? {
        guard let executableTarget = target.executableTarget,
              let resolved = stash.resolveTarget(executableTarget).resolved,
              let scrollView = stash.liveScrollView(for: resolved),
              !scrollView.bhIsUnsafeForProgrammaticScrolling else {
            return nil
        }
        let availableAxis = Self.scrollableAxis(contentSize: scrollView.contentSize, frame: scrollView.frame)
        guard availableAxis.contains(axis) else { return nil }

        let container = scrollSearchContainer(for: scrollView)
            ?? AccessibilityContainer(
                type: .scrollable(contentSize: AccessibilitySize(scrollView.contentSize)),
                frame: AccessibilityRect(scrollView.frame)
            )
        return ScrollPlan(target: .uiScrollView(scrollView), container: container)
    }

    private func scrollSearchContainer(for scrollView: UIScrollView) -> AccessibilityContainer? {
        stash.currentScreen.liveCapture.scrollableContainerViews.first { _, ref in
            ref.view === scrollView
        }?.key
    }

    func stableId(for container: AccessibilityContainer) -> HeistContainer? {
        if let stableId = stash.currentScreen.liveCapture.containerStableIds[container] {
            return stableId
        }
        return stash.currentHierarchy.containerPaths.first { candidate, _ in
            candidate == container
        }.flatMap { _, path in
            stash.currentScreen.liveCapture.containerStableIdsByPath[path]
        }
    }

    func candidateContainerRefs(_ candidates: [ScrollPlan]) -> String {
        candidates.enumerated().map { index, plan in
            stableId(for: plan.container) ?? "#\(index)"
        }.joined(separator: ", ")
    }

    /// Build a ScrollableTarget for a container. Geometry comes from the current
    /// accessibility capture; UIKit refs are only dispatch objects for real scroll
    /// actions, not semantic state authority.
    func scrollableTarget(
        for container: AccessibilityContainer,
        contentSize: AccessibilitySize
    ) -> ScrollableTarget? {
        let cgContentSize = contentSize.cgSize
        if let scrollView = stash.scrollableContainerViews[container] as? UIScrollView {
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
            return .uiScrollView(scrollView)
        }
        guard let screenFrame = safeSwipeFrame(from: container.frame.cgRect) else {
            return nil
        }
        return .swipeable(frame: screenFrame, contentSize: cgContentSize)
    }

    /// Clamp a swipe rectangle to the screen region outside accessibility-level
    /// chrome: above any `.tabBar` container, inset horizontally by the key
    /// window's layout margins. Returns nil when the frame has no targetable
    /// on-screen geometry.
    ///
    /// Nav bar detection is deliberately absent: UIKit does not expose an
    /// accessibility signal for `UINavigationBar`, and we refuse to walk the
    /// UIView hierarchy to infer one. Apps whose scrollable frame extends
    /// under a translucent nav bar will surface the bug (swipe misfires or
    /// doesn't scroll) — the honest failure mode per BH's thesis. The proper
    /// fix will come from AXRuntime attribute 2015 (`_accessibilityValueForAttribute:`),
    /// which every element carries as a back-reference to its owning nav bar;
    /// that path needs LLDB validation across OS versions before shipping.
    func safeSwipeFrame(from frame: CGRect) -> CGRect? {
        let safeIntersection = frame.intersection(currentSwipeSafeBounds())
        if !safeIntersection.isNull, !safeIntersection.isEmpty {
            return safeIntersection
        }
        let screenIntersection = frame.intersection(ScreenMetrics.current.bounds)
        if !screenIntersection.isNull, !screenIntersection.isEmpty {
            return screenIntersection
        }
        return nil
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

    /// Scroll either reveals the requested target or returns a reason it cannot.
    private func liveScrollElementFailureMessage(
        _ target: SemanticElementTarget,
        commandName: String
    ) -> String {
        switch stash.resolveTarget(target) {
        case .resolved:
            return "\(commandName) failed: target is known but not currently visible; "
                + "use scroll_to_visible to reveal it, then retry \(commandName)."
        case .ambiguous(_, let diagnostics):
            return "\(commandName) failed: target is not uniquely resolved in the visible hierarchy; "
                + "\(diagnostics)\nNext: use scroll_to_visible with a heistId for a known off-screen "
                + "target, or retarget from get_screen's visible interface."
        case .notFound(let diagnostics):
            return diagnostics
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
