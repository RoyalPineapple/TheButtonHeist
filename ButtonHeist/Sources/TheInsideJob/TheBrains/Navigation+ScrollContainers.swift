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
        let path: TreePath
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
        case .element(let elementTarget):
            guard let resolved = stash.resolveVisibleTarget(elementTarget).resolved else {
                return .failed(liveScrollElementFailureMessage(elementTarget, commandName: commandName))
            }
            let targetDescription = Self.ScrollTargetDescription(resolved).description
            guard let scrollView = stash.liveScrollView(for: resolved) else {
                return .failed(
                    "scroll target failed: observed \(targetDescription) with no live scrollable ancestor; "
                        + "target an element inside the intended scroll region"
                )
            }
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else {
                return .failed(
                    "scroll target failed: observed \(targetDescription) inside a scroll view that is unsafe "
                        + "for programmatic scrolling; target the element you want made actionable"
                )
            }
            let availableAxis = Self.scrollableAxis(contentSize: scrollView.contentSize, frame: scrollView.frame)
            guard availableAxis.contains(axis) else {
                return .failed(
                    "scroll target failed: observed \(targetDescription) inside a scroll view that supports "
                        + "\(Self.axisDescription(availableAxis)); expected \(Self.axisDescription(axis)); "
                        + "try a matching scroll direction or target an element inside the intended scroll region"
                )
            }
            return .resolved(.uiScrollView(scrollView))
        case .container(let containerName):
            let candidates = scrollCandidates(requiredAxis: axis).filter {
                (stash.liveContainerName(forPath: $0.path) ?? stash.liveContainerName(for: $0.container)) == containerName
            }
            guard !candidates.isEmpty else {
                return .failed(
                    "\(commandName) failed: no visible scroll container named \(containerName) " +
                        "supports \(Self.axisDescription(axis)); refresh get_interface and use a current containerName"
                )
            }
            guard candidates.count == 1, let plan = candidates.first else {
                return .failed(
                    "\(commandName) ambiguous: multiple visible scroll containers named \(containerName) " +
                        "support \(Self.axisDescription(axis)); refresh get_interface and use a current containerName"
                )
            }
            return .resolved(plan.target)
        case .visibleContainer:
            let candidates = scrollCandidates(requiredAxis: axis)
            guard !candidates.isEmpty else {
                return .failed("\(commandName) failed: no visible scroll container supports \(Self.axisDescription(axis))")
            }
            guard candidates.count == 1, let plan = candidates.first else {
                return .failed(
                    "\(commandName) ambiguous: multiple visible scroll containers support \(Self.axisDescription(axis)); "
                        + "target an element inside the intended scroll region"
                )
            }
            return .resolved(plan.target)
        }
    }

    func scrollCandidates(
        requiredAxis axis: ScrollAxis?
    ) -> [ScrollPlan] {
        stash.latestObservedLiveHierarchy.containerPaths.compactMap { item -> ScrollPlan? in
            let container = item.container
            let path = item.path
            guard case .scrollable(let contentSize) = container.type else { return nil }

            if let axis, !Self.scrollableAxis(of: container).contains(axis) {
                return nil
            }

            let liveView = self.stash.liveScrollableContainerView(forPath: path)
                ?? self.stash.scrollableContainerViews[container]
            if let view = liveView,
               view.window != nil,
               Self.isObscuredByPresentation(view: view) {
                return nil
            }
            guard let target = self.scrollableTarget(
                for: container,
                path: path,
                contentSize: contentSize
            ) else {
                return nil
            }
            return ScrollPlan(target: target, container: container, path: path)
        }
    }

    /// Build a ScrollableTarget for a container. Geometry comes from the current
    /// accessibility capture; UIKit refs are only dispatch objects for real scroll
    /// actions, not semantic state authority.
    func scrollableTarget(
        for container: AccessibilityContainer,
        path: TreePath? = nil,
        contentSize: AccessibilitySize
    ) -> ScrollableTarget? {
        let cgContentSize = contentSize.cgSize
        if let path,
           let scrollView = stash.liveScrollableContainerView(forPath: path) as? UIScrollView {
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
            return .uiScrollView(scrollView)
        }
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
        let tabBarTop = stash.latestObservedLiveHierarchy
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
        _ target: ElementTarget,
        commandName: String
    ) -> String {
        switch stash.resolveTarget(target) {
        case .resolved:
            return "\(commandName) failed: target is known but not currently visible; "
                + "target the element you want made actionable, or use scroll_to_visible as an explicit viewport inspection step."
        case .ambiguous(let facts):
            return "\(commandName) failed: target is not uniquely resolved in the visible hierarchy; "
                + "\(TargetResolutionDiagnostics.message(for: .ambiguous(facts)))\nNext: refine the semantic target with "
                + "an ordinal or exact label, identifier, value, or trait from get_screen's visible interface."
        case .notFound(let facts):
            return TargetResolutionDiagnostics.message(for: .notFound(facts))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
