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
        target: ElementTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        deallocatedBoundary: String = "element action",
        preflight: (@MainActor (TheStash.ScreenElement) -> TheSafecracker.InteractionResult?)? = nil,
        action: @MainActor (SemanticActionability.SemanticActionableTarget) async -> TheSafecracker.InteractionResult
    ) async -> TheSafecracker.InteractionResult {
        switch await navigation.actionability.makeActionable(
            for: target,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        ) {
        case .failed(let failure):
            return failure.interactionResult(commandMethod: method)
        case .actionable(let context):
            if let failure = preflight?(context.screenElement) {
                return failure
            }
            if let failure = interactivityFailure(
                context,
                method: method,
                requireInteractive: requireInteractive
            ) {
                return failure
            }
            return await action(context)
        }
    }

    private func refreshActivationTarget(
        _ target: ElementTarget
    ) async -> ActivationPolicy.RefreshResult {
        stash.commitVisibleObservation()
        switch await navigation.actionability.makeActionable(
            for: target,
            method: .activate,
            deallocatedBoundary: "activation retry"
        ) {
        case .actionable(let actionableTarget):
            return .resolved(
                screenElement: actionableTarget.screenElement,
                liveTarget: actionableTarget.liveTarget
            )
        case .failed(let failure):
            return .failure(failure.interactionResult(commandMethod: .activate))
        }
    }

    private func interactivityFailure(
        _ context: SemanticActionability.SemanticActionableTarget,
        method: ActionMethod,
        requireInteractive: Bool
    ) -> TheSafecracker.InteractionResult? {
        guard requireInteractive else { return nil }
        let screenElement = context.screenElement
        let liveTarget = context.liveTarget
        switch TheStash.Interactivity.checkInteractivity(screenElement.element, object: liveTarget.object) {
        case .blocked(let reason):
            return .failure(method, message: reason)
        case .interactive(let warning):
            if let warning { insideJobLogger.warning("\(warning)") }
        }
        guard TheStash.Interactivity.isInteractive(element: screenElement.element, object: liveTarget.object) else {
            return .failure(
                method,
                message: ActionCapabilityDiagnostic.unsupportedElementAction(
                    method,
                    element: screenElement
                )
            )
        }
        return nil
    }

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .activate
        ) { context in
            await ActivationPolicy(
                activate: stash.activate,
                refreshAndResolve: {
                    await self.refreshActivationTarget(context.target)
                },
                syntheticTap: safecracker.tap
            ).apply(to: context.liveTarget)
        }
    }

    func executeIncrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
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
                return .success(method: .increment)
            }
        )
    }

    func executeDecrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
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
                return .success(method: .decrement)
            }
        )
    }

    func executeCustomAction(
        _ target: CustomActionTarget
    ) async -> TheSafecracker.InteractionResult {
        await performElementAction(
            target: target.elementTarget,
            method: .customAction,
            deallocatedBoundary: "custom action"
        ) { context in
            let screenElement = context.screenElement
            let liveTarget = context.liveTarget
            switch self.stash.performCustomAction(named: target.actionName, on: liveTarget) {
            case .deallocated:
                return .failure(.customAction, message: "custom action failed")
            case .noSuchAction:
                return .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.missingCustomAction(
                        target.actionName,
                        element: screenElement
                    )
                )
            case .declined:
                return .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.declinedCustomAction(
                        target.actionName,
                        element: screenElement
                    )
                )
            case .succeeded:
                return .success(method: .customAction)
            }
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
