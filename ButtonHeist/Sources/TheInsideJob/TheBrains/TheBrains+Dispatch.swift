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
        let expectationBaseline = await interactionObservation.captureSettledBaseline(
            scope: expectationBaselineScope
        )

        clearRotorCursorBeforeNonRotorAction(command)
        let result: ActionResult
        switch command {
        case .activate(let target):
            result = await performInteraction(method: .activate) {
                await self.actions.executeActivate(target)
            }
        case .increment(let target):
            result = await performInteraction(method: .increment, observationScope: .discovery) {
                await self.actions.executeIncrement(target)
            }
        case .decrement(let target):
            result = await performInteraction(method: .decrement, observationScope: .discovery) {
                await self.actions.executeDecrement(target)
            }
        case .customAction(let name, let target):
            result = await performInteraction(method: .customAction, observationScope: .discovery) {
                await self.actions.executeCustomAction(name: name, target: target)
            }
        case .dismiss:
            result = await performInteraction(method: .dismiss) {
                await self.actions.executeDismiss()
            }
        case .magicTap:
            result = await performInteraction(method: .magicTap) {
                await self.actions.executeMagicTap()
            }
        case .rotor(let selection, let target, let direction):
            result = await performInteraction(method: .rotor, observationScope: .discovery) {
                await self.actions.executeRotor(
                    selection: selection,
                    target: target,
                    direction: direction
                )
            }
        case .editAction(let target):
            result = await performInteraction(method: .editAction) {
                await self.actions.executeEditAction(target)
            }
        case .setPasteboard(let target):
            result = await performInteraction(method: .setPasteboard) {
                await self.actions.executeSetPasteboard(target)
            }
        case .takeScreenshot:
            result = await executeTakeScreenshot()
        case .dismissKeyboard:
            result = await performInteraction(method: .resignFirstResponder) {
                await self.actions.executeResignFirstResponder()
            }
        case .mechanicalTap(let target):
            result = await performInteraction(
                method: .syntheticTap,
                observationScope: observationScope(for: target)
            ) {
                await self.actions.executeTap(target)
            }
        case .mechanicalLongPress(let target):
            result = await performInteraction(
                method: .syntheticLongPress,
                observationScope: observationScope(for: target)
            ) {
                await self.actions.executeLongPress(target)
            }
        case .mechanicalSwipe(let target):
            result = await performInteraction(
                method: .syntheticSwipe,
                observationScope: observationScope(for: target)
            ) {
                await self.actions.executeSwipe(target)
            }
        case .mechanicalDrag(let target):
            result = await performInteraction(
                method: .syntheticDrag,
                observationScope: observationScope(for: target)
            ) {
                await self.actions.executeDrag(target)
            }
        case .typeText(let payload):
            result = await executeTypeText(payload)
        case .viewportScroll(let target):
            result = await executeViewportScroll(target)
        case .viewportScrollToVisible(let target):
            result = await executeViewportScrollToVisible(target)
        case .viewportScrollToEdge(let target):
            result = await executeViewportScrollToEdge(target)
        }
        return RuntimeActionExecution(
            result: result,
            expectationBaseline: expectationBaseline
        )
    }

    private func executeTypeText(_ payload: ResolvedTypeTextTarget) async -> ActionResult {
        await performInteraction(
            method: .typeText,
            observationScope: .discovery,
            afterStatePayload: { context in
                context.resolvedElementId.flatMap {
                    self.actions.typeTextPayload(resolvedElementId: $0, in: context.baseline)
                }
            },
            interaction: {
                await self.actions.executeTypeText(text: payload.text, target: payload.target)
            }
        )
    }

    private func executeViewportScroll(_ target: ResolvedScrollTarget) async -> ActionResult {
        await performInteraction(
            method: .scroll,
            observationScope: .discovery,
            postActionCommitScope: .discovery
        ) {
            await self.navigation.executeScroll(target)
        }
    }

    private func executeViewportScrollToVisible(_ target: ResolvedAccessibilityTarget) async -> ActionResult {
        await performInteraction(
            method: .scrollToVisible,
            observationScope: .discovery,
            postActionCommitScope: .discovery
        ) {
            await self.navigation.executeScrollToVisible(target: target)
        }
    }

    private func executeViewportScrollToEdge(_ target: ResolvedScrollToEdgeTarget) async -> ActionResult {
        await performInteraction(
            method: .scrollToEdge,
            observationScope: .discovery,
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
            stash.clearRotorCursor()
        }
    }

    func executePasteboardRead() -> ActionResult {
        let result = actions.executeGetPasteboard()
        switch result.state {
        case .success(let payload, _):
            guard let payload else {
                return .success(method: result.method, message: result.message)
            }
            return .success(payload: payload, message: result.message)
        case .failure(let failureKind):
            return .failure(
                method: result.method,
                errorKind: Self.actionErrorKind(for: failureKind),
                message: result.message
            )
        }
    }
    private func performInteraction(
        method: ActionMethod,
        observationScope: SemanticObservationScope = .visible,
        beforeStateScope: SemanticObservationScope = .visible,
        postActionCommitScope: SemanticObservationScope = .visible,
        afterStatePayload: ((PostActionPayloadContext) -> ActionResultPayload?)? = nil,
        interaction: () async -> TheSafecracker.ActionDispatchOutcome
    ) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: method)
        }

        let actionStart = CFAbsoluteTimeGetCurrent()
        let beforeStart = actionStart
        guard let before = await interactionObservation.prepareBeforeState(scope: beforeStateScope) else {
            return treeUnavailableResult(method: method)
        }
        let beforeObservationMs = elapsedMilliseconds(since: beforeStart)
        let notificationWindow = stash.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }

        let demand = stash.semanticObservationStream.beginActiveObservationDemand(scope: observationScope)
        defer { demand.cancel() }

        let interactionStart = CFAbsoluteTimeGetCurrent()
        let result = await interaction()
        let interactionMs = elapsedMilliseconds(since: interactionStart)

        let actionResult = await interactionObservation.finishAfterAction(
            outcome: result,
            afterStatePayload: afterStatePayload,
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
            return runtimeInactiveResult(method: .wait)
        }
        let receipt = await interactionObservation.waitForPredicate(step)
        return receipt.result.actionResult
    }

    nonisolated static func actionErrorKind(for failureKind: TheSafecracker.FailureKind) -> ErrorKind {
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

    private func observationScope(for target: ResolvedTapTarget) -> SemanticObservationScope {
        observationScope(for: target.selection)
    }

    private func observationScope(for target: ResolvedLongPressTarget) -> SemanticObservationScope {
        observationScope(for: target.selection)
    }

    private func observationScope(for target: ResolvedSwipeTarget) -> SemanticObservationScope {
        switch target.selection {
        case .unitElement, .elementDirection:
            return .discovery
        case .pointToPoint, .pointDirection:
            return .visible
        }
    }

    private func observationScope(for target: ResolvedDragTarget) -> SemanticObservationScope {
        switch target.selection {
        case .elementToPoint:
            return .discovery
        case .pointToPoint:
            return .visible
        }
    }

    private func observationScope(for selection: ResolvedGesturePointSelection) -> SemanticObservationScope {
        switch selection {
        case .element, .elementUnitPoint:
            return .discovery
        case .coordinate:
            return .visible
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
