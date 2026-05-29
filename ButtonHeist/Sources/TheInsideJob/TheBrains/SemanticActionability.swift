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
        let target: SemanticElementTarget
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
        let method: ActionMethod?
        let message: String

        static func notFound(_ message: String) -> SemanticActionabilityFailure {
            .init(.notFound, method: .elementNotFound, message: message)
        }
        static func ambiguous(_ message: String) -> SemanticActionabilityFailure {
            .init(.ambiguous, method: .elementNotFound, message: message)
        }
        static func noRevealPath(_ message: String) -> SemanticActionabilityFailure { .init(.noRevealPath, method: nil, message: message) }

        static func staleRefresh(
            _ message: String,
            method: ActionMethod? = nil
        ) -> SemanticActionabilityFailure {
            .init(.staleRefresh, method: method, message: message)
        }

        static func geometryNotActionable(
            _ message: String,
            method: ActionMethod? = nil
        ) -> SemanticActionabilityFailure {
            .init(.geometryNotActionable, method: method, message: message)
        }

        func interactionResult(commandMethod: ActionMethod) -> TheSafecracker.InteractionResult {
            .failure(method ?? commandMethod, message: message)
        }

        private init(_ step: SemanticActionabilityFailureStep, method: ActionMethod?, message: String) {
            failedStep = step
            self.method = method
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
        for target: SemanticElementTarget,
        method: ActionMethod,
        deallocatedBoundary: String
    ) async -> SemanticActionabilityResult {
        guard let executableTarget = target.executableTarget else {
            return .failed(.notFound(target.diagnostics(
                target.validationFailureMessage ?? "target requires heistId or semantic matcher predicates"
            )))
        }

        // Source screens derive only semantic identity. Reveal and geometry
        // authority always come from the current live graph.
        var revealMovedViewport = false
        switch stash.resolveTarget(executableTarget) {
        case .resolved(let screenElement):
            let reveal = stash.executeSemanticRevealPlan(for: screenElement)
            if case .failed = reveal {
                return .failed(.noRevealPath(semanticRevealPlanFailureMessage(screenElement)))
            }
            if reveal.didReveal {
                await tripwire.yieldFrames(Self.postScrollLayoutFrames)
                stash.refresh()
                revealMovedViewport = true
            }
        case .notFound(let diagnostics):
            return .failed(.notFound(target.diagnostics(diagnostics)))
        case .ambiguous(_, let diagnostics):
            return .failed(.ambiguous(target.diagnostics(diagnostics)))
        }

        var freshTarget = resolveFreshElementTarget(
            target: target,
            executableTarget: executableTarget,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        )
        if case .failure(let failure) = freshTarget,
           failure.failedStep == .staleRefresh,
           !revealMovedViewport {
            stash.refresh()
            freshTarget = resolveFreshElementTarget(
                target: target,
                executableTarget: executableTarget,
                method: method,
                deallocatedBoundary: deallocatedBoundary
            )
        }
        switch freshTarget {
        case .success(let actionableTarget):
            return await placeElementActivationPoint(
                actionableTarget,
                executableTarget: executableTarget,
                method: method,
                revealMovedViewport: revealMovedViewport
            )
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private func placeElementActivationPoint(
        _ actionableTarget: SemanticActionableTarget,
        executableTarget: ElementTarget,
        method: ActionMethod,
        revealMovedViewport: Bool
    ) async -> SemanticActionabilityResult {
        let liveTarget = actionableTarget.liveTarget
        guard !Self.activationPointHasPreferredPlacement(liveTarget.activationPoint) else {
            return .actionable(actionableTarget)
        }
        guard !revealMovedViewport else {
            if Self.activationPointIsOnScreen(liveTarget.activationPoint) {
                return .actionable(actionableTarget)
            }
            return .failed(.geometryNotActionable(
                actionableTarget.target.diagnostics(
                    "target \(Navigation.describeScrollTarget(liveTarget.screenElement)) "
                        + "did not become actionable after semantic reveal; "
                        + Self.liveGeometrySummary(liveTarget)
                ),
                method: method
            ))
        }

        let screenElement = liveTarget.screenElement
        let description = Navigation.describeScrollTarget(screenElement)
        if let failure = await scrollActivationPointIntoBounds(
            liveTarget.activationPoint,
            in: stash.liveScrollView(for: screenElement),
            method: method,
            noScrollViewFailure: noScrollViewFailure(
                for: liveTarget,
                description: description,
                method: method
            ),
            unsafeProgrammaticScrollMessage: nil,
            scrollFailedMessage: actionableTarget.target.diagnostics(
                "target \(description) activation point could not be brought on-screen"
            )
        ) {
            return .failed(failure)
        }

        switch resolveFreshElementTarget(
            target: actionableTarget.target,
            executableTarget: executableTarget,
            method: method,
            deallocatedBoundary: "activation point placement"
        ) {
        case .success(let refreshedTarget):
            if Self.activationPointIsOnScreen(refreshedTarget.liveTarget.activationPoint) {
                return .actionable(refreshedTarget)
            }
            return .failed(.geometryNotActionable(
                refreshedTarget.target.diagnostics(
                    "target \(Navigation.describeScrollTarget(refreshedTarget.screenElement)) "
                        + "did not become actionable after activation point placement; "
                        + Self.liveGeometrySummary(refreshedTarget.liveTarget)
                ),
                method: method
            ))
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private func resolveFreshElementTarget(
        target: SemanticElementTarget,
        executableTarget: ElementTarget,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> Result<SemanticActionableTarget, SemanticActionabilityFailure> {
        let screenElement: TheStash.ScreenElement
        switch stash.resolveVisibleTarget(executableTarget) {
        case .resolved(let target):
            screenElement = target
        case .notFound(let diagnostics):
            return .failure(.staleRefresh(
                target.diagnostics("target was not found in fresh live geometry: \(diagnostics)")
            ))
        case .ambiguous(_, let diagnostics):
            return .failure(.ambiguous(target.diagnostics(diagnostics)))
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
                target.diagnostics(
                    ActionCapabilityDiagnostic.elementDeallocated(
                        boundary: deallocatedBoundary,
                        element: screenElement,
                        isInflated: stash.visibleIds.contains(screenElement.heistId)
                    )
                ),
                method: .elementDeallocated
            ))
        case .geometryUnavailable:
            return .failure(.geometryNotActionable(
                target.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: screenElement,
                        isVisible: stash.visibleIds.contains(screenElement.heistId)
                    )
                ),
                method: method
            ))
        }
    }

    private func noScrollViewFailure(
        for liveTarget: TheStash.LiveActionTarget,
        description: String,
        method: ActionMethod
    ) -> SemanticActionabilityFailure {
        let target = liveTarget.screenElement
        if ScreenMetrics.current.bounds.intersects(liveTarget.frame) {
            return .geometryNotActionable(
                "target \(description) has an activation point outside the screen; "
                    + Self.liveGeometrySummary(liveTarget),
                method: method
            )
        }
        return .noRevealPath(
            SemanticElementTarget.currentCapture(.heistId(target.heistId)).diagnostics(
                "target \(description) has no live scrollable ancestor to make activation point actionable"
            )
        )
    }

    func scrollActivationPointIntoBounds(
        _ activationPoint: CGPoint,
        in scrollView: UIScrollView?,
        method: ActionMethod,
        noScrollViewFailure: SemanticActionabilityFailure,
        unsafeProgrammaticScrollMessage: String?,
        scrollFailedMessage: String
    ) async -> SemanticActionabilityFailure? {
        if Self.activationPointHasPreferredPlacement(activationPoint) {
            return nil
        }
        guard let scrollView else {
            if Self.activationPointIsOnScreen(activationPoint) {
                return nil
            }
            return noScrollViewFailure
        }
        if scrollView.bhIsUnsafeForProgrammaticScrolling,
           let unsafeProgrammaticScrollMessage {
            if Self.activationPointIsOnScreen(activationPoint) {
                return nil
            }
            return .geometryNotActionable(unsafeProgrammaticScrollMessage, method: method)
        }
        guard safecracker.scrollToMakeActivationPointVisible(
            activationPoint,
            in: scrollView,
            animated: false,
            preferredScreenRect: Self.interactionComfortZone,
            minimumScreenRect: ScreenMetrics.current.bounds
        ) else {
            if Self.activationPointIsOnScreen(activationPoint) {
                return nil
            }
            return .geometryNotActionable(scrollFailedMessage, method: method)
        }
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        stash.refresh()
        return nil
    }

    func makeFirstResponderActionable(method: ActionMethod) async -> SemanticActionabilityFailure? {
        guard let heistId = stash.firstResponderHeistId else { return nil }
        switch await makeActionable(
            for: .currentCapture(.heistId(heistId)),
            method: method,
            deallocatedBoundary: "first responder actionability"
        ) {
        case .actionable:
            return nil
        case .failed(let failure):
            return failure
        }
    }

    static func activationPointHasPreferredPlacement(_ activationPoint: CGPoint) -> Bool { interactionComfortZone.contains(activationPoint) }

    static func activationPointIsOnScreen(_ activationPoint: CGPoint) -> Bool { ScreenMetrics.current.bounds.contains(activationPoint) }
}

#endif // canImport(UIKit) && DEBUG
