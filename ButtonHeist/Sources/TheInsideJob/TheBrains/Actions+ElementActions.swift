#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension Actions {

    // MARK: - Element Action Pipeline

    /// Unified pipeline for actions that target an element:
    /// find target in tree → resolve that tree entry to something touchable.
    func performElementAction(
        target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        activationPointPolicy: ElementInflation.ActivationPointPolicy = .requireOnscreen,
        preflight: (@MainActor (InterfaceTree.Element) -> TheSafecracker.ActionDispatchOutcome?)? = nil,
        action: @MainActor (ElementInflation.InflatedElementTarget) async -> TheSafecracker.ActionDispatchOutcome
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
        switch TheStash.Interactivity.checkInteractivity(treeElement.element, object: liveTarget.object) {
        case .blocked(let reason):
            return .failure(method, message: reason)
        case .interactive(let warning):
            if let warning { insideJobLogger.warning("\(warning)") }
        }
        guard TheStash.Interactivity.isInteractive(element: treeElement.element, object: liveTarget.object) else {
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

    // MARK: - Accessibility Actions

    /// Deliver `activate` through the accessibility contract:
    /// semantic target -> reveal -> activation refresh ->
    /// one `accessibilityActivate()` -> activation-point dispatch if UIKit declines.
    func executeActivate(_ target: ResolvedAccessibilityTarget) async -> TheSafecracker.ActionDispatchOutcome {
        return await performElementAction(
            target: target,
            method: .activate
        ) { context in
            await ActivationPolicy(
                accessibilityActivate: accessibilityActions.activate,
                refreshAndResolve: {
                    switch await self.navigation.elementInflation.refreshCommittedTarget(
                        context.committedTarget,
                        method: .activate
                    ) {
                    case .inflated(let inflatedTarget):
                        return .resolved(inflatedTarget)
                    case .failed(let failure):
                        return .failure(failure.actionDispatchOutcome(commandMethod: .activate))
                    }
                },
                activationPointDispatch: safecracker.tap,
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
                    stash: stash,
                    safecracker: safecracker,
                    suggestion: "target an editable text field"
                ),
                activationTrace: activationTrace
            )
        }
        return nil
    }

    func executeIncrement(_ target: ResolvedAccessibilityTarget) async -> TheSafecracker.ActionDispatchOutcome {
        return await performElementAction(
            target: target,
            method: .increment,
            preflight: { treeElement in
                guard treeElement.element.traits.contains(.adjustable) else {
                    return .failure(
                        .increment,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .increment,
                            element: treeElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                let liveTarget = context.liveTarget
                _ = self.accessibilityActions.increment(liveTarget)
                return .success(method: .increment)
            }
        )
    }

    func executeDecrement(_ target: ResolvedAccessibilityTarget) async -> TheSafecracker.ActionDispatchOutcome {
        return await performElementAction(
            target: target,
            method: .decrement,
            preflight: { treeElement in
                guard treeElement.element.traits.contains(.adjustable) else {
                    return .failure(
                        .decrement,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .decrement,
                            element: treeElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                let liveTarget = context.liveTarget
                _ = self.accessibilityActions.decrement(liveTarget)
                return .success(method: .decrement)
            }
        )
    }

    func executeCustomAction(
        name: String,
        target: ResolvedAccessibilityTarget
    ) async -> TheSafecracker.ActionDispatchOutcome {
        await performElementAction(
            target: target,
            method: .customAction
        ) { context in
            let dispatchContext: ElementInflation.InflatedElementTarget
            switch await self.customActionDispatchContext(
                context,
                actionName: name
            ) {
            case .resolved(let context):
                dispatchContext = context
            case .failed(let result):
                return result
            }
            let treeElement = dispatchContext.treeElement
            let liveTarget = dispatchContext.liveTarget
            let result: TheSafecracker.ActionDispatchOutcome
            switch self.accessibilityActions.performCustomAction(named: name, on: liveTarget) {
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
        actionName: String
    ) async -> CustomActionDispatchContextResolution {
        guard accessibilityActions.needsPreDispatchRefresh(named: actionName, on: context.liveTarget) else {
            return .resolved(context)
        }

        // SwiftUI can update an AccessibilityNode's label/value before its block-backed custom actions.
        await tripwire.yieldFrames(1)
        switch await navigation.elementInflation.refreshCommittedTarget(
            context.committedTarget,
            method: .customAction
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
