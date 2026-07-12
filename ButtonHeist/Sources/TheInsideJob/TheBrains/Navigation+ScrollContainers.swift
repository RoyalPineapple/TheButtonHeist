#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

import TheScore
import ThePlans

// MARK: - Scroll Container Resolution

extension Navigation {

    /// One selected semantic scroll container plus the physical target used to move it.
    @MainActor struct ScrollPlan { // swiftlint:disable:this agent_main_actor_value_type
        let target: ScrollableTarget
        let container: AccessibilityContainer
        let path: TreePath
    }

    private struct ScrollContainerEvidence {
        let container: AccessibilityContainer
        let path: TreePath
        let contentSize: AccessibilitySize
    }

    @MainActor enum ContainerScrollResolution { // swiftlint:disable:this agent_main_actor_value_type
        case resolved(ScrollableTarget)
        case failed(ContainerScrollFailure)
    }

    enum ContainerScrollCommand: Sendable {
        case scroll
        case scrollToEdge

        var method: ActionMethod {
            switch self {
            case .scroll:
                return .scroll
            case .scrollToEdge:
                return .scrollToEdge
            }
        }

        var diagnosticName: String {
            switch self {
            case .scroll:
                return "scroll"
            case .scrollToEdge:
                return "scroll_to_edge"
            }
        }
    }

    enum ContainerScrollFailure {
        case elementKnownButNotVisible(command: ContainerScrollCommand)
        case elementAmbiguous(TheStash.TargetAmbiguityFacts, command: ContainerScrollCommand)
        case elementNotFound(TheStash.TargetNotFoundFacts, command: ContainerScrollCommand)
        case missingScrollableAncestor(ScrollTargetDescription, command: ContainerScrollCommand)
        case unsafeProgrammaticScroll(ScrollTargetDescription, command: ContainerScrollCommand)
        case axisMismatch(
            target: ScrollTargetDescription,
            available: ScrollAxis,
            expected: ScrollAxis,
            command: ContainerScrollCommand
        )
        case noNamedVisibleContainer(ContainerName, axis: ScrollAxis, command: ContainerScrollCommand)
        case ambiguousNamedVisibleContainer(ContainerName, axis: ScrollAxis, command: ContainerScrollCommand)
        case noVisibleContainer(axis: ScrollAxis, command: ContainerScrollCommand)
        case ambiguousVisibleContainer(axis: ScrollAxis, command: ContainerScrollCommand)

        var command: ContainerScrollCommand {
            switch self {
            case .elementKnownButNotVisible(command: let command),
                 .elementAmbiguous(_, command: let command),
                 .elementNotFound(_, command: let command),
                 .missingScrollableAncestor(_, command: let command),
                 .unsafeProgrammaticScroll(_, command: let command),
                 .axisMismatch(target: _, available: _, expected: _, command: let command),
                 .noNamedVisibleContainer(_, axis: _, command: let command),
                 .ambiguousNamedVisibleContainer(_, axis: _, command: let command),
                 .noVisibleContainer(axis: _, command: let command),
                 .ambiguousVisibleContainer(axis: _, command: let command):
                return command
            }
        }

