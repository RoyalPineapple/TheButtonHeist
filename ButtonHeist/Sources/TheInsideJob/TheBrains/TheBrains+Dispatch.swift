#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension TheBrains {
    struct PostActionPayloadContext {
        let afterState: PostActionObservation.BeforeState
        let resolvedElementId: HeistId?
    }

    // MARK: - Command Dispatch

    /// Execute a command through the full interaction pipeline:
    /// refresh → snapshot → execute → settle → semantic observation → delta → result.
    /// Returns the ActionResult for TheInsideJob to send.
    func executeRuntimeAction(_ message: RuntimeActionMessage) async -> ActionResult {
        // Rotor mode holds a single cursor only while consecutive rotor steps
        // run on the same host. Any other interaction exits rotor mode and drops
        // the held cursor.
        if case .rotor = message {} else {
            stash.clearRotorCursor()
        }
        switch message {
        case .activate(let target):
            return await performInteraction(method: .activate) {
                await self.actions.executeActivate(target)
            }
        case .increment(let target):
            return await performInteraction(method: .increment, observationScope: .discovery) {
                await self.actions.executeIncrement(target)
            }
        case .decrement(let target):
            return await performInteraction(method: .decrement, observationScope: .discovery) {
                await self.actions.executeDecrement(target)
            }
        case .performCustomAction(let target):
            return await performInteraction(method: .customAction, observationScope: .discovery) {
                await self.actions.executeCustomAction(target)
            }
        case .dismiss:
            return await performInteraction(method: .dismiss) { await self.actions.executeDismiss() }
        case .magicTap:
            return await performInteraction(method: .magicTap) { await self.actions.executeMagicTap() }
        case .rotor(let target):
            return await performRotor(target)
        case .editAction(let target):
            return await performInteraction(method: .editAction) { await self.actions.executeEditAction(target) }
        case .setPasteboard(let target):
            return await performInteraction(method: .setPasteboard) { await self.actions.executeSetPasteboard(target) }
        case .takeScreenshot:
            return await executeTakeScreenshot()
        case .resignFirstResponder:
            return await performInteraction(method: .resignFirstResponder) { await self.actions.executeResignFirstResponder() }
        case .oneFingerTap(let target):
            return await performInteraction(method: .syntheticTap, observationScope: observationScope(for: target)) {
                await self.actions.executeTap(target)
            }
        case .longPress(let target):
            return await performInteraction(method: .syntheticLongPress, observationScope: observationScope(for: target)) {
                await self.actions.executeLongPress(target)
            }
        case .swipe(let target):
            return await performInteraction(method: .syntheticSwipe, observationScope: observationScope(for: target)) {
                await self.actions.executeSwipe(target)
            }
        case .drag(let target):
            return await performInteraction(method: .syntheticDrag, observationScope: observationScope(for: target)) {
                await self.actions.executeDrag(target)
            }
        case .typeText(let target):
            return await performInteraction(
                method: .typeText,
                observationScope: .discovery,
                afterStatePayload: { context in
                    self.actions.typeTextPayload(
                        for: target,
                        resolvedElementId: context.resolvedElementId,
                        in: context.afterState
                    )
                },
                interaction: { await self.actions.executeTypeText(target) }
            )
        case .scroll(let target):
            return await performInteraction(
                method: .scroll,
                observationScope: .discovery,
                postActionCommitScope: .discovery
            ) {
                await self.navigation.executeScroll(target)
            }
        case .scrollToVisible(let target):
            return await performInteraction(
                method: .scrollToVisible,
                observationScope: .discovery,
                postActionCommitScope: .discovery
            ) {
                await self.navigation.executeScrollToVisible(target)
            }
        case .scrollToEdge(let target):
            return await performInteraction(
                method: .scrollToEdge,
                observationScope: .discovery,
                postActionCommitScope: .discovery
            ) {
                await self.navigation.executeScrollToEdge(target)
            }
        case .wait(let target):
            return await performWait(target: target)
        }
    }

    func executePasteboardRead() -> ActionResult {
        let result = actions.executeGetPasteboard()
        var builder = ActionResultBuilder()
        builder.message = result.message
        switch result.outcome {
        case .success(let success):
            guard let payload = success.payload else { return builder.success(method: result.method) }
            return builder.success(payload: payload)
        case .failure(let failure):
            return builder.failure(method: result.method, errorKind: Self.actionErrorKind(for: failure.kind))
        }
    }

    // MARK: - Interaction Pipeline

    func performInteraction(
        method: ActionMethod,
        observationScope: SemanticObservationScope = .visible,
        beforeStateScope: SemanticObservationScope = .visible,
        postActionCommitScope: SemanticObservationScope = .visible,
        afterStatePayload: ((PostActionPayloadContext) -> ActionResultPayload?)? = nil,
        interaction: () async -> TheSafecracker.InteractionResult
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

        let demand = stash.beginSemanticObservationDemand(scope: observationScope)
        defer { demand.cancel() }

        let interactionStart = CFAbsoluteTimeGetCurrent()
        let result = await interaction()
        let interactionMs = elapsedMilliseconds(since: interactionStart)
        let postActionOutcome: PostActionObservation.ActionOutcome
        switch result.outcome {
        case .success(let success):
            let payload: PostActionObservation.ActionOutcomePayload
            if let immediatePayload = success.payload {
                payload = .immediate(immediatePayload)
            } else if let afterStatePayload {
                payload = .afterState { afterState in
                    afterStatePayload(PostActionPayloadContext(
                        afterState: afterState,
                        resolvedElementId: success.resolvedElementId
                    ))
                }
            } else {
                payload = .none
            }
            postActionOutcome = .success(.init(
                payload: payload,
                subjectEvidence: success.subjectEvidence,
                activationTrace: success.activationTrace
            ))
        case .failure(let failure):
            postActionOutcome = .failure(.init(
                errorKind: Self.actionErrorKind(for: failure.kind),
                activationTrace: failure.activationTrace
            ))
        }

        let actionResult = await interactionObservation.finishAfterAction(
            method: result.method,
            outcome: postActionOutcome,
            message: result.message,
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

    func performRotor(_ target: RotorTarget) async -> ActionResult {
        return await performInteraction(method: .rotor, observationScope: .discovery) {
            await self.actions.executeRotor(target)
        }
    }

    func performWait(target: WaitTarget) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .wait)
        }
        let demand = stash.beginSemanticObservationDemand(scope: target.predicate.observationScope)
        defer { demand.cancel() }

        let receipt = await interactionObservation.waitForPredicate(
            WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout)
        )
        return receipt.actionResult
    }

    static func actionErrorKind(for result: TheSafecracker.InteractionResult) -> ErrorKind? {
        switch result.outcome {
        case .success:
            return nil
        case .failure(let failure):
            return actionErrorKind(for: failure.kind)
        }
    }

    static func actionErrorKind(for failureKind: TheSafecracker.FailureKind) -> ErrorKind {
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

    private func observationScope(for target: TapTarget) -> SemanticObservationScope {
        observationScope(for: target.selection)
    }

    private func observationScope(for target: LongPressTarget) -> SemanticObservationScope {
        observationScope(for: target.selection)
    }

    private func observationScope(for target: SwipeTarget) -> SemanticObservationScope {
        switch target.selection {
        case .unitElement, .elementDirection:
            return .discovery
        case .point(let start, _):
            return observationScope(for: start)
        }
    }

    private func observationScope(for target: DragTarget) -> SemanticObservationScope {
        observationScope(for: target.start)
    }

    private func observationScope(for selection: GesturePointSelection) -> SemanticObservationScope {
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
