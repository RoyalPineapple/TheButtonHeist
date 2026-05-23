#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

extension Actions {

    // MARK: - Element Action Pipeline

    struct LiveElementActionContext {
        let normalizedTarget: TheStash.NormalizedTarget
        let resolvedTarget: TheStash.ResolvedTarget
        let liveTarget: TheStash.LiveActionTarget

        var screenElement: TheStash.ScreenElement { resolvedTarget.screenElement }
        var element: AccessibilityElement { resolvedTarget.element }
    }

    /// Unified pipeline for actions that target an element:
    /// ensureOnScreen → resolve → check interactivity → perform action.
    func performElementAction(
        target: any SemanticElementTarget,
        method: ActionMethod,
        recordedScreen: Screen? = nil,
        requireInteractive: Bool = true,
        deallocatedBoundary: String = "element action",
        preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)? = nil,
        action: @MainActor (LiveElementActionContext) async -> TheSafecracker.InteractionResult?
    ) async -> TheSafecracker.InteractionResult {
        let normalizedTarget = stash.normalizeTarget(target, in: recordedScreen ?? stash.currentScreen)
        let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = positioning.failure {
            return .failure(failure.method ?? method, message: failure.message)
        }
        switch await liveActionTargetRecoveryPolicy.resolve(.init(
            normalizedTarget: normalizedTarget,
            method: method,
            requireInteractive: requireInteractive,
            deallocatedBoundary: deallocatedBoundary,
            preflight: preflight
        )) {
        case .success(let context):
            return await action(context) ?? .failure(method, message: "\(method.rawValue) failed")
        case .failure(let result):
            return result
        case .retryableFailure(let result):
            return result
        }
    }

    private func resolveActivateTarget(
        _ target: any SemanticElementTarget,
        recordedScreen: Screen?
    ) async -> LiveActionTargetRecoveryPolicy.Resolution {
        let normalizedTarget = stash.normalizeTarget(target, in: recordedScreen ?? stash.currentScreen)
        let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = positioning.failure {
            return .failure(.failure(failure.method ?? .activate, message: failure.message))
        }
        return await liveActionTargetRecoveryPolicy.resolve(.init(
            normalizedTarget: normalizedTarget,
            method: .activate,
            requireInteractive: true,
            deallocatedBoundary: "element action",
            preflight: nil
        ))
    }

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        await executeActivate(target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    func executeActivate(_ target: BatchExecutionTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        await executeActivate(target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    private func executeActivate(_ target: any SemanticElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        switch await resolveActivateTarget(target, recordedScreen: recordedScreen) {
        case .success(let context):
            return await ActivationPolicy(
                activate: stash.activate,
                refreshAndResolve: { await self.refreshAndResolveActivationTarget(context.normalizedTarget) },
                syntheticTap: safecracker.tap,
                showFingerprint: safecracker.showFingerprint,
                tapReceiverDiagnostic: safecracker.tapReceiverDiagnostic,
                screenBounds: { ScreenMetrics.current.bounds }
            ).apply(to: context.liveTarget)
        case .failure(let result), .retryableFailure(let result):
            return result
        }
    }

    private func refreshAndResolveActivationTarget(
        _ normalizedTarget: TheStash.NormalizedTarget
    ) async -> ActivationPolicy.RefreshResult {
        navigation.refresh()
        let retryPositioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = retryPositioning.failure {
            return .failure(.failure(failure.method ?? .activate, message: failure.message))
        }
        let retryResolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let retryResolved = retryResolution.resolved else {
            return .failure(.failure(
                .elementNotFound,
                message: normalizedTarget.diagnostics(retryResolution.diagnostics)
            ))
        }
        let retryLiveTargetResolution = stash.resolveLiveActionTarget(for: retryResolved)
        guard case .resolved(let retryLiveTarget) = retryLiveTargetResolution else {
            return activationRefreshFailure(
                for: retryLiveTargetResolution,
                resolved: retryResolved
            )
        }
        return .resolved(resolvedTarget: retryResolved, liveTarget: retryLiveTarget)
    }

    private func activationRefreshFailure(
        for resolution: TheStash.LiveActionTargetResolution,
        resolved: TheStash.ResolvedTarget
    ) -> ActivationPolicy.RefreshResult {
        switch resolution {
        case .objectUnavailable:
            let traitNames = ActionCapabilityDiagnostic.traitNames(resolved.element.traits)
            let message = ActivateFailureDiagnostic.build(
                element: resolved.element,
                traitNames: traitNames,
                activateOutcome: .objectDeallocated,
                tapAttempted: false,
                tapReceiver: nil,
                screenBounds: ScreenMetrics.current.bounds
            )
            return .failure(.failure(.activate, message: message))
        case .geometryUnavailable:
            return .failure(.failure(
                .activate,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: .activate,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            ))
        case .resolved:
            return .failure(.failure(.activate, message: "activate failed"))
        }
    }

    func executeIncrement(_ target: ElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        await executeIncrement(target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    func executeIncrement(_ target: BatchExecutionTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        await executeIncrement(target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    private func executeIncrement(_ target: any SemanticElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .increment,
            recordedScreen: recordedScreen,
            deallocatedBoundary: "adjustable action",
            preflight: { resolved in
                guard resolved.element.traits.contains(.adjustable) else {
                    return .failure(
                        .increment,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .increment,
                            element: resolved.screenElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                let liveTarget = context.liveTarget
                _ = self.stash.increment(liveTarget)
                self.safecracker.showFingerprint(at: liveTarget.activationPoint)
                return .success(method: .increment)
            }
        )
    }

    func executeDecrement(_ target: ElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        await executeDecrement(target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    func executeDecrement(_ target: BatchExecutionTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        await executeDecrement(target as any SemanticElementTarget, recordedScreen: recordedScreen)
    }

    private func executeDecrement(_ target: any SemanticElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .decrement,
            recordedScreen: recordedScreen,
            deallocatedBoundary: "adjustable action",
            preflight: { resolved in
                guard resolved.element.traits.contains(.adjustable) else {
                    return .failure(
                        .decrement,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .decrement,
                            element: resolved.screenElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                let liveTarget = context.liveTarget
                _ = self.stash.decrement(liveTarget)
                self.safecracker.showFingerprint(at: liveTarget.activationPoint)
                return .success(method: .decrement)
            }
        )
    }

    func executeCustomAction(
        _ target: some CustomActionExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        if let containerTarget = target.actionContainerTarget {
            return executeContainerCustomAction(
                containerTarget,
                ordinal: target.actionContainerOrdinal,
                actionName: target.actionName
            )
        }
        guard let elementTarget = target.actionElementTarget else {
            return .failure(.customAction, message: "custom action failed: missing element or container target")
        }
        return await performElementAction(
            target: elementTarget,
            method: .customAction,
            recordedScreen: recordedScreen,
            deallocatedBoundary: "custom action"
        ) { context in
            let resolved = context.resolvedTarget
            let liveTarget = context.liveTarget
            switch self.stash.performCustomAction(named: target.actionName, on: liveTarget) {
            case .deallocated:
                return .failure(.customAction, message: "custom action failed")
            case .noSuchAction:
                return .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.missingCustomAction(
                        target.actionName,
                        element: resolved.screenElement
                    )
                )
            case .declined:
                return .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.declinedCustomAction(
                        target.actionName,
                        element: resolved.screenElement
                    )
                )
            case .succeeded:
                return .success(method: .customAction)
            }
        }
    }

    private func executeContainerCustomAction(
        _ matcher: ContainerMatcher,
        ordinal: Int?,
        actionName: String
    ) -> TheSafecracker.InteractionResult {
        let resolution = stash.resolveContainerTarget(matcher, ordinal: ordinal)
        guard case .resolved(let containerTarget) = resolution else {
            return .failure(
                .customAction,
                message: "custom action failed: \(resolution.diagnostics); try get_interface to inspect container stableIds."
            )
        }
        switch stash.performCustomAction(named: actionName, on: containerTarget) {
        case .deallocated:
            return .failure(.customAction, message: "custom action failed: container object deallocated")
        case .noSuchAction:
            let available = containerTarget.container.customActions.map(\.name).filter { !$0.isEmpty }
            let suffix = available.isEmpty ? "" : "; available custom actions: \(available.map { "\"\($0)\"" }.joined(separator: ", "))"
            return .failure(
                .customAction,
                message: "custom action failed: requestedAction=\"\(actionName)\" not found on container\(suffix)"
            )
        case .declined:
            return .failure(
                .customAction,
                message: "custom action failed: requestedAction=\"\(actionName)\" declined by container handler"
            )
        case .succeeded:
            safecracker.showFingerprint(at: CGPoint(
                x: containerTarget.container.frame.origin.x + containerTarget.container.frame.size.width / 2,
                y: containerTarget.container.frame.origin.y + containerTarget.container.frame.size.height / 2
            ))
            return .success(method: .customAction)
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
