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
    /// semantic selector → reveal plan → fresh live geometry → actionable target.
    func performElementAction(
        target: any SemanticElementTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        deallocatedBoundary: String = "element action",
        preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)? = nil,
        action: @MainActor (LiveElementActionContext) async -> TheSafecracker.InteractionResult
    ) async -> TheSafecracker.InteractionResult {
        let normalizedTarget = stash.normalizeTarget(target)
        switch await liveActionTargetRecoveryPolicy.resolve(.init(
            normalizedTarget: normalizedTarget,
            method: method,
            requireInteractive: requireInteractive,
            deallocatedBoundary: deallocatedBoundary,
            preflight: preflight
        )) {
        case .success(let context):
            return await action(context)
        case .failure(let result):
            return result
        }
    }

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await executeActivate(target as any SemanticElementTarget)
    }

    func executeActivate(_ target: SemanticActionTarget) async -> TheSafecracker.InteractionResult {
        await executeActivate(BatchSemanticElementTarget(target))
    }

    private func executeActivate(_ target: any SemanticElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .activate
        ) { context in
            await ActivationPolicy(
                activate: stash.activate,
                refreshAndResolve: {
                    await self.liveActionTargetRecoveryPolicy.refreshActivationTarget(context.normalizedTarget)
                },
                syntheticTap: safecracker.tap,
                showFingerprint: safecracker.showFingerprint,
                tapReceiverDiagnostic: safecracker.tapReceiverDiagnostic,
                screenBounds: { ScreenMetrics.current.bounds }
            ).apply(to: context.liveTarget)
        }
    }

    func executeIncrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await executeIncrement(target as any SemanticElementTarget)
    }

    func executeIncrement(_ target: SemanticActionTarget) async -> TheSafecracker.InteractionResult {
        await executeIncrement(BatchSemanticElementTarget(target))
    }

    private func executeIncrement(_ target: any SemanticElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .increment,
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

    func executeDecrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await executeDecrement(target as any SemanticElementTarget)
    }

    func executeDecrement(_ target: SemanticActionTarget) async -> TheSafecracker.InteractionResult {
        await executeDecrement(BatchSemanticElementTarget(target))
    }

    private func executeDecrement(_ target: any SemanticElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .decrement,
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
        _ target: some CustomActionExecutionInput
    ) async -> TheSafecracker.InteractionResult {
        switch target.customActionSelection {
        case .container(let containerTarget, let ordinal, let actionName):
            return await executeContainerCustomAction(
                containerTarget,
                ordinal: ordinal,
                actionName: actionName
            )
        case .element(let elementTarget, let actionName):
            return await performElementAction(
                target: elementTarget,
                method: .customAction,
                deallocatedBoundary: "custom action"
            ) { context in
                let resolved = context.resolvedTarget
                let liveTarget = context.liveTarget
                switch self.stash.performCustomAction(named: actionName, on: liveTarget) {
                case .deallocated:
                    return .failure(.customAction, message: "custom action failed")
                case .noSuchAction:
                    return .failure(
                        .customAction,
                        message: ActionCapabilityDiagnostic.missingCustomAction(
                            actionName,
                            element: resolved.screenElement
                        )
                    )
                case .declined:
                    return .failure(
                        .customAction,
                        message: ActionCapabilityDiagnostic.declinedCustomAction(
                            actionName,
                            element: resolved.screenElement
                        )
                    )
                case .succeeded:
                    return .success(method: .customAction)
                }
            }
        }
    }

    private func executeContainerCustomAction(
        _ matcher: ContainerMatcher,
        ordinal: Int?,
        actionName: String
    ) async -> TheSafecracker.InteractionResult {
        let containerTarget: SemanticActionability.SemanticContainerActionableTarget
        switch await actionability.makeActionable(
            matcher: matcher,
            ordinal: ordinal,
            method: .customAction
        ) {
        case .actionable(let actionableTarget):
            containerTarget = actionableTarget
        case .failed(let failure):
            return failure.interactionResult(commandMethod: .customAction)
        }
        let liveContainerTarget = containerTarget.liveTarget
        switch stash.performCustomAction(named: actionName, on: liveContainerTarget) {
        case .deallocated:
            return .failure(.customAction, message: "custom action failed: container object deallocated")
        case .noSuchAction:
            let available = containerTarget.resolvedTarget.container.customActions.map { $0.name }.filter { !$0.isEmpty }
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
            safecracker.showFingerprint(at: liveContainerTarget.activationPoint)
            return .success(method: .customAction)
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
