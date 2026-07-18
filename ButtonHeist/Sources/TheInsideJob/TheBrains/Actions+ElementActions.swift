#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension Actions {

    func performElementAction(
        target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        activationPointPolicy: ElementInflation.ActivationPointPolicy = .requireOnscreen,
        preflight: (@MainActor (InterfaceTree.Element) -> TheSafecracker.ActionDispatchOutcome?)? = nil,
        action: @MainActor (ElementInflation.InflatedElementTarget) async
            -> TheSafecracker.ActionDispatchOutcome
    ) async -> TheSafecracker.ActionDispatchOutcome {
        func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
            Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
        }

        let resolutionStart = CFAbsoluteTimeGetCurrent()
        let inflation = await navigation.elementInflation.inflate(
            for: target,
            method: method,
            activationPointPolicy: activationPointPolicy
        )
        let targetResolutionMs = elapsedMilliseconds(since: resolutionStart)

        let dispatchStart = CFAbsoluteTimeGetCurrent()
        let result: TheSafecracker.ActionDispatchOutcome
        switch inflation {
        case .failed(let failure):
            result = failure.actionDispatchOutcome(commandMethod: method)
        case .inflated(let context):
            if let failure = preflight?(context.treeElement) {
                result = failure
            } else if let failure = interactivityFailure(
                context,
                method: method,
                requireInteractive: requireInteractive
            ) {
                result = failure
            } else {
                let dispatchResult = await action(context)
                let initialEvidence = dispatchResult.success
                    ? context.subjectEvidence(source: .resolvedSemanticTarget)
                    : nil
                let subjectEvidence = dispatchResult.subjectEvidence ?? initialEvidence
                result = dispatchResult
                    .withSubjectEvidence(subjectEvidence)
                    .withResolvedElementId(context.treeElement.heistId)
            }
        }

        return result.withTiming(ActionPerformanceTiming(
            targetResolutionMs: targetResolutionMs,
            actionDispatchMs: elapsedMilliseconds(since: dispatchStart)
        ))
    }

    private func interactivityFailure(
        _ context: ElementInflation.InflatedElementTarget,
        method: ActionMethod,
        requireInteractive: Bool
    ) -> TheSafecracker.ActionDispatchOutcome? {
        guard requireInteractive else { return nil }
        let treeElement = context.treeElement
        let liveTarget = context.liveTarget
        switch TheVault.Interactivity.checkInteractivity(treeElement.element, object: liveTarget.object) {
        case .blocked(let reason):
            return .failure(method, message: reason)
        case .interactive(let warning):
            if let warning { insideJobLogger.warning("\(warning)") }
        }
        guard TheVault.Interactivity.isInteractive(element: treeElement.element, object: liveTarget.object) else {
            return .failure(
                method,
                message: ActionCapabilityDiagnostic.unsupportedElementAction(
                    method,
                    element: treeElement
                )
            )
        }
        return nil
    }

    func executeActivate(
        _ target: ResolvedAccessibilityTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        return await performElementAction(
            target: target,
            method: .activate,
        ) { context in
            await ActivationPolicy(
                accessibilityActivate: { liveTarget in
                    self.vault.dispatchOnFreshLiveActionTarget(
                        liveTarget,
                    ) { currentTarget in
                        ActivationDispatchEvidence(
                            outcome: self.accessibilityActions.activate(currentTarget),
                            activationPoint: currentTarget.activationPoint
                        )
                    }
                },
                refreshAndResolve: {
                    switch await self.navigation.elementInflation.refreshCommittedTarget(
                        context.committedTarget,
                        method: .activate,
                    ) {
                    case .inflated(let inflatedTarget):
                        return .resolved(inflatedTarget)
                    case .failed(let failure):
                        return .failure(failure.actionDispatchOutcome(commandMethod: .activate))
                    }
                },
                prepareActivationPointDispatch: safecracker.prepareTap,
                completeActivationPointDispatch: safecracker.completePreparedTouch,
                showFingerprint: safecracker.showFingerprint,
                textEntryActivationFailure: textEntryActivationFailure
            ).apply(to: context.liveTarget)
        }
    }

    private func textEntryActivationFailure(
        treeElement: InterfaceTree.Element,
        activationTrace: ActivationTrace
    ) async -> TheSafecracker.ActionDispatchOutcome? {
        guard treeElement.element.traits.contains(.textEntry) else { return nil }
        guard await safecracker.waitForActiveTextInput() else {
            return .failure(
                .activate,
                message: ActionCapabilityDiagnostic.textEntryFailed(
                    operation: "post-activation keyboard readiness",
                    vault: vault,
                    safecracker: safecracker,
                    suggestion: "target an editable text field"
                ),
                activationTrace: activationTrace
            )
        }
        return nil
    }

    func executeIncrement(
        _ target: ResolvedAccessibilityTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        await executeAdjustment(target, method: .increment, action: accessibilityActions.increment)
    }

    func executeDecrement(
        _ target: ResolvedAccessibilityTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        await executeAdjustment(target, method: .decrement, action: accessibilityActions.decrement)
    }

    private func executeAdjustment(
        _ target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        action: @MainActor (TheVault.LiveActionTarget) -> Bool
    ) async -> TheSafecracker.ActionDispatchOutcome {
        await performElementAction(
            target: target,
            method: method,
            preflight: { treeElement in
                guard treeElement.element.traits.contains(.adjustable) else {
                    return .failure(
                        method,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            method,
                            element: treeElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                switch self.vault.dispatchOnFreshLiveActionTarget(context.liveTarget, operation: action) {
                case .success:
                    return .success(method: method)
                case .failure(let staleness):
                    return self.staleLiveTargetFailure(staleness, method: method)
                }
            }
        )
    }

    func executeCustomAction(
        name: CustomActionName,
        target: ResolvedAccessibilityTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        await performElementAction(
            target: target,
            method: .customAction,
        ) { context in
            let dispatchContext: ElementInflation.InflatedElementTarget
            switch await self.customActionDispatchContext(
                context,
                actionName: name,
            ) {
            case .resolved(let context):
                dispatchContext = context
            case .failed(let result):
                return result
            }
            let treeElement = dispatchContext.treeElement
            let liveTarget = dispatchContext.liveTarget
            let result: TheSafecracker.ActionDispatchOutcome
            let dispatch = self.vault.dispatchOnFreshLiveActionTarget(
                liveTarget,
            ) { target in
                self.accessibilityActions.performCustomAction(named: name, on: target)
            }
            let customActionOutcome: AccessibilityActionDispatcher.CustomActionOutcome
            switch dispatch {
            case .success(let outcome):
                customActionOutcome = outcome
            case .failure(let staleness):
                return self.staleLiveTargetFailure(staleness, method: .customAction)
            }
            switch customActionOutcome {
            case .deallocated:
                result = .failure(.customAction, message: "custom action failed")
            case .noSuchAction:
                result = .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.missingCustomAction(
                        name,
                        element: treeElement
                    )
                )
            case .declined:
                result = .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.declinedCustomAction(
                        name,
                        element: treeElement
                    )
                )
            case .succeeded:
                result = .success(method: .customAction)
            }
            return result.withSubjectEvidence(
                dispatchContext.subjectEvidence(source: .resolvedSemanticTarget)
            )
        }
    }

    private enum CustomActionDispatchContextResolution {
        case resolved(ElementInflation.InflatedElementTarget)
        case failed(TheSafecracker.ActionDispatchOutcome)
    }

    private func customActionDispatchContext(
        _ context: ElementInflation.InflatedElementTarget,
        actionName: CustomActionName,
    ) async -> CustomActionDispatchContextResolution {
        guard accessibilityActions.needsPreDispatchRefresh(named: actionName, on: context.liveTarget) else {
            return .resolved(context)
        }

        await tripwire.yieldFrames(1)
        switch await navigation.elementInflation.refreshCommittedTarget(
            context.committedTarget,
            method: .customAction,
        ) {
        case .inflated(let refreshedContext):
            return .resolved(refreshedContext)
        case .failed(let failure):
            return .failed(failure.actionDispatchOutcome(commandMethod: .customAction))
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
