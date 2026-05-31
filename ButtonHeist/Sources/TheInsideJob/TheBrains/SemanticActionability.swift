#if canImport(UIKit) && DEBUG
import UIKit

import TheScore

@MainActor
final class SemanticActionability {

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire

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

    struct SemanticActionableTarget {
        let target: ElementTarget
        let screenElement: TheStash.ScreenElement
        let liveTarget: TheStash.LiveActionTarget
    }

    enum SemanticActionabilityResult {
        case actionable(SemanticActionableTarget)
        case failed(SemanticActionabilityFailure)
    }

    enum SemanticActionabilityFailureStep: String {
        case notFound
        case ambiguous
        case noRevealPath
        case staleRefresh
        case geometryNotActionable
    }

    struct SemanticActionabilityFailure: Error {
        let failedStep: SemanticActionabilityFailureStep
        let failureKind: TheSafecracker.FailureKind?
        let message: String

        static func notFound(_ message: String) -> SemanticActionabilityFailure {
            .init(.notFound, failureKind: .targetUnavailable, message: message)
        }
        static func ambiguous(_ message: String) -> SemanticActionabilityFailure {
            .init(.ambiguous, failureKind: .targetUnavailable, message: message)
        }
        static func noRevealPath(_ message: String) -> SemanticActionabilityFailure {
            .init(.noRevealPath, failureKind: nil, message: message)
        }

        static func staleRefresh(
            _ message: String,
            failureKind: TheSafecracker.FailureKind? = nil
        ) -> SemanticActionabilityFailure {
            .init(.staleRefresh, failureKind: failureKind, message: message)
        }

        static func geometryNotActionable(
            _ message: String,
            failureKind: TheSafecracker.FailureKind? = nil
        ) -> SemanticActionabilityFailure {
            .init(.geometryNotActionable, failureKind: failureKind, message: message)
        }

        func interactionResult(commandMethod: ActionMethod) -> TheSafecracker.InteractionResult {
            .failure(commandMethod, message: message, failureKind: failureKind)
        }

        private init(
            _ step: SemanticActionabilityFailureStep,
            failureKind: TheSafecracker.FailureKind?,
            message: String
        ) {
            failedStep = step
            self.failureKind = failureKind
            self.message = message.contains("[\(step.rawValue)]")
                ? message
                : "semantic actionability failed [\(step.rawValue)]: \(message)"
        }
    }

    static var interactionComfortZone: CGRect {
        let bounds = ScreenMetrics.current.bounds
        return bounds.insetBy(dx: bounds.width * comfortMarginFraction, dy: bounds.height * comfortMarginFraction)
    }

    func makeActionable(
        for target: ElementTarget,
        method: ActionMethod,
        deallocatedBoundary: String
    ) async -> SemanticActionabilityResult {
        // Source screens derive only semantic identity. Reveal and geometry
        // authority always come from the current live graph.
        var didRevealTarget = false
        switch stash.resolveTarget(target) {
        case .resolved(let screenElement):
            let reveal = stash.revealSemanticTarget(screenElement)
            if case .failed(let failure) = reveal {
                return .failed(.noRevealPath(semanticRevealFailureMessage(failure, entry: screenElement)))
            }
            if reveal.didReveal {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                stash.refresh()
                didRevealTarget = true
            }
        case .notFound(let diagnostics):
            return .failed(.notFound(diagnostics))
        case .ambiguous(_, let diagnostics):
            return .failed(.ambiguous(diagnostics))
        }

        var freshTarget = resolveFreshElementTarget(
            target: target,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        )
        if case .failure(let failure) = freshTarget,
           failure.failedStep == .staleRefresh,
           !didRevealTarget {
            // A semantic target can outlive its capture-local UIKit object.
            // Refresh once before failing; reveal and activation-point placement
            // own the other bounded refresh points.
            stash.refresh()
            freshTarget = resolveFreshElementTarget(
                target: target,
                method: method,
                deallocatedBoundary: deallocatedBoundary
            )
        }
        switch freshTarget {
        case .success(let actionableTarget):
            return await placeElementActivationPoint(
                actionableTarget,
                method: method,
                didRevealTarget: didRevealTarget
            )
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private func placeElementActivationPoint(
        _ actionableTarget: SemanticActionableTarget,
        method: ActionMethod,
        didRevealTarget: Bool
    ) async -> SemanticActionabilityResult {
        let liveTarget = actionableTarget.liveTarget
        guard !Self.interactionComfortZone.contains(liveTarget.activationPoint) else {
            return .actionable(actionableTarget)
        }
        guard !didRevealTarget else {
            if ScreenMetrics.current.bounds.contains(liveTarget.activationPoint) {
                return .actionable(actionableTarget)
            }
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
            return .actionable(actionableTarget)
        case .failure(let failure):
            return .failed(failure)
        case .success(true):
            break
        }

        switch resolveFreshElementTarget(
            target: actionableTarget.target,
            method: method,
            deallocatedBoundary: "activation point placement"
        ) {
        case .success(let refreshedTarget):
            if ScreenMetrics.current.bounds.contains(refreshedTarget.liveTarget.activationPoint) {
                return .actionable(refreshedTarget)
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
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> Result<SemanticActionableTarget, SemanticActionabilityFailure> {
        let screenElement: TheStash.ScreenElement
        switch stash.resolveVisibleTarget(target) {
        case .resolved(let target):
            screenElement = target
        case .notFound(let diagnostics):
            return .failure(.staleRefresh(
                "target was not found in fresh live geometry: \(diagnostics)"
            ))
        case .ambiguous(_, let diagnostics):
            return .failure(.ambiguous(diagnostics))
        }

        switch stash.resolveLiveActionTarget(for: screenElement) {
        case .resolved(let liveTarget):
            return .success(SemanticActionableTarget(
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
    ) -> SemanticActionabilityFailure {
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
        noScrollViewFailure: SemanticActionabilityFailure,
        unsafeProgrammaticScrollMessage: String?,
        scrollFailedMessage: String
    ) async -> Result<Bool, SemanticActionabilityFailure> {
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
        guard safecracker.scrollToMakeActivationPointVisible(
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
        stash.refresh()
        return .success(true)
    }

    func makeFirstResponderActionable(method: ActionMethod) async -> SemanticActionabilityFailure? {
        guard let heistId = stash.firstResponderHeistId else { return nil }
        switch await makeActionable(
            for: .heistId(heistId),
            method: method,
            deallocatedBoundary: "first responder actionability"
        ) {
        case .actionable:
            return nil
        case .failed(let failure):
            return failure
        }
    }

}

#endif // canImport(UIKit) && DEBUG
