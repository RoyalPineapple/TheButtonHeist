#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

// MARK: - Semantic Actionability

/// Central semantic actionability path.
///
/// Semantic commands name a target. This owner absorbs viewport mechanics:
/// resolve semantic identity, execute the reveal plan, refresh, acquire fresh
/// accessibility geometry, and classify the failed contract if any step cannot
/// make the target actionable.
@MainActor
final class SemanticActionability {

    private let stash: TheStash
    private let safecracker: TheSafecracker
    private let tripwire: TheTripwire

    private static let comfortMarginFraction: CGFloat = 1.0 / 6.0
    private static let postScrollLayoutFrames = Navigation.postScrollLayoutFrames

    init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
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

        var failure: SemanticActionabilityFailure? {
            if case .failed(let failure) = self { return failure }
            return nil
        }
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

    private enum ActivationPointPlacement {
        case usable
        case refreshed
        case failed(SemanticActionabilityFailure)
    }

    @discardableResult
    private func refresh() -> Screen? {
        stash.refresh()
    }

    /// Reveal a target. If already visible, nudge it into the comfort zone. If
    /// it is known-only, execute a semantic reveal plan against a live parent
    /// derived from the current graph, then prove success through a fresh
    /// visible resolution.
    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> TheSafecracker.InteractionResult {
        await executeScrollToVisible(elementTarget: .currentCapture(target.elementTarget))
    }

    func executeScrollToVisible(elementTarget: SemanticElementTarget?) async -> TheSafecracker.InteractionResult {
        guard let elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for scroll_to_visible")
        }

        stash.refresh()