        var message: String {
            switch self {
            case .elementKnownButNotVisible(command: let command):
                return "\(command.diagnosticName) failed: target is known but not currently visible; "
                    + "target the element you want made actionable, or use scroll_to_visible as an explicit viewport inspection step."
            case .elementAmbiguous(let facts, command: let command):
                return "\(command.diagnosticName) failed: target is not uniquely resolved in the visible hierarchy; "
                    + "\(TargetResolutionDiagnostics.message(for: .ambiguous(facts)))\nNext: refine the semantic target with "
                    + "an ordinal or exact label, identifier, value, or trait from get_screen's visible interface."
            case .elementNotFound(let facts, command: _):
                return TargetResolutionDiagnostics.message(for: .notFound(facts))
            case .missingScrollableAncestor(let target, command: _):
                return "scroll target failed: observed \(target.description) with no live scrollable ancestor; "
                    + "target an element inside the intended scroll region"
            case .unsafeProgrammaticScroll(let target, command: _):
                return "scroll target failed: observed \(target.description) inside a scroll view that is unsafe "
                    + "for programmatic scrolling; target the element you want made actionable"
            case .axisMismatch(target: let target, available: let available, expected: let expected, command: _):
                return "scroll target failed: observed \(target.description) inside a scroll view that supports "
                    + "\(Navigation.axisDescription(available)); expected \(Navigation.axisDescription(expected)); "
                    + "try a matching scroll direction or target an element inside the intended scroll region"
            case .noNamedVisibleContainer(let containerName, axis: let axis, command: let command):
                return "\(command.diagnosticName) failed: no visible scroll container named \(containerName.rawValue) "
                    + "supports \(Navigation.axisDescription(axis)); refresh get_interface and use a current containerName"
            case .ambiguousNamedVisibleContainer(let containerName, axis: let axis, command: let command):
                return "\(command.diagnosticName) ambiguous: multiple visible scroll containers named \(containerName.rawValue) "
                    + "support \(Navigation.axisDescription(axis)); refresh get_interface and use a current containerName"
            case .noVisibleContainer(axis: let axis, command: let command):
                return "\(command.diagnosticName) failed: no visible scroll container supports \(Navigation.axisDescription(axis))"
            case .ambiguousVisibleContainer(axis: let axis, command: let command):
                return "\(command.diagnosticName) ambiguous: multiple visible scroll containers support "
                    + "\(Navigation.axisDescription(axis)); target an element inside the intended scroll region"
            }
        }
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
        command: ContainerScrollCommand
    ) -> ContainerScrollResolution {
        switch selection {
        case .element(let target):
            let visibleResolution = stash.resolveVisibleTarget(target)
            let resolved: TheStash.ScreenElement
            switch visibleResolution {
            case .resolved(let screenElement):
                resolved = screenElement
            case .notFound, .ambiguous:
                return .failed(liveScrollElementFailure(target, command: command))
            }
            let targetDescription = Self.ScrollTargetDescription(resolved)
            guard let scrollView = stash.liveScrollView(for: resolved) else {
                return .failed(.missingScrollableAncestor(targetDescription, command: command))
            }
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else {
                return .failed(.unsafeProgrammaticScroll(targetDescription, command: command))
            }
            let availableAxis = Self.scrollableAxis(contentSize: scrollView.contentSize, frame: scrollView.frame)
            guard availableAxis.contains(axis) else {
                return .failed(.axisMismatch(
                    target: targetDescription,
                    available: availableAxis,
                    expected: axis,
                    command: command
                ))
            }
            return .resolved(.uiScrollView(scrollView))
        case .container(let containerName):
            let candidates = scrollCandidates(requiredAxis: axis).filter {
                stash.liveContainerName(forPath: $0.path) == containerName
            }
            guard !candidates.isEmpty else {
                return .failed(.noNamedVisibleContainer(containerName, axis: axis, command: command))
            }
            guard candidates.count == 1, let plan = candidates.first else {
                return .failed(.ambiguousNamedVisibleContainer(containerName, axis: axis, command: command))
            }
            return .resolved(plan.target)
        case .visibleContainer:
            let candidates = scrollCandidates(requiredAxis: axis)
            guard !candidates.isEmpty else {
                return .failed(.noVisibleContainer(axis: axis, command: command))
            }
            guard candidates.count == 1, let plan = candidates.first else {
                return .failed(.ambiguousVisibleContainer(axis: axis, command: command))
            }
            return .resolved(plan.target)
        }
    }

    func scrollCandidates(
        requiredAxis axis: ScrollAxis?
    ) -> [ScrollPlan] {
        let indexedContainers = stash.latestObservedLiveHierarchy.pathIndexedContainers
        let safeSwipeBounds = currentSwipeSafeBounds(in: indexedContainers)

        return indexedContainers.compactMap { item -> ScrollPlan? in
            let container = item.container
            let path = item.path
            guard let contentSize = container.scrollableContentSize else { return nil }

            if let axis, !Self.scrollableAxis(of: container).contains(axis) {
                return nil
            }

            if let view = self.stash.liveScrollableContainerView(forPath: path),
               view.window != nil,
               Self.isObscuredByPresentation(view: view) {
                return nil
            }
            guard let target = self.scrollableTarget(
                for: ScrollContainerEvidence(
                    container: container,
                    path: path,
                    contentSize: contentSize
                ),
                safeSwipeBounds: safeSwipeBounds
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
        scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize,
            safeSwipeBounds: currentSwipeSafeBounds()
        )
    }

    private func scrollableTarget(
        for evidence: ScrollContainerEvidence,
        safeSwipeBounds: CGRect
    ) -> ScrollableTarget? {
        scrollableTarget(
            for: evidence.container,
            path: evidence.path,
            contentSize: evidence.contentSize,
            safeSwipeBounds: safeSwipeBounds
        )
    }

    private func scrollableTarget(
        for container: AccessibilityContainer,
        path: TreePath? = nil,
        contentSize: AccessibilitySize,
        safeSwipeBounds: CGRect
    ) -> ScrollableTarget? {
        let cgContentSize = contentSize.cgSize
        if let path,
           let scrollView = stash.liveScrollableContainerView(forPath: path) {
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
            return .uiScrollView(scrollView)
        }
        guard let screenFrame = safeSwipeFrame(from: container.frame.cgRect, safeBounds: safeSwipeBounds) else {
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
        safeSwipeFrame(from: frame, safeBounds: currentSwipeSafeBounds())
    }

    private func safeSwipeFrame(from frame: CGRect, safeBounds: CGRect) -> CGRect? {
        let safeIntersection = frame.intersection(safeBounds)
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
        currentSwipeSafeBounds(in: stash.latestObservedLiveHierarchy.pathIndexedContainers)
    }

    private func currentSwipeSafeBounds(in containers: [PathIndexedAccessibilityContainer]) -> CGRect {
        let screen = ScreenMetrics.current.bounds
        let tabBarTop = containers
            .compactMap { container -> CGFloat? in
                guard case .tabBar = container.container.type else { return nil }
                return container.container.frame.minY
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
    private func liveScrollElementFailure(
        _ target: AccessibilityTarget,
        command: ContainerScrollCommand
    ) -> ContainerScrollFailure {
        switch stash.resolveTarget(target) {
        case .resolved:
            return .elementKnownButNotVisible(command: command)
        case .ambiguous(let facts):
            return .elementAmbiguous(facts, command: command)
        case .notFound(let facts):
            return .elementNotFound(facts, command: command)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
