#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

/// Converts a semantic target into a fresh live target that can receive the
/// requested accessibility action.
///
/// Invariant: the tree is the map; viewport movement updates the map; actions
/// resolve one map entry to a fresh live object with an on-screen activation point.
///
/// It owns reveal, bounded viewport movement, and live geometry acquisition.
/// It does not choose matchers, dispatch actions, or evaluate post-action
/// expectations.
@MainActor
final class ElementInflation {

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    var discoverTarget: (@MainActor (ElementTarget) async -> Screen?)?
    var revealKnownTarget: (@MainActor (HeistId) async -> Screen?)?

    /// Bounded window inflation waits for a target whose reveal failed to
    /// become resolvable before failing `noRevealPath`.
    ///
    /// Async-loaded destinations can produce a settled world that knows the
    /// target before its live scroll geometry is wired, so a reveal failure at
    /// the dispatch instant is not proof of unreachability — the very next
    /// settled capture can show the target framed and reachable. The wait is
    /// keyed off the target resolving, not a fixed retry count, because the
    /// gating operation is typically I/O (an in-flight content load).
    /// Field-measured arrivals land within ~500ms of dispatch; the standard
    /// settle timeout covers them with margin.
    var revealPathGraceTimeout: TimeInterval = SemanticObservationTiming.defaultTimeout

    /// Re-parse cadence inside the grace window when the app posts no
    /// transition-completion notifications. Apps that announce transitions
    /// wake the window immediately; silent apps fall back to this interval.
    var revealPathSilentReparseInterval: TimeInterval = 0.15

    static let comfortMarginFraction: CGFloat = 1.0 / 6.0
    static let stableGeometryQuietFrames = 2
    static let stableGeometryTimeout: TimeInterval = 1.0
    static var postScrollLayoutFrames: Int { Navigation.postScrollLayoutFrames }

