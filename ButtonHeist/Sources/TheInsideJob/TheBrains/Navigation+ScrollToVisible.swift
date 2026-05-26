#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

// MARK: - Scroll To Visible

extension Navigation {

    private static let comfortMarginFraction: CGFloat = 1.0 / 6.0

    struct SemanticActionableTarget {
        let normalizedTarget: TheStash.NormalizedTarget
        let resolvedTarget: TheStash.ResolvedTarget
        let liveTarget: TheStash.LiveActionTarget
    }

    struct SemanticContainerActionableTarget {
        let resolvedTarget: TheStash.ResolvedContainerTarget
        let liveTarget: TheStash.LiveContainerTarget
    }

    enum SemanticActionabilityResult {
        case actionable(SemanticActionableTarget)
        case failed(SemanticActionabilityFailure)

        var failure: SemanticActionabilityFailure? {
            if case .failed(let failure) = self { return failure }
            return nil
        }
    }

    enum SemanticContainerActionabilityResult {
        case actionable(SemanticContainerActionableTarget)
        case failed(SemanticActionabilityFailure)
    }

    enum SemanticActionabilityFailureStep: String {
        case notFound
        case ambiguous
        case noRevealPath
        case staleRefresh
        case geometryNotActionable
    }

    struct SemanticActionabilityFailure {
        let failedStep: SemanticActionabilityFailureStep
        let method: ActionMethod?
        let message: String

        static func notFound(_ message: String) -> SemanticActionabilityFailure {
            SemanticActionabilityFailure(
                failedStep: .notFound,
                method: .elementNotFound,
                message: classifiedMessage(step: .notFound, message: message)
            )
        }

        static func ambiguous(_ message: String) -> SemanticActionabilityFailure {
            SemanticActionabilityFailure(
                failedStep: .ambiguous,
                method: .elementNotFound,
                message: classifiedMessage(step: .ambiguous, message: message)
            )
        }

        static func noRevealPath(_ message: String) -> SemanticActionabilityFailure {
            SemanticActionabilityFailure(
                failedStep: .noRevealPath,
                method: nil,
                message: classifiedMessage(step: .noRevealPath, message: message)
            )
        }

        static func staleRefresh(
            _ message: String,
            method: ActionMethod? = nil
        ) -> SemanticActionabilityFailure {
            SemanticActionabilityFailure(
                failedStep: .staleRefresh,
                method: method,
                message: classifiedMessage(step: .staleRefresh, message: message)
            )
        }

        static func geometryNotActionable(
            _ message: String,
            method: ActionMethod? = nil
        ) -> SemanticActionabilityFailure {
            SemanticActionabilityFailure(
                failedStep: .geometryNotActionable,
                method: method,
                message: classifiedMessage(step: .geometryNotActionable, message: message)
            )
        }

        static func elementNotFound(_ message: String) -> SemanticActionabilityFailure {
            notFound(message)
        }

        static func actionFailed(_ message: String) -> SemanticActionabilityFailure {
            noRevealPath(message)
        }

        func interactionResult(commandMethod: ActionMethod) -> TheSafecracker.InteractionResult {
            .failure(method ?? commandMethod, message: message)
        }

        private static func classifiedMessage(
            step: SemanticActionabilityFailureStep,
            message: String
        ) -> String {
            guard !message.contains("[\(step.rawValue)]") else { return message }
            return "semantic actionability failed [\(step.rawValue)]: \(message)"
        }
    }

    /// Reveal a target. If already visible, nudge it into the comfort zone. If
    /// it is known-only, execute a semantic reveal plan against a live parent
    /// derived from the current graph, then prove success through a fresh
    /// visible resolution.
    func executeScrollToVisible(
        _ target: ScrollToVisibleTarget,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        await executeScrollToVisible(
            elementTarget: target.elementTarget,
            recordedScreen: recordedScreen
        )
    }

    func executeScrollToVisible(
        elementTarget: (any SemanticElementTarget)?,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        guard let elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for \(ScrollMode.toVisible.canonicalCommand)")
        }

        if recordedScreen == nil {
            stash.refresh()
        }

