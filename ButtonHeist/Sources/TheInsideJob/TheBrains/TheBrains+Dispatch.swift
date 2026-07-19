#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal struct RuntimeActionExecution: Sendable, Equatable {
    internal let result: ActionResult
    internal let expectationBaseline: SettledCapture?
}

extension TheBrains {
    func executeRuntimeAction(_ command: ResolvedHeistActionCommand) async -> ActionResult {
        await executeRuntimeActionWithBaseline(command).result
    }

    func executeRuntimeActionWithBaseline(
        _ command: ResolvedHeistActionCommand,
        expectationBaselineScope: SemanticObservationScope? = nil
    ) async -> RuntimeActionExecution {
        let expectationBaseline = await interactionCoordinator.settledCapture(
            scope: expectationBaselineScope
        )

        clearRotorCursorBeforeNonRotorAction(command)
        let result: ActionResult
        switch command {
        case .activate(let target):
            result = await performInteraction(payload: .activate) {
                await self.actions.executeActivate(target)
            }
        case .increment(let target):
            result = await performInteraction(payload: .increment) {
                await self.actions.executeIncrement(target)
            }
        case .decrement(let target):
            result = await performInteraction(payload: .decrement) {
                await self.actions.executeDecrement(target)
            }
        case .customAction(let name, let target):
            result = await performInteraction(payload: .customAction) {
                await self.actions.executeCustomAction(name: name, target: target)
            }
        case .dismiss:
            result = await performInteraction(payload: .dismiss) {
                await self.actions.executeDismiss()
            }
        case .magicTap:
            result = await performInteraction(payload: .magicTap) {
                await self.actions.executeMagicTap()
            }
        case .rotor(let selection, let target, let direction):
            result = await performInteraction(payload: .rotor(nil)) {
                await self.actions.executeRotor(
                    selection: selection,
                    target: target,
                    direction: direction
                )
            }
        case .editAction(let target):
            result = await performInteraction(payload: .editAction) {
                await self.actions.executeEditAction(target)
            }
        case .setPasteboard(let target):
            result = await performInteraction(payload: .setPasteboard(nil)) {
                await self.actions.executeSetPasteboard(target)
            }
        case .takeScreenshot:
            result = await executeTakeScreenshot()
        case .dismissKeyboard:
            result = await performInteraction(payload: .dismissKeyboard) {
                await self.actions.executeResignFirstResponder()
            }
        case .oneFingerTap(let target):
            result = await performInteraction(payload: .oneFingerTap) {
                await self.actions.executeTap(target)
            }
        case .longPress(let target):
            result = await performInteraction(payload: .longPress) {
                await self.actions.executeLongPress(target)
            }
        case .swipe(let target):
            result = await performInteraction(payload: .swipe) {
                await self.actions.executeSwipe(target)
            }
        case .drag(let target):
            result = await performInteraction(payload: .drag) {
                await self.actions.executeDrag(target)
            }
        case .typeText(let payload):
            result = await executeTypeText(payload)
        case .scroll(let target):
            result = await executeViewportScroll(target)
        case .scrollToVisible(let target):
            result = await executeViewportScrollToVisible(target)
        case .scrollToEdge(let target):
            result = await executeViewportScrollToEdge(target)
        }
        return RuntimeActionExecution(
            result: result,
            expectationBaseline: expectationBaseline
        )
    }

    private func executeTypeText(_ payload: ResolvedTypeTextTarget) async -> ActionResult {
        await performInteraction(
            payload: .typeText(nil),
            afterStateValue: { context in
                context.resolvedElementId.flatMap {
                    self.actions.typeTextPayload(resolvedElementId: $0, in: context.committedBaseline)
                }
            },
            interaction: {
                await self.actions.executeTypeText(text: payload.text, target: payload.target)
            }
        )
    }

    private func executeViewportScroll(_ target: ResolvedScrollTarget) async -> ActionResult {
        await performInteraction(
            payload: .scroll,
            postActionCommitScope: .discovery
        ) {
            await self.navigation.executeScroll(target)
        }
    }

    private func executeViewportScrollToVisible(_ target: ResolvedAccessibilityTarget) async -> ActionResult {
        await performInteraction(
            payload: .scrollToVisible,
            postActionCommitScope: .discovery
        ) {
            await self.navigation.executeScrollToVisible(target: target)
        }
    }

    private func executeViewportScrollToEdge(_ target: ResolvedScrollToEdgeTarget) async -> ActionResult {
        await performInteraction(
            payload: .scrollToEdge,
            postActionCommitScope: .discovery
        ) {
            await self.navigation.executeScrollToEdge(target)
        }
    }

    func executeSemanticDiscovery() async -> Navigation.InterfaceExplorationResult? {
        await navigation.exploreScreen(exitPosition: .origin)
    }

    private func clearRotorCursorBeforeNonRotorAction(_ command: ResolvedHeistActionCommand) {
        if case .rotor = command {} else {
            vault.clearRotorCursor()
        }
    }

    func executePasteboardRead() -> ActionResult {
        let result = actions.executeGetPasteboard()
        switch result.outcome {
        case .success:
            return .success(payload: result.payload, message: result.message)
        case .failure(let failureKind):
            return .failure(
                payload: result.payload,
                failureKind: Self.actionFailureKind(for: failureKind),
                message: result.message
            )
        }
    }
    private func performInteraction(
        payload: ActionResult.Payload,
        beforeStateScope: SemanticObservationScope = .visible,
        postActionCommitScope: SemanticObservationScope = .visible,
        afterStateValue: ((ActionPayloadEvidence) -> String?)? = nil,
        interaction: () async -> TheSafecracker.ActionDispatchResult
    ) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: payload)
        }

        let actionStart = CFAbsoluteTimeGetCurrent()
        let beforeStart = actionStart
        guard let before = await interactionCoordinator.admittedBaseline(scope: beforeStateScope) else {
            return treeUnavailableResult(payload: payload)
        }
        let beforeObservationMs = elapsedMilliseconds(since: beforeStart)
        let notificationWindow = vault.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }

        let demand = vault.semanticObservationStream.beginActiveObservationDemand()
        defer { demand.cancel() }

        let interactionStart = CFAbsoluteTimeGetCurrent()
        let result = await interaction()
        let interactionMs = elapsedMilliseconds(since: interactionStart)

        let actionResult = await interactionCoordinator.settleAfterAction(
            dispatchResult: result,
            afterStateValue: afterStateValue,
            before: before,
            postActionCommitScope: postActionCommitScope,
            notificationWindow: notificationWindow
        )
        return actionResult.withTiming(ActionPerformanceTiming(
            beforeObservationMs: beforeObservationMs,
            targetResolutionMs: result.timing?.targetResolutionMs,
            actionDispatchMs: result.timing?.actionDispatchMs,
            interactionMs: interactionMs,
            totalMs: elapsedMilliseconds(since: actionStart)
        ))
    }

    func performWait(step: ResolvedWaitRuntimeInput) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: .wait)
        }
        let result = await interactionCoordinator.waitForPredicate(step)
        return result.outcome.actionResult
    }

    nonisolated static func actionFailureKind(
        for failureKind: TheSafecracker.FailureKind
    ) -> ActionFailure.Kind {
        switch failureKind {
        case .actionFailed:
            return .actionFailed
        case .treeUnavailable:
            return .accessibilityTreeUnavailable
        case .timeout:
            return .timeout
        case .inputValidation:
            return .validationError
        case .targetUnavailable:
            return .elementNotFound
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
