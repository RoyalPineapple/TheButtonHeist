#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

// MARK: - Scroll To Visible

extension Navigation {

    private static let comfortMarginFraction: CGFloat = 1.0 / 6.0

    enum SemanticVisibilityResult {
        case alreadyUsable
        case adjustedVisibleTarget
        case recoveredKnownOffscreen
        case operationLocalRotorResult
        case failed(SemanticActionabilityFailure)

        var succeeded: Bool {
            if case .failed = self { return false }
            return true
        }

        var failure: SemanticActionabilityFailure? {
            if case .failed(let failure) = self { return failure }
            return nil
        }
    }

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
        let ensureResult = await makeSemanticallyVisible(for: normalizedTarget)
        guard ensureResult.succeeded else {
            return .failure(
                .scrollToVisible,
                message: ensureResult.failure?.message ?? "\(ScrollMode.toVisible.canonicalCommand) failed"
            )
        }

        if case .operationLocalRotorResult = ensureResult {
            return .success(method: .scrollToVisible)
        }

        let refreshedResolution = stash.resolveVisibleTarget(normalizedTarget.executableTarget)
        guard refreshedResolution.resolved != nil else {
            let suffix = refreshedResolution.diagnostics.isEmpty ? "" : ": \(refreshedResolution.diagnostics)"
            return .failure(
                .scrollToVisible,
                message: SemanticActionabilityFailure.staleRefresh(
                    normalizedTarget.diagnostics("target disappeared after semantic reveal\(suffix)")
                ).message
            )
        }

        let message: String?
        switch ensureResult {
        case .alreadyUsable, .adjustedVisibleTarget:
            message = "Already visible"
        case .recoveredKnownOffscreen, .operationLocalRotorResult, .failed:
            message = nil
        }
        return .success(method: .scrollToVisible, message: message)
    }

    private static var interactionComfortZone: CGRect {
        let bounds = ScreenMetrics.current.bounds
        return bounds.insetBy(
            dx: bounds.width * comfortMarginFraction,
            dy: bounds.height * comfortMarginFraction
        )
    }

    func makeSemanticallyVisible(
        for target: ElementTarget,
        recordedScreen: Screen? = nil
    ) async -> SemanticVisibilityResult {
        await makeSemanticallyVisible(for: target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    func makeSemanticallyVisible(
        for target: any SemanticElementTarget,
        recordedScreen: Screen? = nil
    ) async -> SemanticVisibilityResult {
        let normalizedTarget = stash.normalizeTarget(target, in: recordedScreen ?? stash.currentScreen)
        return await makeSemanticallyVisible(for: normalizedTarget)
    }

    func makeSemanticallyVisible(for normalizedTarget: TheStash.NormalizedTarget) async -> SemanticVisibilityResult {
        let target = normalizedTarget.executableTarget
        if let pendingRotorResult = stash.activePendingRotorResult(for: normalizedTarget.originalTarget) {
            let ensureResult = await alignVisibleResolvedTarget(.init(screenElement: pendingRotorResult))
            guard ensureResult.succeeded else { return ensureResult }
            return .operationLocalRotorResult
        }

        // Source screens only derive `executableTarget`. Positioning authority
        // comes from the current screen and live UIKit graph below.
        switch stash.resolveTarget(normalizedTarget.executableTarget) {
        case .resolved(let semanticTarget):
            let reveal = stash.executeSemanticRevealPlan(for: semanticTarget.screenElement)
            if case .failed = reveal {
                return .failed(.noRevealPath(
                    semanticRevealPlanFailureMessage(semanticTarget.screenElement)
                ))
            }
            if reveal.didReveal {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                refresh()
            }
            let liveResolution = stash.resolveVisibleTarget(target)
            switch liveResolution {
            case .resolved(let liveTarget):
                let ensureResult = await alignVisibleResolvedTarget(liveTarget)
                guard ensureResult.succeeded else { return ensureResult }
                return reveal.didReveal ? .recoveredKnownOffscreen : ensureResult
            case .notFound(let diagnostics):
                let suffix = diagnostics.isEmpty ? "" : ": \(diagnostics)"
                return .failed(.staleRefresh(
                    normalizedTarget.diagnostics("target was not visible after semantic reveal\(suffix)")
                ))
            case .ambiguous(_, let diagnostics):
                return .failed(.ambiguous(normalizedTarget.diagnostics(diagnostics)))
            }
        case .notFound(let diagnostics):
            return .failed(.notFound(normalizedTarget.diagnostics(diagnostics)))
        case .ambiguous(_, let diagnostics):
            return .failed(.ambiguous(normalizedTarget.diagnostics(diagnostics)))
        }
    }

    func makeActionable(
        for normalizedTarget: TheStash.NormalizedTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        allowingStaleRefresh: Bool = true
    ) async -> SemanticActionabilityResult {
        if stash.activePendingRotorResult(for: normalizedTarget.originalTarget) == nil {
            switch stash.resolveVisibleTarget(normalizedTarget.executableTarget) {
            case .resolved:
                break
            case .ambiguous(_, let diagnostics):
                return .failed(.ambiguous(normalizedTarget.diagnostics(diagnostics)))
            case .notFound:
                let visibility = await makeSemanticallyVisible(for: normalizedTarget)
                if let failure = visibility.failure {
                    return .failed(failure)
                }
            }
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
            return .actionable(SemanticActionableTarget(
                normalizedTarget: normalizedTarget,
                resolvedTarget: resolved,
                liveTarget: liveTarget
            ))
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

    private func alignVisibleResolvedTarget(_ resolved: TheStash.ResolvedTarget) async -> SemanticVisibilityResult {
        let liveTarget: TheStash.LiveActionTarget
        switch stash.resolveLiveActionTarget(for: resolved) {
        case .resolved(let target):
            liveTarget = target
        case .objectUnavailable:
            return .failed(.staleRefresh(
                "visible target \(Self.describeScrollTarget(resolved.screenElement)) has no live dispatch object",
                method: .elementDeallocated
            ))
        case .geometryUnavailable:
            return .failed(.geometryNotActionable(
                "visible target \(Self.describeScrollTarget(resolved.screenElement)) has no usable live geometry"
            ))
        }

        if ScreenMetrics.current.bounds.contains(liveTarget.frame)
            || Self.interactionComfortZone.contains(liveTarget.activationPoint) {
            return .alreadyUsable
        }

        guard let scrollView = stash.liveScrollView(for: resolved.screenElement) else {
            return .failed(.noRevealPath(
                "visible target \(Self.describeScrollTarget(resolved.screenElement)) "
                    + "has no live scrollable ancestor to make actionable"
            ))
        }

        guard safecracker.scrollToMakeVisible(
            liveTarget.frame,
            in: scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) else {
            return .failed(.geometryNotActionable(
                "visible target \(Self.describeScrollTarget(resolved.screenElement)) "
                    + "could not be scrolled fully on-screen"
            ))
        }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        refresh()
        return .adjustedVisibleTarget
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
