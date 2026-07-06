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
        target: ElementTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        activationPointPolicy: ElementInflation.ActivationPointPolicy = .requireOnscreen,
        deallocatedBoundary: String = "element action",
        preflight: (@MainActor (TheStash.ScreenElement) -> TheSafecracker.InteractionResult?)? = nil,
        action: @MainActor (ElementInflation.InflatedElementTarget) async -> TheSafecracker.InteractionResult
    ) async -> TheSafecracker.InteractionResult {
        func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
            Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
        }

        let resolutionStart = CFAbsoluteTimeGetCurrent()
        let inflation = await navigation.elementInflation.inflate(
            for: target,
            method: method,
            deallocatedBoundary: deallocatedBoundary,
            activationPointPolicy: activationPointPolicy
        )
        let targetResolutionMs = elapsedMilliseconds(since: resolutionStart)

        let dispatchStart = CFAbsoluteTimeGetCurrent()
        let result: TheSafecracker.InteractionResult
        switch inflation {
        case .failed(let failure):
            result = failure.interactionResult(commandMethod: method)
        case .inflated(let context):
            if let failure = preflight?(context.screenElement) {
                result = failure
            } else if let failure = interactivityFailure(
                context,
                method: method,
                requireInteractive: requireInteractive
            ) {
                result = failure
            } else {
                result = await action(context).withSubjectEvidence(
                    context.subjectEvidence(source: .resolvedSemanticTarget)
                )
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

    /// Deliver `activate` through the accessibility contract:
    /// semantic target -> reveal -> activation refresh ->
    /// one `accessibilityActivate()` -> activation-point dispatch if UIKit declines.
    func executeActivate(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .activate
        ) { context in
            await ActivationPolicy(
                accessibilityActivate: accessibilityActions.activate,
                refreshAndResolve: {
                    switch await self.navigation.elementInflation.inflateAfterActivationRefresh(
                        for: context.target
                    ) {
                    case .inflated(let inflatedTarget):
                        return .resolved(
                            screenElement: inflatedTarget.screenElement,
                            liveTarget: inflatedTarget.liveTarget
                        )
                    case .failed(let failure):
                        return .failure(failure.interactionResult(commandMethod: .activate))
                    }
                },
                activationPointDispatch: safecracker.tap,
                showFingerprint: safecracker.showFingerprint,
                textEntryActivationFailure: textEntryActivationFailure
            ).apply(to: context.liveTarget)
        }
    }

    private func textEntryActivationFailure(
        screenElement: TheStash.ScreenElement,
        activationTrace: ActivationTrace
    ) async -> TheSafecracker.InteractionResult? {
        guard screenElement.element.traits.contains(.textEntry) else { return nil }
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
                _ = self.accessibilityActions.increment(liveTarget)
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
                _ = self.accessibilityActions.decrement(liveTarget)
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
            let dispatchContext: ElementInflation.InflatedElementTarget
            switch await self.customActionDispatchContext(
                context,
                actionName: target.actionName
            ) {
            case .resolved(let context):
                dispatchContext = context
            case .failed(let result):
                return result
            }
            let screenElement = dispatchContext.screenElement
            let liveTarget = dispatchContext.liveTarget
            switch self.accessibilityActions.performCustomAction(named: target.actionName, on: liveTarget) {
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

    private enum CustomActionDispatchContextResolution {
        case resolved(ElementInflation.InflatedElementTarget)
        case failed(TheSafecracker.InteractionResult)
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
        switch await navigation.elementInflation.inflate(
            for: context.target,
            method: .customAction,
            deallocatedBoundary: "custom action dispatch refresh"
        ) {
        case .inflated(let refreshedContext):
            return .resolved(refreshedContext)
        case .failed(let failure):
            return .failed(failure.interactionResult(commandMethod: .customAction))
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
