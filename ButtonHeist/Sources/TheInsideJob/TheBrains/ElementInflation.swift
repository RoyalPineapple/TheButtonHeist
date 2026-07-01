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

    static let comfortMarginFraction: CGFloat = 1.0 / 6.0
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

    private typealias RetryReason = ElementInflationRetryReason
    private typealias ResolutionPass = ElementInflationResolutionPass

    private enum FreshElementTargetResolution {
        case success(InflatedElementTarget)
        case retry(RetryReason)
        case failure(ElementInflationFailure)
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
        let reducer = ElementInflationReducer(maxAttempts: maxAttempts)

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
                    to: stateAfterRefresh(
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
                switch reducer.reduce(
                    .retrying(failedAttempt: failedAttempt, reason: reason),
                    event: .retryReady
                ) {
                case .resolving(let pass):
                    stash.refreshCurrentVisibleTree()
                    transition(&state, to: .resolving(pass))
                case .retryExhausted(let reason):
                    transition(
                        &state,
                        to: .failed(retryExhaustedFailure(reason: reason, maxAttempts: maxAttempts))
                    )
                case .retrying:
                    transition(&state, to: .retrying(failedAttempt: failedAttempt, reason: reason))
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
            return .failed(.noRevealPath(semanticRevealFailureMessage(failure, entry: treeElement)))
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

    private func stateAfterRefresh(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement,
        didReveal: Bool,
        attempt: Int,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy
    ) -> InflationState {
        switch resolveFreshElementTarget(
            target: target,
            screenElement: screenElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        ) {
        case .success(let inflatedTarget):
            if activationPointPolicy == .liveObjectOnly {
                return .inflated(inflatedTarget)
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
            return .inflated(inflatedTarget)
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
            return .inflated(inflatedTarget)
        case .success(true):
            return .retrying(failedAttempt: attempt, reason: .activationPointOffscreen)
        case .failure(let failure):
            return .failed(failure)
        }
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
        if let revealable = uniquelyResolvedRevealableTarget(target) {
            return .success(revealable)
        }
        if let reachable = uniquelyResolvedReachableTarget(target) {
            return .success(reachable)
        }
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

    private func uniquelyResolvedRevealableTarget(_ target: ElementTarget) -> TheStash.ScreenElement? {
        uniquelyResolvedRevealableTarget(target, in: stash.settledSemanticScreen)
    }

    private func uniquelyResolvedRevealableTarget(
        _ target: ElementTarget,
        in screen: Screen
    ) -> TheStash.ScreenElement? {
        switch target {
        case .predicate(let predicate, ordinal: nil):
            let revealableMatches = stash.matchScreenElements(predicate, limit: 3, in: screen)
                .filter { $0.scrollMembership != nil && stash.liveScrollView(for: $0) != nil }
            return revealableMatches.count == 1 ? revealableMatches[0] : nil
        case .predicate:
            return nil
        }
    }

    private func uniquelyResolvedReachableTarget(_ target: ElementTarget) -> TheStash.ScreenElement? {
        uniquelyResolvedReachableTarget(target, in: stash.settledSemanticScreen)
    }

    private func uniquelyResolvedReachableTarget(
        _ target: ElementTarget,
        in screen: Screen
    ) -> TheStash.ScreenElement? {
        switch target {
        case .predicate(let predicate, ordinal: nil):
            let reachableMatches = stash.matchScreenElements(predicate, limit: 3, in: screen)
                .filter { $0.scrollMembership != nil }
            return reachableMatches.count == 1 ? reachableMatches[0] : nil
        case .predicate:
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
                return .retry(.staleTarget)
            }
            return .success(InflatedElementTarget(
                target: target,
                screenElement: liveTarget.screenElement,
                liveTarget: liveTarget
            ))
        case .objectUnavailable:
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

#endif // canImport(UIKit) && DEBUG