    init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
    }

    struct InflatedElementTarget {
        let target: ElementTarget
        let screenElement: TheStash.ScreenElement
        let liveTarget: TheStash.LiveActionTarget
    }

    enum ElementInflationResult {
        case inflated(InflatedElementTarget)
        case failed(ElementInflationFailure)
    }

    enum ActivationPointPolicy {
        case requireOnscreen
        case liveObjectOnly
    }

    private enum TreeTargetMatch {
        case visible(TheStash.ScreenElement)
        case known(TheStash.ScreenElement)
    }

    private enum RetryReason: String, CustomStringConvertible, Sendable, Equatable {
        case objectDeallocated
        case staleTarget
        case activationPointOffscreen

        var description: String {
            rawValue
        }

        var failureDescription: String {
            switch self {
            case .objectDeallocated:
                return "the live object was deallocated"
            case .staleTarget:
                return "the live target no longer matched"
            case .activationPointOffscreen:
                return "the activation point stayed off-screen"
            }
        }
    }

    private enum ResolutionPass: Sendable, Equatable {
        case initial
        case afterRetry(attempt: Int, reason: RetryReason)

        var attempt: Int {
            switch self {
            case .initial:
                return 0
            case .afterRetry(let attempt, _):
                return attempt
            }
        }

        var allowsKnownFallback: Bool {
            switch self {
            case .initial, .afterRetry(_, .objectDeallocated):
                return true
            case .afterRetry(_, .staleTarget), .afterRetry(_, .activationPointOffscreen):
                return false
            }
        }
    }

    private enum InflationState: CustomStringConvertible {
        case resolving(ResolutionPass)
        case revealing(treeElement: TheStash.ScreenElement, attempt: Int)
        case refreshing(
            target: ElementTarget,
            screenElement: TheStash.ScreenElement,
            attempt: Int,
            didReveal: Bool
        )
        case placing(inflatedTarget: InflatedElementTarget, attempt: Int, didReveal: Bool)
        case retrying(failedAttempt: Int, reason: RetryReason)
        case inflated(InflatedElementTarget)
        case failed(ElementInflationFailure)

        var description: String {
            switch self {
            case .resolving:
                return "resolving"
            case .revealing(let treeElement, let attempt):
                return "revealing(element: \(treeElement.heistId), attempt: \(attempt))"
            case .refreshing(_, let screenElement, let attempt, let didReveal):
                return "refreshing(element: \(screenElement.heistId), didReveal: \(didReveal), attempt: \(attempt))"
            case .placing(let inflatedTarget, let attempt, let didReveal):
                return "placing(element: \(inflatedTarget.screenElement.heistId), didReveal: \(didReveal), attempt: \(attempt))"
            case .retrying(let failedAttempt, let reason):
                return "retrying(failedAttempt: \(failedAttempt), reason: \(reason.description))"
            case .inflated(let inflatedTarget):
                return "inflated(element: \(inflatedTarget.screenElement.heistId))"
            case .failed(let failure):
                return "failed(step: \(failure.failedStep.rawValue))"
            }
        }
    }

    private enum FreshElementTargetResolution {
        case success(InflatedElementTarget)
        case retry(RetryReason)
        case failure(ElementInflationFailure)
    }

    private enum RevealPathGraceOutcome {
        case resolved(TheStash.ScreenElement, didReveal: Bool)
        case failed(ElementInflationFailure)
        case timedOut
    }

    enum ElementInflationFailureStep: String {
        case notFound
        case ambiguous
        case noRevealPath
        case staleRefresh
        case geometryNotActionable
    }

    struct ElementInflationFailure: Error {
        let failedStep: ElementInflationFailureStep
        let failureKind: TheSafecracker.FailureKind
        let message: String

        static func notFound(_ message: String) -> ElementInflationFailure {
            .init(.notFound, failureKind: .targetUnavailable, message: message)
        }
        static func ambiguous(_ message: String) -> ElementInflationFailure {
            .init(.ambiguous, failureKind: .targetUnavailable, message: message)
        }
        static func noRevealPath(_ message: String) -> ElementInflationFailure {
            .init(.noRevealPath, failureKind: .actionFailed, message: message)
        }

        static func staleRefresh(
            _ message: String,
            failureKind: TheSafecracker.FailureKind = .actionFailed
        ) -> ElementInflationFailure {
            .init(.staleRefresh, failureKind: failureKind, message: message)
        }

        static func geometryNotActionable(
            _ message: String,
            failureKind: TheSafecracker.FailureKind = .actionFailed
        ) -> ElementInflationFailure {
            .init(.geometryNotActionable, failureKind: failureKind, message: message)
        }

        func interactionResult(commandMethod: ActionMethod) -> TheSafecracker.InteractionResult {
            .failure(commandMethod, message: message, failureKind: failureKind)
        }

        private init(
            _ step: ElementInflationFailureStep,
            failureKind: TheSafecracker.FailureKind,
            message: String
        ) {
            failedStep = step
            self.failureKind = failureKind
            self.message = message.contains("[\(step.rawValue)]")
                ? message
                : "element inflation failed [\(step.rawValue)]: \(message)"
        }
    }

    static var interactionComfortZone: CGRect {
        let bounds = ScreenMetrics.current.bounds
        return bounds.insetBy(dx: bounds.width * comfortMarginFraction, dy: bounds.height * comfortMarginFraction)
    }

    func inflate(
        for target: ElementTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy = .requireOnscreen
    ) async -> ElementInflationResult {
        stash.refreshCurrentVisibleTree()
        var state: InflationState = .resolving(.initial)
        let maxAttempts = 2

        while true {
            switch state {
            case .resolving(let pass):
                switch await findTargetInTree(target, allowKnownFallback: pass.allowsKnownFallback) {
                case .success(.visible(let treeElement)):
                    transition(
                        &state,
                        to: .refreshing(
                            target: target,
                            screenElement: treeElement,
                            attempt: pass.attempt,
                            didReveal: false
                        )
                    )
                case .success(.known(let treeElement)):
                    transition(&state, to: .revealing(treeElement: treeElement, attempt: pass.attempt))
                case .failure(let failure):
                    transition(&state, to: .failed(failure))
                }

            case .revealing(let treeElement, let attempt):
                transition(&state, to: await stateAfterReveal(treeElement, target: target, attempt: attempt))

            case .refreshing(let target, let screenElement, let attempt, let didReveal):
                transition(
                    &state,
                    to: await stateAfterRefresh(
                        target: target,
                        screenElement: screenElement,
                        didReveal: didReveal,
                        attempt: attempt,
                        method: method,
                        deallocatedBoundary: deallocatedBoundary,
                        activationPointPolicy: activationPointPolicy
                    )
                )

            case .placing(let inflatedTarget, let attempt, let didReveal):
                transition(
                    &state,
                    to: await stateAfterPlacement(
                        inflatedTarget,
                        didReveal: didReveal,
                        attempt: attempt,
                        method: method
                    )
                )

            case .retrying(let failedAttempt, let reason):
                let nextAttempt = failedAttempt + 1
                if nextAttempt >= maxAttempts {
                    transition(
                        &state,
                        to: .failed(retryExhaustedFailure(reason: reason, maxAttempts: maxAttempts))
                    )
                } else {
                    await tripwire.yieldRealFrames(1)
                    stash.refreshCurrentVisibleTree()
                    transition(&state, to: .resolving(.afterRetry(attempt: nextAttempt, reason: reason)))
                }

            case .inflated(let result):
                return .inflated(result)

            case .failed(let failure):
                return .failed(failure)
            }
        }
    }

    private func stateAfterReveal(
        _ treeElement: TheStash.ScreenElement,
        target: ElementTarget,
        attempt: Int
    ) async -> InflationState {
        if case .success(let visible)? = visibleTargetResolution(target) {
            return .refreshing(
                target: target,
                screenElement: visible,
                attempt: attempt,
                didReveal: false
            )
        }

        let reveal = await revealSemanticTarget(treeElement)
        if case .failed(let failure) = reveal {
            switch refreshedVisibleTargetResolution(target) {
            case .success(let visible)?:
                return .refreshing(
                    target: target,
                    screenElement: visible,
                    attempt: attempt,
                    didReveal: false
                )
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                break
            }
            switch await awaitRevealPathGrace(for: target) {
            case .resolved(let resolved, let didReveal):
                return .refreshing(
                    target: target,
                    screenElement: resolved,
                    attempt: attempt,
                    didReveal: didReveal
                )
            case .failed(let graceFailure):
                return .failed(graceFailure)
            case .timedOut:
                return .failed(.noRevealPath(
                    semanticRevealFailureMessage(failure, entry: treeElement)
                        + "; no reveal path appeared within \(Int(revealPathGraceTimeout * 1_000))ms"
                ))
            }
        }
        return .refreshing(
            target: target,
            screenElement: treeElement,
            attempt: attempt,
            didReveal: reveal.didReveal
        )
    }

    private func refreshedVisibleTargetResolution(
        _ target: ElementTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure>? {
        guard stash.refreshCurrentVisibleTree() != nil else { return nil }
        return visibleTargetResolution(target)
    }

    /// Re-observe until a target whose reveal failed becomes resolvable, or
    /// the grace window expires.
    ///
    /// A reveal failure during a screen transition reads a mid-arrival world:
    /// the settled union can know the target before the destination finishes
    /// loading and wires live scroll geometry. The window wakes when the app
    /// posts a transition-completion notification (screenChanged or
    /// layoutChanged mean the change has already landed, so the next parse
    /// should find it); silent apps fall back to a coarse re-parse cadence.
    /// The target arriving on-viewport resolves visibly, and a fresh known
    /// entry that gained scroll membership earns one reveal retry.
    ///
    /// Every iteration suspends — first on the notification waiter, then on a
    /// one-frame real-time floor — so the window can never starve the main
    /// actor, and task cancellation exits promptly.
    private func awaitRevealPathGrace(for target: ElementTarget) async -> RevealPathGraceOutcome {
        let deadline = CFAbsoluteTimeGetCurrent() + revealPathGraceTimeout
        var cursor = stash.accessibilityNotifications.transitionCursor()
        var didRetryReveal = false
        while !Task.isCancelled {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }
            if let advanced = await stash.accessibilityNotifications.waitForTransitionEvent(
                after: cursor,
                timeout: min(revealPathSilentReparseInterval, remaining)
            ) {
                cursor = advanced
            }
            await tripwire.yieldRealFrames(1)
            guard !Task.isCancelled else { break }
            guard stash.refreshCurrentVisibleTree() != nil else { continue }
            switch visibleTargetResolution(target) {
            case .success(let visible)?:
                return .resolved(visible, didReveal: false)
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                break
            }
            guard !didRetryReveal,
                  case .success(let fresh) = knownSemanticTarget(target),
                  fresh.scrollMembership != nil
            else { continue }
            didRetryReveal = true
            let retryReveal = await revealSemanticTarget(fresh)
            if case .failed = retryReveal { continue }
            return .resolved(fresh, didReveal: retryReveal.didReveal)
        }
        return .timedOut
    }

    private func stateAfterRefresh(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement,
        didReveal: Bool,
        attempt: Int,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy
    ) async -> InflationState {
        switch resolveFreshElementTarget(
            target: target,
            screenElement: screenElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        ) {
        case .success(let inflatedTarget):
            if activationPointPolicy == .liveObjectOnly {
                return await stateAfterStableLiveGeometry(
                    inflatedTarget,
                    attempt: attempt,
                    method: method,
                    requireOnscreenActivationPoint: false
                )
            }
            return .placing(inflatedTarget: inflatedTarget, attempt: attempt, didReveal: didReveal)
        case .retry(let reason):
            return .retrying(failedAttempt: attempt, reason: reason)
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private func stateAfterPlacement(
        _ inflatedTarget: InflatedElementTarget,
        didReveal: Bool,
        attempt: Int,
        method: ActionMethod
    ) async -> InflationState {
        let liveTarget = inflatedTarget.liveTarget
        if ScreenMetrics.current.bounds.contains(liveTarget.activationPoint) {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                attempt: attempt,
                method: method,
                requireOnscreenActivationPoint: true
            )
        }
        if didReveal {
            return .failed(.geometryNotActionable(
                "target \(Navigation.ScrollTargetDescription(liveTarget.screenElement).description) "
                    + "did not become actionable after semantic reveal; "
                    + Self.liveGeometrySummary(liveTarget)
            ))
        }

        let screenElement = liveTarget.screenElement
        let description = Navigation.ScrollTargetDescription(screenElement).description
        let placement = await scrollActivationPointIntoBounds(
            liveTarget.activationPoint,
            in: stash.liveScrollView(for: screenElement),
            method: method,
            noScrollViewFailure: noScrollViewFailure(
                for: liveTarget,
                description: description,
                method: method
            ),
            unsafeProgrammaticScrollMessage: nil,
            scrollFailedMessage: "target \(description) activation point could not be brought on-screen"
        )
        switch placement {
        case .success(false):
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                attempt: attempt,
                method: method,
                requireOnscreenActivationPoint: true
            )
        case .success(true):
            return .retrying(failedAttempt: attempt, reason: .activationPointOffscreen)
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private struct LiveGeometrySample {
        let frame: CGRect
        let activationPoint: CGPoint

        init(_ target: TheStash.LiveActionTarget) {
            frame = target.frame
            activationPoint = target.activationPoint
        }

        init?(_ screenElement: TheStash.ScreenElement) {
            let frame = screenElement.element.bhFrame
            let activationPoint = screenElement.element.bhResolvedActivationPoint
            guard Self.isUsableFrame(frame),
                  Self.isUsablePoint(activationPoint)
            else { return nil }
            self.frame = frame
            self.activationPoint = activationPoint
        }

        func matches(_ other: LiveGeometrySample) -> Bool {
            frame.matchesForActionHandoff(other.frame)
                && activationPoint.matchesForActionHandoff(other.activationPoint)
        }

        private static func isUsableFrame(_ frame: CGRect) -> Bool {
            !frame.isNull
                && !frame.isEmpty
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }

        private static func isUsablePoint(_ point: CGPoint) -> Bool {
            point.x.isFinite && point.y.isFinite
        }
    }

    private func stateAfterStableLiveGeometry(
        _ inflatedTarget: InflatedElementTarget,
        attempt: Int,
        method: ActionMethod,
        requireOnscreenActivationPoint: Bool
    ) async -> InflationState {
        let deadline = CFAbsoluteTimeGetCurrent() + Self.stableGeometryTimeout
        var stableTarget = inflatedTarget
        var previous = LiveGeometrySample(inflatedTarget.liveTarget)
        var quietFrames = 1
        let shouldRefreshLiveCapture = shouldRefreshLiveCaptureForStableGeometry(inflatedTarget.liveTarget)
        if !shouldRefreshLiveCapture {
            await tripwire.yieldRealFrames(1)
            if requireOnscreenActivationPoint,
               !ScreenMetrics.current.bounds.contains(stableTarget.liveTarget.activationPoint) {
                return .retrying(failedAttempt: attempt, reason: .activationPointOffscreen)
            }
            return .inflated(stableTarget)
        }

        while !Task.isCancelled {
            guard CFAbsoluteTimeGetCurrent() < deadline else { break }
            await tripwire.yieldRealFrames(1)
            guard stash.refreshLiveCapture() != nil else { continue }
            switch visibleTargetResolution(inflatedTarget.target) {
            case .success(let currentScreenElement)?:
                guard let current = LiveGeometrySample(currentScreenElement) else {
                    return .failed(.geometryNotActionable(
                        ActionCapabilityDiagnostic.gestureTargetUnavailable(
                            method: method,
                            element: currentScreenElement,
                            isVisible: stash.visibleIds.contains(currentScreenElement.heistId)
                        )
                    ))
                }
                if requireOnscreenActivationPoint,
                   !ScreenMetrics.current.bounds.contains(current.activationPoint) {
                    return .retrying(failedAttempt: attempt, reason: .activationPointOffscreen)
                }
                let currentTarget = stableActionTarget(
                    target: inflatedTarget.target,
                    retainedTarget: stableTarget,
                    screenElement: currentScreenElement,
                    sample: current
                )
                if current.matches(previous) {
                    quietFrames += 1
                    stableTarget = currentTarget
                    if quietFrames >= Self.stableGeometryQuietFrames {
                        return .inflated(stableTarget)
                    }
                } else {
                    previous = current
                    stableTarget = currentTarget
                    quietFrames = 1
                }
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                continue
            }
        }

        return .failed(.geometryNotActionable(
            "target \(Navigation.ScrollTargetDescription(stableTarget.screenElement).description) "
                + "live geometry did not settle within \(Int(Self.stableGeometryTimeout * 1_000))ms; "
                + Self.liveGeometrySummary(stableTarget.liveTarget)
        ))
    }

    private func stableActionTarget(
        target: ElementTarget,
        retainedTarget: InflatedElementTarget,
        screenElement: TheStash.ScreenElement,
        sample: LiveGeometrySample
    ) -> InflatedElementTarget {
        if case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: screenElement),
           liveTarget.screenElement.matches(target) {
            return InflatedElementTarget(
                target: target,
                screenElement: liveTarget.screenElement,
                liveTarget: liveTarget
            )
        }
        let liveTarget = TheStash.LiveActionTarget(
            screenElement: screenElement,
            object: retainedTarget.liveTarget.object,
            frame: sample.frame,
            activationPoint: sample.activationPoint
        )
        return InflatedElementTarget(
            target: target,
            screenElement: screenElement,
            liveTarget: liveTarget
        )
    }

    private func shouldRefreshLiveCaptureForStableGeometry(_ target: TheStash.LiveActionTarget) -> Bool {
        if let view = target.object as? UIView {
            return view.window != nil
        }
        if let element = target.object as? UIAccessibilityElement,
           let view = element.accessibilityContainer as? UIView {
            return view.window != nil
        }
        return false
    }

    func inflateAfterActivationRefresh(
        for target: ElementTarget
    ) async -> ElementInflationResult {
        refreshLiveCaptureForActivation()
        return await inflate(
            for: target,
            method: .activate,
            deallocatedBoundary: "activation refresh"
        )
    }

    private func refreshLiveCaptureForActivation() {
        stash.refreshCurrentVisibleTree()
    }

    private func findTargetInTree(
        _ target: ElementTarget,
        allowKnownFallback: Bool
    ) async -> Result<TreeTargetMatch, ElementInflationFailure> {
        switch visibleTargetResolution(target) {
        case .success(let visible):
            return .success(.visible(visible))
        case .failure(let failure):
            return .failure(failure)
        case nil:
            break
        }
        if case .failure(let failure) = knownSemanticTarget(target),
           failure.failedStep == .ambiguous {
            return .failure(failure)
        }
        if let screen = await discoverTarget?(target) {
            stash.semanticObservationStream.commitSettledDiscoveryObservation(screen)
            switch visibleTargetResolution(target, in: screen) {
            case .success(let visible):
                return .success(.visible(visible))
            case .failure(let failure):
                return .failure(failure)
            case nil:
                return discoveredSemanticTarget(target)
            }
        }
        guard allowKnownFallback else {
            return currentVisibleTargetFailure(target)
        }
        switch knownSemanticTarget(target) {
        case .success(let screenElement):
            return .success(.known(screenElement))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func discoveredSemanticTarget(
        _ target: ElementTarget
    ) -> Result<TreeTargetMatch, ElementInflationFailure> {
        switch knownSemanticTarget(target) {
        case .success(let screenElement):
            return .success(.known(screenElement))
        case .failure(let failure) where failure.failedStep == .notFound:
            return .failure(failure)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func currentVisibleTargetFailure(
        _ target: ElementTarget
    ) -> Result<TreeTargetMatch, ElementInflationFailure> {
        switch stash.resolveVisibleTarget(target) {
        case .resolved(let screenElement):
            return .success(.visible(screenElement))
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound(let facts):
            return .failure(.staleRefresh(
                "target was not found after refreshing the current live tree: "
                    + TargetResolutionDiagnostics.message(for: .notFound(facts))
            ))
        }
    }

    private func knownSemanticTarget(
        _ target: ElementTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        switch stash.resolveTarget(target) {
        case .resolved(let screenElement):
            return .success(screenElement)
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound(let facts):
            return .failure(.notFound(TargetResolutionDiagnostics.message(for: .notFound(facts))))
        }
    }

    private func visibleTargetResolution(
        _ target: ElementTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure>? {
        visibleTargetResolution(target, in: stash.liveVisibleScreen)
    }

    private func visibleTargetResolution(
        _ target: ElementTarget,
        in screen: Screen
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure>? {
        switch stash.resolveTarget(target, in: screen.visibleOnly) {
        case .resolved(let screenElement):
            return .success(screenElement)
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound:
            return nil
        }
    }

    private func resolveFreshElementTarget(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> FreshElementTargetResolution {
        resolveLiveElementTarget(
            target: target,
            screenElement: screenElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        )
    }

    private func resolveLiveElementTarget(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> FreshElementTargetResolution {
        switch stash.resolveLiveActionTarget(for: screenElement) {
        case .resolved(let liveTarget):
            guard liveTarget.screenElement.matches(target) else {
                if let currentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                    target: target,
                    method: method
                ) {
                    return currentVisibleTarget
                }
                if stash.refreshLiveCapture() != nil,
                   let refreshedCurrentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                       target: target,
                       method: method
                   ) {
                    return refreshedCurrentVisibleTarget
                }
                return .retry(.staleTarget)
            }
            return .success(InflatedElementTarget(
                target: target,
                screenElement: liveTarget.screenElement,
                liveTarget: liveTarget
            ))
        case .objectUnavailable:
            if let currentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                target: target,
                method: method
            ) {
                return currentVisibleTarget
            }
            if stash.refreshLiveCapture() != nil,
               let refreshedCurrentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                   target: target,
                   method: method
               ) {
                return refreshedCurrentVisibleTarget
            }
            return .retry(.objectDeallocated)
        case .geometryUnavailable:
            return .failure(.geometryNotActionable(
                ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: screenElement,
                    isVisible: stash.visibleIds.contains(screenElement.heistId)
                )
            ))
        }
    }

    private func resolveCurrentVisibleLiveElementTarget(
        target: ElementTarget,
        method: ActionMethod
    ) -> FreshElementTargetResolution? {
        switch visibleTargetResolution(target) {
        case .success(let screenElement)?:
            if let liveCaptureTarget = resolveCurrentVisibleLiveCaptureTarget(
                target: target,
                method: method
            ) {
                return liveCaptureTarget
            }
            switch stash.resolveLiveActionTarget(for: screenElement) {
            case .resolved(let liveTarget):
                guard liveTarget.screenElement.matches(target) else {
                    return resolveCurrentVisibleLiveCaptureTarget(
                        target: target,
                        method: method
                    ) ?? .retry(.staleTarget)
                }
                return .success(InflatedElementTarget(
                    target: target,
                    screenElement: liveTarget.screenElement,
                    liveTarget: liveTarget
                ))
            case .objectUnavailable:
                return nil
            case .geometryUnavailable:
                return .failure(.geometryNotActionable(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: screenElement,
                        isVisible: stash.visibleIds.contains(screenElement.heistId)
                    )
                ))
            }
        case .failure(let failure)?:
            return .failure(failure)
        case nil:
            return nil
        }
    }

    private func resolveCurrentVisibleLiveCaptureTarget(
        target: ElementTarget,
        method: ActionMethod
    ) -> FreshElementTargetResolution? {
        guard let entry = currentVisibleLiveCaptureEntry(matching: target) else { return nil }
        guard let object = entry.ref?.object else { return nil }
        guard let sample = LiveGeometrySample(entry.screenElement) else {
            return .failure(.geometryNotActionable(
                ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: entry.screenElement,
                    isVisible: stash.visibleIds.contains(entry.heistId)
                )
            ))
        }
        let liveTarget = TheStash.LiveActionTarget(
            screenElement: entry.screenElement,
            object: object,
            frame: sample.frame,
            activationPoint: sample.activationPoint
        )
        return .success(InflatedElementTarget(
            target: target,
            screenElement: entry.screenElement,
            liveTarget: liveTarget
        ))
    }

    private func currentVisibleLiveCaptureEntry(
        matching target: ElementTarget
    ) -> LiveCapture.LiveElementEntry? {
        switch target {
        case .predicate(let predicate, let ordinal):
            let matches = stash.currentLiveCapture.orderedElementEntries()
                .filter { predicate.matches($0.element) }
            if let ordinal {
                guard matches.indices.contains(ordinal) else { return nil }
                return matches[ordinal]
            }
            guard matches.count == 1 else { return nil }
            return matches[0]
        }
    }

    private func transition(_ state: inout InflationState, to nextState: InflationState) {
        let currentDescription = state.description
        let nextDescription = nextState.description
        insideJobLogger.debug(
            "inflation: \(currentDescription, privacy: .public) -> \(nextDescription, privacy: .public)"
        )
        state = nextState
    }

    private func retryExhaustedFailure(
        reason: RetryReason,
        maxAttempts: Int
    ) -> ElementInflationFailure {
        let message = "inflation exhausted \(maxAttempts) retry attempts after \(reason.failureDescription)"
        switch reason {
        case .objectDeallocated, .staleTarget:
            return .staleRefresh(message, failureKind: .targetUnavailable)
        case .activationPointOffscreen:
            return .geometryNotActionable(message)
        }
    }

    private func noScrollViewFailure(
        for liveTarget: TheStash.LiveActionTarget,
        description: String,
        method: ActionMethod
    ) -> ElementInflationFailure {
        if ScreenMetrics.current.bounds.intersects(liveTarget.frame) {
            return .geometryNotActionable(
                "target \(description) has an activation point outside the screen; "
                    + Self.liveGeometrySummary(liveTarget)
            )
        }
        return .noRevealPath(
            "target \(description) has no live scrollable ancestor to make activation point actionable"
        )
    }

    func scrollActivationPointIntoBounds(
        _ activationPoint: CGPoint,
        in scrollView: UIScrollView?,
        method: ActionMethod,
        noScrollViewFailure: ElementInflationFailure,
        unsafeProgrammaticScrollMessage: String?,
        scrollFailedMessage: String
    ) async -> Result<Bool, ElementInflationFailure> {
        if Self.interactionComfortZone.contains(activationPoint) {
            return .success(false)
        }
        guard let scrollView else {
            if ScreenMetrics.current.bounds.contains(activationPoint) {
                return .success(false)
            }
            return .failure(noScrollViewFailure)
        }
        if scrollView.bhIsUnsafeForProgrammaticScrolling,
           let unsafeProgrammaticScrollMessage {
            if ScreenMetrics.current.bounds.contains(activationPoint) {
                return .success(false)
            }
            return .failure(.geometryNotActionable(unsafeProgrammaticScrollMessage))
        }
        guard safecracker.scrollToMakeScreenPointVisible(
            activationPoint,
            in: scrollView,
            animated: false,
            preferredScreenRect: Self.interactionComfortZone,
            minimumScreenRect: ScreenMetrics.current.bounds
        ) else {
            if ScreenMetrics.current.bounds.contains(activationPoint) {
                return .success(false)
            }
            return .failure(.geometryNotActionable(scrollFailedMessage))
        }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        stash.refreshTreeAfterViewportMove()
        return .success(true)
    }

    func inflateFirstResponder(method: ActionMethod) async -> ElementInflationFailure? {
        guard let screenElement = stash.firstResponderScreenElement(),
              let target = firstResponderTarget(for: screenElement) else { return nil }
        switch await inflate(
            for: target,
            method: method,
            deallocatedBoundary: "first responder inflation"
        ) {
        case .inflated:
            return nil
        case .failed(let failure):
            return failure
        }
    }

    private func firstResponderTarget(for screenElement: TheStash.ScreenElement) -> ElementTarget? {
        stash.minimumUniqueTarget(for: screenElement)
    }

}

extension ElementInflation.InflatedElementTarget {
    @MainActor
    func subjectEvidence(source: ActionSubjectEvidence.Source) -> ActionSubjectEvidence {
        ActionSubjectEvidence(
            source: source,
            target: target,
            element: TheStash.WireConversion.convert(screenElement.element)
        )
    }
}

private extension TheStash.ScreenElement {
    func matches(_ target: ElementTarget) -> Bool {
        switch target {
        case .predicate(let predicate, _):
            return predicate.matches(element)
        }
    }
}

private extension CGRect {
    func matchesForActionHandoff(_ other: CGRect) -> Bool {
        origin.matchesForActionHandoff(other.origin)
            && size.matchesForActionHandoff(other.size)
    }
}

private extension CGPoint {
    func matchesForActionHandoff(_ other: CGPoint) -> Bool {
        abs(x - other.x) < 0.5
            && abs(y - other.y) < 0.5
    }
}

private extension CGSize {
    func matchesForActionHandoff(_ other: CGSize) -> Bool {
        abs(width - other.width) < 0.5
            && abs(height - other.height) < 0.5
    }
}

#endif // canImport(UIKit) && DEBUG
