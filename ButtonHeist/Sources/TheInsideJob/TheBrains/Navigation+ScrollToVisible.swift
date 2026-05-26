#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

// MARK: - Scroll To Visible

extension Navigation {

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

    /// Reveal a target. If already visible, nudge it into the comfort zone. If
    /// it is known-only, inflate it by scrolling a live parent derived from the
    /// current graph, then prove success through a fresh visible resolution.
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
        _ target: BatchScrollToVisibleTarget,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        await executeScrollToVisible(
            elementTarget: target.target,
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
        let ensureResult = await ensureOnScreen(for: normalizedTarget)
        guard ensureResult.succeeded else {
            return .failure(
                .scrollToVisible,
                message: ensureResult.failure?.message ?? "\(ScrollMode.toVisible.canonicalCommand) failed"
            )
        }

        let refreshedResolution = stash.resolveVisibleTarget(normalizedTarget.executableTarget)
        guard refreshedResolution.resolved != nil else {
            let suffix = refreshedResolution.diagnostics.isEmpty ? "" : ": \(refreshedResolution.diagnostics)"
            return .failure(
                .scrollToVisible,
                message: normalizedTarget.diagnostics("Element disappeared after inflation\(suffix)")
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

    func ensureOnScreen(for target: ElementTarget, recordedScreen: Screen? = nil) async -> EnsureOnScreenResult {
        await ensureOnScreen(for: target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    func ensureOnScreen(
        for target: any SemanticElementTarget,
        recordedScreen: Screen? = nil
    ) async -> EnsureOnScreenResult {
        let normalizedTarget = stash.normalizeTarget(target, in: recordedScreen ?? stash.currentScreen)
        return await ensureOnScreen(for: normalizedTarget)
    }

    func ensureOnScreen(for normalizedTarget: TheStash.NormalizedTarget) async -> EnsureOnScreenResult {
        let target = normalizedTarget.executableTarget
        if stash.activePendingRotorResult(for: normalizedTarget.originalTarget) != nil {
            return .operationLocalRotorResult
        }

        // Source screens only derive `executableTarget`. Positioning authority
        // comes from the current screen and live UIKit graph below.
        switch stash.resolveTarget(normalizedTarget.executableTarget) {
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
        case .failed(.unsafeProgrammaticScroll):
            return "\(ScrollMode.toVisible.canonicalCommand) failed: known target \(description) is inside a scroll view that is "
                + "unsafe for programmatic scrolling; use \(ScrollMode.search.canonicalCommand) to use semantic search"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
