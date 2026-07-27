#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension Actions {

    func performElementAction(
        target: ResolvedAccessibilityTarget,
        payload: ActionResult.Payload,
        timing: inout ActionTiming,
        requireInteractive: Bool = true,
        activationPointPolicy: ElementInflation.ActivationPointPolicy = .requireOnscreen,
        preflight: (@MainActor (InterfaceTree.Element) -> TheSafecracker.ActionDispatchResult?)? = nil,
        action: @MainActor (ElementInflation.InflatedElementTarget) async
            -> TheSafecracker.ActionDispatchResult
    ) async -> TheSafecracker.ActionDispatchResult {
        let resolutionStart = RuntimeElapsed.now
        let inflation = await navigation.elementInflation.inflate(
            for: target,
            method: payload.method,
            activationPointPolicy: activationPointPolicy
        )
        timing.record(.targetResolution, since: resolutionStart)

        let dispatchStart = RuntimeElapsed.now
        let result: TheSafecracker.ActionDispatchResult
        switch inflation {
        case .failed(let failure):
            result = failure.actionDispatchResult(payload: payload)
        case .inflated(let context):
            if let failure = preflight?(context.treeElement) {
                result = failure
            } else if let failure = interactivityFailure(
                context,
                payload: payload,
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

        timing.record(.actionDispatch, since: dispatchStart)
        return result
    }

    private func interactivityFailure(
        _ context: ElementInflation.InflatedElementTarget,
        payload: ActionResult.Payload,
        requireInteractive: Bool
    ) -> TheSafecracker.ActionDispatchResult? {
        guard requireInteractive else { return nil }
        let treeElement = context.treeElement
        if let reason = TheVault.Interactivity.blockedReason(treeElement.element) {
            // Deliberate VoiceOver divergence: VoiceOver permits the double-tap
            // and lets the app ignore it, while `notEnabled` is explicit
            // accessibility state saying that Button Heist should not dispatch.
            return .failure(payload, message: reason)
        }
        // VoiceOver calls accessibilityActivate() for any target, then dispatches
        // at its activation point when it declines. Let expectations arbitrate
        // whether that delivery had the intended effect.
        guard payload.method != .activate else { return nil }
        guard TheVault.Interactivity.isInteractive(element: treeElement.element) else {
            return .failure(
                payload,
                message: ActionCapabilityDiagnostic.unsupportedElementAction(
                    payload.method,
                    element: treeElement
                )
            )
        }
        return nil
    }

    func executeActivate(
        _ target: ResolvedAccessibilityTarget,
        timing: inout ActionTiming
    ) async -> TheSafecracker.ActionDispatchResult {
        return await performElementAction(
            target: target,
            payload: .activate,
            timing: &timing
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
                        return .failure(failure.actionDispatchResult(payload: .activate))
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
    ) async -> TheSafecracker.ActionDispatchResult? {
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
        timing: inout ActionTiming
    ) async -> TheSafecracker.ActionDispatchResult {
        await executeAdjustment(
            target,
            payload: .increment,
            timing: &timing,
            action: accessibilityActions.increment
        )
    }

    func executeDecrement(
        _ target: ResolvedAccessibilityTarget,
        timing: inout ActionTiming
    ) async -> TheSafecracker.ActionDispatchResult {
        await executeAdjustment(
            target,
            payload: .decrement,
            timing: &timing,
            action: accessibilityActions.decrement
        )
    }

    private func executeAdjustment(
        _ target: ResolvedAccessibilityTarget,
        payload: ActionResult.Payload,
        timing: inout ActionTiming,
        action: @MainActor (TheVault.LiveActionTarget) -> Bool
    ) async -> TheSafecracker.ActionDispatchResult {
        await performElementAction(
            target: target,
            payload: payload,
            timing: &timing,
            preflight: { treeElement in
                guard treeElement.element.traits.contains(.adjustable) else {
                    return .failure(
                        payload,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            payload.method,
                            element: treeElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                switch self.vault.dispatchOnFreshLiveActionTarget(context.liveTarget, operation: action) {
                case .success:
                    return .success(payload: payload)
                case .failure(let staleness):
                    return self.staleLiveTargetFailure(staleness, payload: payload)
                }
            }
        )
    }

    func executeCustomAction(
        name: CustomActionName,
        target: ResolvedAccessibilityTarget,
        timing: inout ActionTiming
    ) async -> TheSafecracker.ActionDispatchResult {
        await performElementAction(
            target: target,
            payload: .customAction,
            timing: &timing
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
            let result: TheSafecracker.ActionDispatchResult
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
                return self.staleLiveTargetFailure(staleness, payload: .customAction)
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
                result = .success(payload: .customAction)
            }
            return result.withSubjectEvidence(
                dispatchContext.subjectEvidence(source: .resolvedSemanticTarget)
            )
        }
    }

    private enum CustomActionDispatchContextResolution {
        case resolved(ElementInflation.InflatedElementTarget)
        case failed(TheSafecracker.ActionDispatchResult)
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
            return .failed(failure.actionDispatchResult(payload: .customAction))
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
