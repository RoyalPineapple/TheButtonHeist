#if canImport(UIKit) && DEBUG
import UIKit

import TheScore

/// Converts a semantic target into a fresh live target that can receive the
/// requested accessibility action.
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

    static let comfortMarginFraction: CGFloat = 1.0 / 6.0
    static let postScrollLayoutFrames = Navigation.postScrollLayoutFrames

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

    enum ElementInflationFailureStep: String {
        case notFound
        case ambiguous
        case noRevealPath
        case staleRefresh
        case geometryNotActionable
    }

    struct ElementInflationFailure: Error {
        let failedStep: ElementInflationFailureStep
        let failureKind: TheSafecracker.FailureKind?
        let message: String

        static func notFound(_ message: String) -> ElementInflationFailure {
            .init(.notFound, failureKind: .targetUnavailable, message: message)
        }
        static func ambiguous(_ message: String) -> ElementInflationFailure {
            .init(.ambiguous, failureKind: .targetUnavailable, message: message)
        }
        static func noRevealPath(_ message: String) -> ElementInflationFailure {
            .init(.noRevealPath, failureKind: nil, message: message)
        }

        static func staleRefresh(
            _ message: String,
            failureKind: TheSafecracker.FailureKind? = nil
        ) -> ElementInflationFailure {
            .init(.staleRefresh, failureKind: failureKind, message: message)
        }

        static func geometryNotActionable(
            _ message: String,
            failureKind: TheSafecracker.FailureKind? = nil
        ) -> ElementInflationFailure {
            .init(.geometryNotActionable, failureKind: failureKind, message: message)
        }

        func interactionResult(commandMethod: ActionMethod) -> TheSafecracker.InteractionResult {
            .failure(commandMethod, message: message, failureKind: failureKind)
        }

        private init(
            _ step: ElementInflationFailureStep,
            failureKind: TheSafecracker.FailureKind?,
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
        // Source screens derive only semantic identity. Reveal and geometry
        // authority always come from the current live graph.
        var screenElement: TheStash.ScreenElement
        var didRevealTarget = false
        switch await resolveSemanticTarget(target) {
        case .success(let resolvedElement):
            screenElement = resolvedElement
            var reveal = revealSemanticTarget(screenElement)
            if case .failed = reveal,
               let rediscoveredElement = await rediscoverSemanticTarget(target) {
                screenElement = rediscoveredElement
                reveal = revealSemanticTarget(screenElement)
            }
            if case .failed(let failure) = reveal {
                return .failed(.noRevealPath(semanticRevealFailureMessage(failure, entry: screenElement)))
            }
            if reveal.didReveal {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                stash.refreshLiveCapture()
                didRevealTarget = true
            }
        case .failure(let failure):
            return .failed(failure)
        }

        var freshTarget = resolveFreshElementTarget(
            target: target,
            screenElement: screenElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        )
        if case .failure(let failure) = freshTarget,
           failure.failedStep == .staleRefresh,
           let rediscoveredElement = await rediscoverSemanticTarget(target) {
            screenElement = rediscoveredElement
            let reveal = revealSemanticTarget(screenElement)
            if case .failed(let failure) = reveal {
                return .failed(.noRevealPath(semanticRevealFailureMessage(failure, entry: screenElement)))
            }
            if reveal.didReveal {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                stash.refreshLiveCapture()
                didRevealTarget = true
            }
            freshTarget = resolveFreshElementTarget(
                target: target,
                screenElement: screenElement,
                method: method,
                deallocatedBoundary: deallocatedBoundary
            )
        }
        if case .failure(let failure) = freshTarget,
           failure.failedStep == .staleRefresh,
           !didRevealTarget {
            // A semantic target can outlive its capture-local UIKit object.
            // Refresh once before failing; reveal and activation-point placement
            // own the other bounded refresh points.
            stash.refreshLiveCapture()
            freshTarget = resolveFreshElementTarget(
                target: target,
                screenElement: screenElement,
                method: method,
                deallocatedBoundary: deallocatedBoundary
            )
        }
        switch freshTarget {
        case .success(let inflatedTarget):
            guard activationPointPolicy == .requireOnscreen else {
                return .inflated(inflatedTarget)
            }
            return await placeElementActivationPoint(
                inflatedTarget,
                method: method,
                didRevealTarget: didRevealTarget
            )
        case .failure(let failure):
            return .failed(failure)
        }
    }

    func inflateAfterActivationRetryRefresh(
        for target: ElementTarget
    ) async -> ElementInflationResult {
        refreshLiveCaptureForActivationRetry()
        return await inflate(
            for: target,
            method: .activate,
            deallocatedBoundary: "activation retry"
        )
    }

    private func refreshLiveCaptureForActivationRetry() {
        stash.refreshLiveCapture()
    }

    private func resolveSemanticTarget(
        _ target: ElementTarget
    ) async -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        if let visible = uniquelyResolvedVisibleTarget(target) {
            return .success(visible)
        }
        if let screen = await discoverTarget?(target) {
            stash.semanticObservationStream.commitSettledDiscoveryObservation(screen)
            if let visible = uniquelyResolvedVisibleTarget(target, in: screen) {
                return .success(visible)
            }
            if let revealable = uniquelyResolvedRevealableTarget(target, in: screen) {
                return .success(revealable)
            }
        }
        return knownSemanticTarget(target)
    }

    private func rediscoverSemanticTarget(_ target: ElementTarget) async -> TheStash.ScreenElement? {
        guard let screen = await discoverTarget?(target) else { return nil }
        stash.semanticObservationStream.commitSettledDiscoveryObservation(screen)
        guard case .success(let screenElement) = preferredSemanticTarget(target) else { return nil }
        return screenElement
    }

    private func knownSemanticTarget(
        _ target: ElementTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        if let revealable = uniquelyResolvedRevealableTarget(target) {
            return .success(revealable)
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

    private func preferredSemanticTarget(
        _ target: ElementTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        if let visible = uniquelyResolvedVisibleTarget(target) {
            return .success(visible)
        }
        return knownSemanticTarget(target)
    }

    private func uniquelyResolvedVisibleTarget(_ target: ElementTarget) -> TheStash.ScreenElement? {
        uniquelyResolvedVisibleTarget(target, in: stash.liveVisibleScreen)
    }

    private func uniquelyResolvedVisibleTarget(
        _ target: ElementTarget,
        in screen: Screen
    ) -> TheStash.ScreenElement? {
        switch stash.resolveTarget(target, in: screen.visibleOnly) {
        case .resolved(let screenElement):
            return screenElement
        case .notFound, .ambiguous:
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
                .filter { $0.contentSpaceOrigin != nil && stash.liveScrollView(for: $0) != nil }
            return revealableMatches.count == 1 ? revealableMatches[0] : nil
        case .predicate:
            return nil
        }
    }

    private func placeElementActivationPoint(
        _ inflatedTarget: InflatedElementTarget,
        method: ActionMethod,
        didRevealTarget: Bool
    ) async -> ElementInflationResult {
        let liveTarget = inflatedTarget.liveTarget
        guard !ScreenMetrics.current.bounds.contains(liveTarget.activationPoint) else {
            return .inflated(inflatedTarget)
        }
        guard !didRevealTarget else {
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
        case .failure(let failure):
            return .failed(failure)
        case .success(true):
            break
        }

        switch resolveFreshElementTarget(
            target: inflatedTarget.target,
            screenElement: inflatedTarget.screenElement,
            method: method,
            deallocatedBoundary: "activation point placement"
        ) {
        case .success(let refreshedTarget):
            if ScreenMetrics.current.bounds.contains(refreshedTarget.liveTarget.activationPoint) {
                return .inflated(refreshedTarget)
            }
            return .failed(.geometryNotActionable(
                "target \(Navigation.ScrollTargetDescription(refreshedTarget.screenElement).description) "
                    + "did not become actionable after activation point placement; "
                    + Self.liveGeometrySummary(refreshedTarget.liveTarget)
            ))
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private func resolveFreshElementTarget(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> Result<InflatedElementTarget, ElementInflationFailure> {
        let liveResolution = stash.resolveLiveActionTarget(for: screenElement)
        if case .resolved(let liveTarget) = liveResolution {
            return .success(InflatedElementTarget(
                target: target,
                screenElement: screenElement,
                liveTarget: liveTarget
            ))
        }

        if case .objectUnavailable = liveResolution {
            switch stash.resolveVisibleTarget(target) {
            case .resolved(let visibleElement) where visibleElement.heistId != screenElement.heistId:
                return resolveVisibleReboundElementTarget(
                    target: target,
                    screenElement: visibleElement,
                    method: method,
                    deallocatedBoundary: deallocatedBoundary
                )
            case .resolved:
                break
            case .notFound(let facts):
                return .failure(.staleRefresh(
                    "target was not found in fresh live geometry: \(TargetResolutionDiagnostics.message(for: .notFound(facts)))"
                ))
            case .ambiguous(let facts):
                return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
            }
        }

        switch liveResolution {
        case .resolved(let liveTarget):
            return .success(InflatedElementTarget(
                target: target,
                screenElement: screenElement,
                liveTarget: liveTarget
            ))
        case .objectUnavailable:
            return .failure(.staleRefresh(
                ActionCapabilityDiagnostic.elementDeallocated(
                    boundary: deallocatedBoundary,
                    element: screenElement,
                    isInflated: stash.visibleIds.contains(screenElement.heistId)
                ),
                failureKind: .targetUnavailable
            ))
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

    private func resolveVisibleReboundElementTarget(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> Result<InflatedElementTarget, ElementInflationFailure> {
        switch stash.resolveLiveActionTarget(for: screenElement) {
        case .resolved(let liveTarget):
            return .success(InflatedElementTarget(
                target: target,
                screenElement: screenElement,
                liveTarget: liveTarget
            ))
        case .objectUnavailable:
            return .failure(.staleRefresh(
                ActionCapabilityDiagnostic.elementDeallocated(
                    boundary: deallocatedBoundary,
                    element: screenElement,
                    isInflated: stash.visibleIds.contains(screenElement.heistId)
                ),
                failureKind: .targetUnavailable
            ))
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
        stash.refreshLiveCapture()
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

#endif // canImport(UIKit) && DEBUG
