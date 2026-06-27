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

    private enum StaleLiveTargetRecovery {
        case refreshVisibleTarget
        case fail
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
        stash.refreshCurrentVisibleTree()
        var allowKnownFallback = true
        while true {
            switch await findTargetInTree(target, allowKnownFallback: allowKnownFallback) {
            case .success(let treeElement):
                let result = await resolveTargetFromTree(
                    target: target,
                    treeElement: treeElement,
                    method: method,
                    deallocatedBoundary: deallocatedBoundary,
                    activationPointPolicy: activationPointPolicy
                )
                guard case .failed(let failure) = result,
                      failure.failedStep == .staleRefresh,
                      allowKnownFallback else {
                    return result
                }
                allowKnownFallback = false
            case .failure(let failure):
                return .failed(failure)
            }
        }
    }

    private func resolveTargetFromTree(
        target: ElementTarget,
        treeElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy
    ) async -> ElementInflationResult {
        let reveal = await revealSemanticTarget(treeElement)
        if case .failed(let failure) = reveal {
            return .failed(.noRevealPath(semanticRevealFailureMessage(failure, entry: treeElement)))
        }

        switch resolveFreshElementTarget(
            target: target,
            screenElement: treeElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        ) {
        case .success(let inflatedTarget):
            guard activationPointPolicy == .requireOnscreen else {
                return .inflated(inflatedTarget)
            }
            return await placeElementActivationPoint(
                inflatedTarget,
                method: method,
                didRevealTarget: reveal.didReveal
            )
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
    ) async -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        switch visibleTargetResolution(target) {
        case .success(let visible):
            return .success(visible)
        case .failure(let failure):
            return .failure(failure)
        case nil:
            break
        }
        if let screen = await discoverTarget?(target) {
            stash.semanticObservationStream.commitSettledDiscoveryObservation(screen)
            switch visibleTargetResolution(target, in: screen) {
            case .success(let visible):
                return .success(visible)
            case .failure(let failure):
                return .failure(failure)
            case nil:
                return discoveredSemanticTarget(target)
            }
        }
        guard allowKnownFallback else {
            return currentVisibleTargetFailure(target)
        }
        return knownSemanticTarget(target)
    }

    private func discoveredSemanticTarget(
        _ target: ElementTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        switch knownSemanticTarget(target) {
        case .success(let screenElement):
            return .success(screenElement)
        case .failure(let failure) where failure.failedStep == .notFound:
            return .failure(failure)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func currentVisibleTargetFailure(
        _ target: ElementTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        switch stash.resolveVisibleTarget(target) {
        case .resolved(let screenElement):
            return .success(screenElement)
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
                .filter { $0.contentSpaceOrigin != nil && stash.liveScrollView(for: $0) != nil }
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
                .filter { $0.scrollContentLocation != nil }
            return reachableMatches.count == 1 ? reachableMatches[0] : nil
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
        resolveLiveElementTarget(
            target: target,
            screenElement: screenElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary,
            staleTargetRecovery: .refreshVisibleTarget
        )
    }

    private func resolveFreshVisibleElementTarget(
        target: ElementTarget,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> Result<InflatedElementTarget, ElementInflationFailure> {
        stash.refreshCurrentVisibleTree()
        switch stash.resolveVisibleTarget(target) {
        case .resolved(let visibleElement):
            return resolveLiveElementTarget(
                target: target,
                screenElement: visibleElement,
                method: method,
                deallocatedBoundary: deallocatedBoundary,
                staleTargetRecovery: .fail
            )
        case .notFound(let facts):
            return .failure(.staleRefresh(
                "target was not found in fresh live geometry: \(TargetResolutionDiagnostics.message(for: .notFound(facts)))",
                failureKind: .targetUnavailable
            ))
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        }
    }

    private func resolveLiveElementTarget(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String,
        staleTargetRecovery: StaleLiveTargetRecovery
    ) -> Result<InflatedElementTarget, ElementInflationFailure> {
        switch stash.resolveLiveActionTarget(for: screenElement) {
        case .resolved(let liveTarget):
            if case .refreshVisibleTarget = staleTargetRecovery,
               !liveTarget.screenElement.matches(target) {
                return resolveFreshVisibleElementTarget(
                    target: target,
                    method: method,
                    deallocatedBoundary: deallocatedBoundary
                )
            }
            return .success(InflatedElementTarget(
                target: target,
                screenElement: liveTarget.screenElement,
                liveTarget: liveTarget
            ))
        case .objectUnavailable:
            if case .refreshVisibleTarget = staleTargetRecovery {
                return resolveFreshVisibleElementTarget(
                    target: target,
                    method: method,
                    deallocatedBoundary: deallocatedBoundary
                )
            }
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
