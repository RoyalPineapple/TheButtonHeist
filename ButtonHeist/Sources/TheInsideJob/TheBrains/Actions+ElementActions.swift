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
        stash.refresh()
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
                syntheticTap: safecracker.tap,
                showFingerprint: safecracker.showFingerprint,
                tapReceiverDiagnostic: safecracker.tapReceiverDiagnostic,
                screenBounds: { ScreenMetrics.current.bounds }
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
                self.safecracker.showFingerprint(at: liveTarget.activationPoint)
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
                target: elementTarget,
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
        let containerTarget: SemanticScreen.Container
        switch stash.resolveContainerTarget(matcher, ordinal: ordinal) {
        case .resolved(let target):
            containerTarget = target
        case .notFound(let diagnostics):
            return customActionFailure(.notFound("container target could not be made actionable: \(diagnostics)"))
        case .ambiguous(_, let diagnostics):
            return customActionFailure(.ambiguous("container target is ambiguous: \(diagnostics)"))
        }

        let description = TheStash.containerCandidateSummary(containerTarget)
        let liveContainerTarget: TheStash.LiveContainerTarget
        switch stash.resolveLiveContainerTarget(for: containerTarget) {
        case .resolved(let target):
            let placement = await navigation.actionability.scrollActivationPointIntoBounds(
                target.activationPoint,
                in: stash.liveScrollView(forContainerPath: containerTarget.path),
                method: .customAction,
                noScrollViewFailure: .noRevealPath(
                    "container target \(description) has no live scrollable ancestor to make actionable"
                ),
                unsafeProgrammaticScrollMessage: "container target \(description) "
                    + "is inside a scroll view that is unsafe for programmatic semantic reveal",
                scrollFailedMessage: "container target \(description) activation point could not be brought on-screen"
            )
            if case .failure(let failure) = placement {
                return failure.interactionResult(commandMethod: .customAction)
            }
        case .objectUnavailable:
            return customActionFailure(.staleRefresh("container target became stale before dispatch", method: .customAction))
        case .geometryUnavailable:
            return customActionFailure(.geometryNotActionable(
                "container target has no fresh actionable geometry",
                method: .customAction
            ))
        }

        switch stash.resolveLiveContainerTarget(for: containerTarget) {
        case .resolved(let target):
            guard ScreenMetrics.current.bounds.contains(target.activationPoint) else {
                return .failure(
                    .customAction,
                    message: SemanticActionability.SemanticActionabilityFailure
                        .geometryNotActionable(
                            "container target \(description) did not become actionable after activation point placement",
                            method: .customAction
                        )
                        .message
                )
            }
            liveContainerTarget = target
        case .objectUnavailable:
            return customActionFailure(.staleRefresh(
                "container target became stale after activation point placement",
                method: .customAction
            ))
        case .geometryUnavailable:
            return customActionFailure(.geometryNotActionable(
                "container target has no fresh actionable geometry after activation point placement",
                method: .customAction
            ))
        }
        switch stash.performCustomAction(named: actionName, on: liveContainerTarget) {
        case .deallocated:
            return .failure(.customAction, message: "custom action failed: container object deallocated")
        case .noSuchAction:
            let available = containerTarget.container.customActions.map { $0.name }.filter { !$0.isEmpty }
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

    private func customActionFailure(
        _ failure: SemanticActionability.SemanticActionabilityFailure
    ) -> TheSafecracker.InteractionResult {
        .failure(.customAction, message: failure.message)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