        let normalizedTarget = stash.normalizeTarget(elementTarget)
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
        deallocatedBoundary: String
    ) async -> SemanticActionabilityResult {
        guard let executableTarget = normalizedTarget.executableTarget else {
            return .failed(.notFound(normalizedTarget.validationFailureMessage))
        }
        if let failure = await prepareActionability(for: normalizedTarget) {
            return .failed(failure)
        }

        return await makeElementActionable(
            normalizedTarget: normalizedTarget,
            executableTarget: executableTarget,
            method: method,
            deallocatedBoundary: deallocatedBoundary,
            canRefreshLiveTarget: true
        )
    }

    private func makeElementActionable(
        normalizedTarget: TheStash.NormalizedTarget,
        executableTarget: ElementTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        canRefreshLiveTarget: Bool
    ) async -> SemanticActionabilityResult {
        let resolvedTarget: TheStash.ResolvedTarget
        switch stash.resolveVisibleTarget(executableTarget) {
        case .resolved(let target):
            resolvedTarget = target
        case .notFound(let diagnostics):
            return .failed(.staleRefresh(
                normalizedTarget.diagnostics("target was not found in fresh live geometry: \(diagnostics)")
            ))
        case .ambiguous(_, let diagnostics):
            return .failed(.ambiguous(normalizedTarget.diagnostics(diagnostics)))
        }

        switch stash.resolveLiveActionTarget(for: resolvedTarget) {
        case .resolved(let liveTarget):
            switch await placeElementActivationPoint(
                liveTarget,
                normalizedTarget: normalizedTarget,
                method: method,
                canAdjustPlacement: canRefreshLiveTarget
            ) {
            case .usable:
                return .actionable(SemanticActionableTarget(
                    normalizedTarget: normalizedTarget,
                    resolvedTarget: resolvedTarget,
                    liveTarget: liveTarget
                ))
            case .refreshed:
                return await makeElementActionable(
                    normalizedTarget: normalizedTarget,
                    executableTarget: executableTarget,
                    method: method,
                    deallocatedBoundary: deallocatedBoundary,
                    canRefreshLiveTarget: false
                )
            case .failed(let failure):
                return .failed(failure)
            }
        case .objectUnavailable:
            let message = normalizedTarget.diagnostics(
                ActionCapabilityDiagnostic.elementDeallocated(
                    boundary: deallocatedBoundary,
                    element: resolvedTarget.screenElement,
                    isInflated: stash.visibleIds.contains(resolvedTarget.screenElement.heistId)
                )
            )
            guard canRefreshLiveTarget else {
                return .failed(.staleRefresh(message, method: .elementDeallocated))
            }
            refresh()
            let refreshed = await makeElementActionable(
                normalizedTarget: normalizedTarget,
                executableTarget: executableTarget,
                method: method,
                deallocatedBoundary: deallocatedBoundary,
                canRefreshLiveTarget: false
            )
            guard let observedFailure = refreshed.failure else { return refreshed }
            return .failed(.staleRefresh(
                message + "\nrefresh observed: " + observedFailure.message,
                method: .elementDeallocated
            ))
        case .geometryUnavailable:
            return .failed(.geometryNotActionable(
                normalizedTarget.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: resolvedTarget.screenElement,
                        isVisible: stash.visibleIds.contains(resolvedTarget.screenElement.heistId)
                    )
                ),
                method: method
            ))
        }
    }

    private func placeElementActivationPoint(
        _ liveTarget: TheStash.LiveActionTarget,
        normalizedTarget: TheStash.NormalizedTarget,
        method: ActionMethod,
        canAdjustPlacement: Bool
    ) async -> ActivationPointPlacement {
        let resolved = liveTarget.resolvedTarget
        let description = Self.describeScrollTarget(resolved.screenElement)
        return await placeActivationPoint(
            liveTarget.activationPoint,
            in: stash.liveScrollView(for: resolved.screenElement),
            method: method,
            canAdjustPlacement: canAdjustPlacement,
            noRevealPathMessage: normalizedTarget.diagnostics(
                "target \(description) has no live scrollable ancestor to make activation point actionable"
            ),
            notActionableAfterRevealMessage: normalizedTarget.diagnostics(
                "target \(description) did not become actionable after semantic reveal; "
                    + Self.liveGeometrySummary(liveTarget)
            ),
            unsafeProgrammaticScrollMessage: nil,
            scrollFailedMessage: normalizedTarget.diagnostics(
                "target \(description) activation point could not be brought on-screen"
            )
        )
    }

    private func placeContainerActivationPoint(
        _ liveTarget: TheStash.LiveContainerTarget,
        method: ActionMethod,
        canAdjustPlacement: Bool
    ) async -> ActivationPointPlacement {
        let resolvedTarget = liveTarget.resolvedTarget
        let description = TheStash.containerCandidateSummary(resolvedTarget)
        return await placeActivationPoint(
            liveTarget.activationPoint,
            in: stash.liveScrollView(forContainerPath: resolvedTarget.path),
            method: method,
            canAdjustPlacement: canAdjustPlacement,
            noRevealPathMessage: "container target \(description) has no live scrollable ancestor to make actionable",
            notActionableAfterRevealMessage: "container target \(description) "
                + "did not become actionable after semantic reveal",
            unsafeProgrammaticScrollMessage: "container target \(description) "
                + "is inside a scroll view that is unsafe for programmatic semantic reveal",
            scrollFailedMessage: "container target \(description) activation point could not be brought on-screen"
        )
    }

    private func placeActivationPoint(
        _ activationPoint: CGPoint,
        in scrollView: UIScrollView?,
        method: ActionMethod,
        canAdjustPlacement: Bool,
        noRevealPathMessage: String,
        notActionableAfterRevealMessage: String,
        unsafeProgrammaticScrollMessage: String?,
        scrollFailedMessage: String
    ) async -> ActivationPointPlacement {
        if Self.activationPointHasPreferredPlacement(activationPoint) {
            return .usable
        }
        if !canAdjustPlacement {
            if Self.activationPointIsOnScreen(activationPoint) {
                return .usable
            }
            return .failed(.geometryNotActionable(notActionableAfterRevealMessage, method: method))
        }
        guard let scrollView else {
            if Self.activationPointIsOnScreen(activationPoint) {
                return .usable
            }
            return .failed(.noRevealPath(noRevealPathMessage))
        }
        if scrollView.bhIsUnsafeForProgrammaticScrolling,
           let unsafeProgrammaticScrollMessage {
            if Self.activationPointIsOnScreen(activationPoint) {
                return .usable
            }
            return .failed(.geometryNotActionable(unsafeProgrammaticScrollMessage, method: method))
        }
        guard safecracker.scrollToMakeActivationPointVisible(
            activationPoint,
            in: scrollView,
            animated: false,
            preferredScreenRect: Self.interactionComfortZone,
            minimumScreenRect: ScreenMetrics.current.bounds
        ) else {
            if Self.activationPointIsOnScreen(activationPoint) {
                return .usable
            }
            return .failed(.geometryNotActionable(scrollFailedMessage, method: method))
        }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        refresh()
        return .refreshed
    }

    private func prepareActionability(
        for normalizedTarget: TheStash.NormalizedTarget
    ) async -> SemanticActionabilityFailure? {
        guard let executableTarget = normalizedTarget.executableTarget else {
            return .notFound(normalizedTarget.validationFailureMessage)
        }
        // Source screens derive only semantic identity. Reveal and geometry
        // authority always come from the current live graph.
        switch stash.resolveTarget(executableTarget) {
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

    func makeActionable(
        matcher: ContainerMatcher,
        ordinal: Int?,
        method: ActionMethod
    ) async -> SemanticContainerActionabilityResult {
        await makeContainerActionable(
            matcher: matcher,
            ordinal: ordinal,
            method: method,
            canRefreshLiveTarget: true
        )
    }

    private func makeContainerActionable(
        matcher: ContainerMatcher,
        ordinal: Int?,
        method: ActionMethod,
        canRefreshLiveTarget: Bool
    ) async -> SemanticContainerActionabilityResult {
        let resolvedTarget: TheStash.ResolvedContainerTarget
        switch stash.resolveContainerTarget(matcher, ordinal: ordinal) {
        case .resolved(let target):
            resolvedTarget = target
        case .notFound(let diagnostics):
            return .failed(.notFound("container target could not be made actionable: \(diagnostics)"))
        case .ambiguous(_, let diagnostics):
            return .failed(.ambiguous("container target is ambiguous: \(diagnostics)"))
        }

        switch stash.resolveLiveContainerTarget(for: resolvedTarget) {
        case .resolved(let liveTarget):
            switch await placeContainerActivationPoint(
                liveTarget,
                method: method,
                canAdjustPlacement: canRefreshLiveTarget
            ) {
            case .usable:
                return .actionable(SemanticContainerActionableTarget(
                    resolvedTarget: resolvedTarget,
                    liveTarget: liveTarget
                ))
            case .refreshed:
                return await makeContainerActionable(
                    matcher: matcher,
                    ordinal: ordinal,
                    method: method,
                    canRefreshLiveTarget: false
                )
            case .failed(let failure):
                return .failed(failure)
            }
        case .objectUnavailable:
            guard canRefreshLiveTarget else {
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
                canRefreshLiveTarget: false
            )
        case .geometryUnavailable:
            guard canRefreshLiveTarget else {
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
                canRefreshLiveTarget: false
            )
        }
    }

    func makeFirstResponderActionable(method: ActionMethod) async -> SemanticActionabilityFailure? {
        guard let heistId = stash.firstResponderHeistId else { return nil }
        let normalizedTarget = stash.normalizeTarget(.heistId(heistId))
        switch await makeActionable(
            for: normalizedTarget,
            method: method,
            deallocatedBoundary: "first responder actionability"
        ) {
        case .actionable:
            return nil
        case .failed(let failure):
            return failure
        }
    }

    private static func activationPointHasPreferredPlacement(_ activationPoint: CGPoint) -> Bool {
        interactionComfortZone.contains(activationPoint)
    }

    private static func activationPointIsOnScreen(_ activationPoint: CGPoint) -> Bool {
        ScreenMetrics.current.bounds.contains(activationPoint)
    }

    private static func liveGeometrySummary(_ liveTarget: TheStash.LiveActionTarget) -> String {
        "liveFrame=\(formatRect(liveTarget.frame)) "
            + "activationPoint=\(formatPoint(liveTarget.activationPoint)) "
            + "screenBounds=\(formatRect(ScreenMetrics.current.bounds))"
    }

    private static func formatRect(_ rect: CGRect) -> String {
        "(x:\(format(rect.origin.x)), y:\(format(rect.origin.y)), "
            + "w:\(format(rect.size.width)), h:\(format(rect.size.height)))"
    }

    private static func formatPoint(_ point: CGPoint) -> String {
        "(x:\(format(point.x)), y:\(format(point.y)))"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
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

    private static func describeScrollTarget(_ screenElement: TheStash.ScreenElement) -> String {
        Navigation.describeScrollTarget(screenElement)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
