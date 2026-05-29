#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

extension Actions {

    // MARK: - Element Action Pipeline

    /// Unified pipeline for actions that target an element:
    /// semantic selector → reveal plan → fresh live geometry → actionable target.
    func performElementAction(
        target: SemanticElementTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        deallocatedBoundary: String = "element action",
        preflight: (@MainActor (TheStash.ScreenElement) -> TheSafecracker.InteractionResult?)? = nil,
        action: @MainActor (SemanticActionability.SemanticActionableTarget) async -> TheSafecracker.InteractionResult
    ) async -> TheSafecracker.InteractionResult {
        switch await liveActionTargetRecoveryPolicy.resolve(.init(
            target: target,
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
        await executeActivate(.currentCapture(target))
    }

    func executeActivate(_ target: SemanticActionTarget) async -> TheSafecracker.InteractionResult {
        await executeActivate(.durable(target))
    }

    private func executeActivate(_ target: SemanticElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .activate
        ) { context in
            await ActivationPolicy(
                activate: stash.activate,
                refreshAndResolve: {
                    await self.liveActionTargetRecoveryPolicy.refreshActivationTarget(context.target)
                },
                syntheticTap: safecracker.tap,
                showFingerprint: safecracker.showFingerprint,
                tapReceiverDiagnostic: safecracker.tapReceiverDiagnostic,
                screenBounds: { ScreenMetrics.current.bounds }
            ).apply(to: context.liveTarget)
        }
    }

    func executeIncrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await executeIncrement(.currentCapture(target))
    }

    func executeIncrement(_ target: SemanticActionTarget) async -> TheSafecracker.InteractionResult {
        await executeIncrement(.durable(target))
    }

    private func executeIncrement(_ target: SemanticElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .increment,
            deallocatedBoundary: "adjustable action",
            preflight: { screenElement in
                guard screenElement.element.traits.contains(.adjustable) else {
                    return .failure(
                        .increment,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .increment,
                            element: screenElement
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
        await executeDecrement(.currentCapture(target))
    }

    func executeDecrement(_ target: SemanticActionTarget) async -> TheSafecracker.InteractionResult {
        await executeDecrement(.durable(target))
    }

    private func executeDecrement(_ target: SemanticElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .decrement,
            deallocatedBoundary: "adjustable action",
            preflight: { screenElement in
                guard screenElement.element.traits.contains(.adjustable) else {
                    return .failure(
                        .decrement,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .decrement,
                            element: screenElement
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
        _ target: CustomActionTarget
    ) async -> TheSafecracker.InteractionResult {
        switch target.selection {
        case .container(let containerTarget, let ordinal, let actionName):
            return await executeContainerCustomAction(
                containerTarget,
                ordinal: ordinal,
                actionName: actionName
            )
        case .element(let elementTarget, let actionName):
            return await performElementAction(
                target: .currentCapture(elementTarget),
                method: .customAction,
                deallocatedBoundary: "custom action"
            ) { context in
                let screenElement = context.screenElement
                let liveTarget = context.liveTarget
                switch self.stash.performCustomAction(named: actionName, on: liveTarget) {
                case .deallocated:
                    return .failure(.customAction, message: "custom action failed")
                case .noSuchAction:
                    return .failure(
                        .customAction,
                        message: ActionCapabilityDiagnostic.missingCustomAction(
                            actionName,
                            element: screenElement
                        )
                    )
                case .declined:
                    return .failure(
                        .customAction,
                        message: ActionCapabilityDiagnostic.declinedCustomAction(
                            actionName,
                            element: screenElement
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
            let available = containerTarget.containerTarget.container.customActions.map { $0.name }.filter { !$0.isEmpty }
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