        let knownScreen = recordedScreen ?? stash.currentScreen
        let normalizedTarget = stash.normalizeTarget(elementTarget, in: knownScreen)
        switch await makeActionable(
            for: normalizedTarget,
            method: .scrollToVisible,
            deallocatedBoundary: "scroll_to_visible dispatch"
        ) {
        case .actionable:
            return .success(method: .scrollToVisible)
        case .failed(let failure):
            return .failure(.scrollToVisible, message: failure.message)
        }
    }

    private static var interactionComfortZone: CGRect {
        let bounds = ScreenMetrics.current.bounds
        return bounds.insetBy(
            dx: bounds.width * comfortMarginFraction,
            dy: bounds.height * comfortMarginFraction
        )
    }

    func makeActionable(
        for normalizedTarget: TheStash.NormalizedTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        allowingStaleRefresh: Bool = true
    ) async -> SemanticActionabilityResult {
        if let preparationFailure = await prepareActionability(for: normalizedTarget) {
            return .failed(preparationFailure)
        }

        let resolved: TheStash.ResolvedTarget
        if let pendingRotorResult = stash.activePendingRotorResult(for: normalizedTarget.originalTarget) {
            resolved = TheStash.ResolvedTarget(screenElement: pendingRotorResult)
        } else {
            switch stash.resolveVisibleTarget(normalizedTarget.executableTarget) {
            case .resolved(let target):
                resolved = target
            case .notFound(let diagnostics):
                return .failed(.staleRefresh(
                    normalizedTarget.diagnostics("target was not found in fresh live geometry: \(diagnostics)")
                ))
            case .ambiguous(_, let diagnostics):
                return .failed(.ambiguous(normalizedTarget.diagnostics(diagnostics)))
            }
        }

        switch stash.resolveLiveActionTarget(for: resolved) {
        case .resolved(let liveTarget):
            return await ensureLiveGeometryActionable(
                liveTarget,
                normalizedTarget: normalizedTarget,
                method: method,
                deallocatedBoundary: deallocatedBoundary,
                allowingStaleRefresh: allowingStaleRefresh
            )
        case .objectUnavailable:
            let message = normalizedTarget.diagnostics(
                ActionCapabilityDiagnostic.elementDeallocated(
                    boundary: deallocatedBoundary,
                    element: resolved.screenElement,
                    isInflated: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            )
            guard allowingStaleRefresh else {
                return .failed(.staleRefresh(message, method: .elementDeallocated))
            }
            refresh()
            let refreshed = await makeActionable(
                for: normalizedTarget,
                method: method,
                deallocatedBoundary: deallocatedBoundary,
                allowingStaleRefresh: false
            )
            if case .actionable = refreshed {
                return refreshed
            }
            return .failed(.staleRefresh(
                message
                    + "\nrefresh observed: "
                    + (refreshed.failure?.message ?? "unknown"),
                method: .elementDeallocated
            ))
        case .geometryUnavailable:
            return .failed(.geometryNotActionable(
                normalizedTarget.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: resolved.screenElement,
                        isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                    )
                ),
                method: method
            ))
        }
    }

    private func ensureLiveGeometryActionable(
        _ liveTarget: TheStash.LiveActionTarget,
        normalizedTarget: TheStash.NormalizedTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        allowingStaleRefresh: Bool
    ) async -> SemanticActionabilityResult {
        if Self.liveGeometryIsAlreadyUsable(
            frame: liveTarget.frame,
            activationPoint: liveTarget.activationPoint
        ) {
            return .actionable(SemanticActionableTarget(
                normalizedTarget: normalizedTarget,
                resolvedTarget: liveTarget.resolvedTarget,
                liveTarget: liveTarget
            ))
        }

        let resolved = liveTarget.resolvedTarget
        guard allowingStaleRefresh else {
            return .failed(.geometryNotActionable(
                normalizedTarget.diagnostics(
                    "target \(Self.describeScrollTarget(resolved.screenElement)) "
                        + "did not become actionable after semantic reveal"
                ),
                method: method
            ))
        }
        guard let scrollView = stash.liveScrollView(for: resolved.screenElement) else {
            return .failed(.noRevealPath(normalizedTarget.diagnostics(
                "target \(Self.describeScrollTarget(resolved.screenElement)) "
                    + "has no live scrollable ancestor to make actionable"
            )))
        }
        guard safecracker.scrollToMakeVisible(
            liveTarget.frame,
            in: scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) else {
            return .failed(.geometryNotActionable(
                normalizedTarget.diagnostics(
                    "target \(Self.describeScrollTarget(resolved.screenElement)) "
                        + "could not be scrolled fully on-screen"
                ),
                method: method
            ))
        }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        refresh()
        return await makeActionable(
            for: normalizedTarget,
            method: method,
            deallocatedBoundary: deallocatedBoundary,
            allowingStaleRefresh: false
        )
    }

    private func prepareActionability(
        for normalizedTarget: TheStash.NormalizedTarget
    ) async -> SemanticActionabilityFailure? {
        guard stash.activePendingRotorResult(for: normalizedTarget.originalTarget) == nil else {
            return nil
        }

        // Source screens derive only semantic identity. Reveal and geometry
        // authority always come from the current live graph.
        switch stash.resolveTarget(normalizedTarget.executableTarget) {
        case .resolved(let semanticTarget):
            let reveal = stash.executeSemanticRevealPlan(for: semanticTarget.screenElement)
            if case .failed = reveal {
                return .noRevealPath(semanticRevealPlanFailureMessage(semanticTarget.screenElement))
            }
            if reveal.didReveal {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                refresh()
            }
            return nil
        case .notFound(let diagnostics):
            return .notFound(normalizedTarget.diagnostics(diagnostics))
        case .ambiguous(_, let diagnostics):
            return .ambiguous(normalizedTarget.diagnostics(diagnostics))
        }
    }

    func makeContainerActionable(
        matcher: ContainerMatcher,
        ordinal: Int?,
        method: ActionMethod,
        allowingStaleRefresh: Bool = true
    ) async -> SemanticContainerActionabilityResult {
        switch stash.resolveContainerTarget(matcher, ordinal: ordinal) {
        case .resolved(let resolvedTarget):
            return await makeResolvedContainerActionable(
                resolvedTarget,
                matcher: matcher,
                ordinal: ordinal,
                method: method,
                allowingStaleRefresh: allowingStaleRefresh
            )
        case .notFound(let diagnostics):
            return .failed(.notFound("container target could not be made actionable: \(diagnostics)"))
        case .ambiguous(_, let diagnostics):
            return .failed(.ambiguous("container target is ambiguous: \(diagnostics)"))
        }
    }

    private func makeResolvedContainerActionable(
        _ resolvedTarget: TheStash.ResolvedContainerTarget,
        matcher: ContainerMatcher,
        ordinal: Int?,
        method: ActionMethod,
        allowingStaleRefresh: Bool
    ) async -> SemanticContainerActionabilityResult {
        switch stash.resolveLiveContainerTarget(for: resolvedTarget) {
        case .resolved(let liveTarget):
            if Self.liveGeometryIsAlreadyUsable(
                frame: liveTarget.frame,
                activationPoint: liveTarget.activationPoint
            ) {
                return .actionable(SemanticContainerActionableTarget(
                    resolvedTarget: resolvedTarget,
                    liveTarget: liveTarget
                ))
            }
            guard allowingStaleRefresh else {
                return .failed(.geometryNotActionable(
                    "container target \(TheStash.containerCandidateSummary(resolvedTarget)) "
                        + "did not become actionable after semantic reveal",
                    method: method
                ))
            }
            guard let contentFrame = resolvedTarget.contentFrame else {
                return .failed(.noRevealPath(
                    "container target \(TheStash.containerCandidateSummary(resolvedTarget)) "
                        + "has no content-space position to make actionable"
                ))
            }
            guard let scrollView = stash.liveScrollView(forContainerPath: resolvedTarget.path) else {
                return .failed(.noRevealPath(
                    "container target \(TheStash.containerCandidateSummary(resolvedTarget)) "
                        + "has no live scrollable ancestor to make actionable"
                ))
            }
            guard !scrollView.bhIsUnsafeForProgrammaticScrolling else {
                return .failed(.geometryNotActionable(
                    "container target \(TheStash.containerCandidateSummary(resolvedTarget)) "
                        + "is inside a scroll view that is unsafe for programmatic semantic reveal",
                    method: method
                ))
            }
            scrollView.setContentOffset(
                TheStash.semanticRevealTargetOffset(for: contentFrame.origin, in: scrollView),
                animated: false
            )
            await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            refresh()
            return await makeContainerActionable(
                matcher: matcher,
                ordinal: ordinal,
                method: method,
                allowingStaleRefresh: false
            )
        case .objectUnavailable:
            guard allowingStaleRefresh else {
                return .failed(.staleRefresh(
                    "container target became stale before dispatch",
                    method: method
                ))
            }
            refresh()
            return await makeContainerActionable(
                matcher: matcher,
                ordinal: ordinal,
                method: method,
                allowingStaleRefresh: false
            )
        case .geometryUnavailable:
            guard allowingStaleRefresh else {
                return .failed(.geometryNotActionable(
                    "container target has no fresh actionable geometry",
                    method: method
                ))
            }
            refresh()
            return await makeContainerActionable(
                matcher: matcher,
                ordinal: ordinal,
                method: method,
                allowingStaleRefresh: false
            )
        }
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

    private static func liveGeometryIsAlreadyUsable(frame: CGRect, activationPoint: CGPoint) -> Bool {
        ScreenMetrics.current.bounds.contains(frame)
            || interactionComfortZone.contains(activationPoint)
    }

    private func semanticRevealPlanFailureMessage(_ entry: Screen.ScreenElement) -> String {
        let description = Self.describeScrollTarget(entry)
        switch stash.resolveSemanticRevealScrollView(for: entry) {
        case .resolved:
            return "semantic reveal plan for known target \(description) could not be executed"
        case .failed(.missingContentOrigin):
            return "known target \(description) has no content-space position"
        case .failed(.noLiveScrollableAncestor):
            return "known target \(description) has no live scrollable ancestor in the current semantic graph"
        case .failed(.unsafeProgrammaticScroll):
            return "known target \(description) is inside a scroll view that is unsafe for programmatic semantic reveal"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
