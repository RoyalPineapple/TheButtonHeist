#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {
    var liveActionTargetRecoveryPolicy: LiveActionTargetRecoveryPolicy {
        LiveActionTargetRecoveryPolicy(navigation: navigation)
    }
}

extension Navigation.SemanticActionabilityFailure {
    func interactionResult(commandMethod: ActionMethod) -> TheSafecracker.InteractionResult {
        .failure(method ?? commandMethod, message: message)
    }
}

/// Resolves a semantic actionability target, refreshing once on recoverable
/// stale-object failures.
struct LiveActionTargetRecoveryPolicy {
    struct Request {
        let normalizedTarget: TheStash.NormalizedTarget
        let method: ActionMethod
        let requireInteractive: Bool
        let deallocatedBoundary: String
        let preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)?
    }

    enum Resolution {
        case success(Actions.LiveElementActionContext)
        case failure(TheSafecracker.InteractionResult)
    }

    let navigation: Navigation

    @MainActor
    func resolve(_ request: Request) async -> Resolution {
        switch await navigation.makeActionable(
            for: request.normalizedTarget,
            method: request.method,
            deallocatedBoundary: request.deallocatedBoundary
        ) {
        case .actionable(let actionableTarget):
            return makeContext(request, actionableTarget: actionableTarget)
        case .failed(let failure):
            return .failure(failure.interactionResult(commandMethod: request.method))
        }
    }

    @MainActor
    func refreshActivationTarget(
        _ normalizedTarget: TheStash.NormalizedTarget
    ) async -> ActivationPolicy.RefreshResult {
        navigation.refresh()
        switch await navigation.makeActionable(
            for: normalizedTarget,
            method: .activate,
            deallocatedBoundary: "activation retry"
        ) {
        case .actionable(let actionableTarget):
            return .resolved(
                resolvedTarget: actionableTarget.resolvedTarget,
                liveTarget: actionableTarget.liveTarget
            )
        case .failed(let failure):
            return .failure(failure.interactionResult(commandMethod: .activate))
        }
    }

    @MainActor
    private func makeContext(
        _ request: Request,
        actionableTarget: Navigation.SemanticActionableTarget
    ) -> Resolution {
        let resolved = actionableTarget.resolvedTarget
        let liveTarget = actionableTarget.liveTarget
        if let failure = request.preflight?(resolved) {
            return .failure(failure)
        }
        if request.requireInteractive {
            switch TheStash.Interactivity.checkInteractivity(resolved.element, object: liveTarget.object) {
            case .blocked(let reason):
                return .failure(.failure(request.method, message: reason))
            case .interactive(let warning):
                if let warning { insideJobLogger.warning("\(warning)") }
            }
            guard TheStash.Interactivity.isInteractive(element: resolved.element, object: liveTarget.object) else {
                return .failure(.failure(
                    request.method,
                    message: ActionCapabilityDiagnostic.unsupportedElementAction(
                        request.method,
                        element: resolved.screenElement
                    )
                ))
            }
        }
        return .success(Actions.LiveElementActionContext(
            normalizedTarget: actionableTarget.normalizedTarget,
            resolvedTarget: resolved,
            liveTarget: liveTarget
        ))
    }
}

struct LiveActionTargetRecoveryDiagnostic: Equatable {
    let initialFailureMessage: String
    let contractFailed: String
    let knownState: String
    let nextValidCommand: String

    var message: String {
        [
            initialFailureMessage,
            "- contractFailed: \(contractFailed)",
            "- knownState: \(knownState)",
            "- nextValidCommand: \(nextValidCommand)",
        ].joined(separator: "\n")
    }

    static func refreshReresolveFailed(
        initialFailure: TheSafecracker.InteractionResult,
        recoveryObservation: String?,
        method: ActionMethod
    ) -> LiveActionTargetRecoveryDiagnostic {
        let initialMessage: String
        if let message = initialFailure.message, !message.isEmpty {
            initialMessage = message
        } else {
            initialMessage = "\(method.rawValue) failed without diagnostic message"
        }
        let observed: String
        if let recoveryObservation, !recoveryObservation.isEmpty {
            observed = recoveryObservation
        } else {
            observed = "unknown"
        }
        return LiveActionTargetRecoveryDiagnostic(
            initialFailureMessage: initialMessage,
            contractFailed: "live action target must be reachable after refresh",
            knownState: "refresh/re-resolve failed; observed \(observed)",
            nextValidCommand: "retry \(method.rawValue) against the same semantic target after UI settles"
        )
    }

    static func recoveryFailed(
        initialFailure: TheSafecracker.InteractionResult,
        recoveryObservation: String?,
        method: ActionMethod
    ) -> TheSafecracker.InteractionResult {
        let diagnostic = refreshReresolveFailed(
            initialFailure: initialFailure,
            recoveryObservation: recoveryObservation,
            method: method
        )
        return .failure(
            initialFailure.method,
            message: diagnostic.message,
            payload: initialFailure.payload,
            failureKind: initialFailure.failureKind
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
