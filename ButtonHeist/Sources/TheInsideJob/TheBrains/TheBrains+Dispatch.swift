#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

extension TheBrains {

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
            return await performInteraction(method: .activate) { await self.actions.executeActivate(target) }
        case .increment(let target):
            return await performInteraction(method: .increment) { await self.actions.executeIncrement(target) }
        case .decrement(let target):
            return await performInteraction(method: .decrement) { await self.actions.executeDecrement(target) }
        case .performCustomAction(let target):
            return await performInteraction(method: .customAction) { await self.actions.executeCustomAction(target) }
        case .rotor(let target):
            return await performRotor(target)
        case .editAction(let target):
            return await performInteraction(method: .editAction) { await self.actions.executeEditAction(target) }
        case .setPasteboard(let target):
            return await performInteraction(method: .setPasteboard) { await self.actions.executeSetPasteboard(target) }
        case .resignFirstResponder:
            return await performInteraction(method: .resignFirstResponder) { await self.actions.executeResignFirstResponder() }
        case .oneFingerTap(let target):
            return await performInteraction(method: .syntheticTap) { await self.actions.executeTap(target) }
        case .longPress(let target):
            return await performInteraction(method: .syntheticLongPress) { await self.actions.executeLongPress(target) }
        case .swipe(let target):
            return await performInteraction(method: .syntheticSwipe) { await self.actions.executeSwipe(target) }
        case .drag(let target):
            return await performInteraction(method: .syntheticDrag) { await self.actions.executeDrag(target) }
        case .typeText(let target):
            return await performInteraction(
                method: .typeText,
                afterStatePayload: { self.actions.typeTextPayload(for: target, in: $0) },
                interaction: { await self.actions.executeTypeText(target) }
            )
        case .scroll(let target):
            return await performInteraction(method: .scroll) { await self.navigation.executeScroll(target) }
        case .scrollToVisible(let target):
            return await performInteraction(method: .scrollToVisible) { await self.navigation.executeScrollToVisible(target) }
        case .scrollToEdge(let target):
            return await performInteraction(method: .scrollToEdge) { await self.navigation.executeScrollToEdge(target) }
        case .wait(let target):
            return await performWait(target: target)
        }
    }

    func executePasteboardRead() -> ActionResult {
        let result = actions.executeGetPasteboard()
        return ActionResult(
            success: result.success,
            method: result.method,
            message: result.message,
            errorKind: result.success ? nil : Self.actionErrorKind(for: result),
            payload: result.payload
        )
    }

    // MARK: - Interaction Pipeline

    func performInteraction(
        method: ActionMethod,
        afterStatePayload: ((PostActionObservation.BeforeState) -> ResultPayload?)? = nil,
        interaction: () async -> TheSafecracker.InteractionResult
    ) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: method)
        }
        guard let before = await interactionObservation.prepareBeforeState() else {
            return treeUnavailableResult(method: method)
        }
        let result = await interaction()

        return await interactionObservation.finishAfterAction(
            success: result.success,
            method: result.method,
            message: result.message,
            payload: result.payload,
            afterStatePayload: afterStatePayload,
            errorKind: Self.actionErrorKind(for: result),
            subjectEvidence: result.subjectEvidence,
            before: before
        )
    }

    func performRotor(_ target: RotorTarget) async -> ActionResult {
        return await performInteraction(method: .rotor) { await self.actions.executeRotor(target) }
    }

    func performWait(target: WaitTarget) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .wait)
        }
        let receipt = await interactionObservation.waitForPredicate(
            WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout)
        )
        return receipt.actionResult
    }

    static func actionErrorKind(for result: TheSafecracker.InteractionResult) -> ErrorKind? {
        guard !result.success else { return nil }
        switch result.failureKind {
        case .treeUnavailable:
            return .actionFailed
        case .timeout:
            return .timeout
        case .inputValidation:
            return .validationError
        case .targetUnavailable:
            return .elementNotFound
        case .none:
            return .actionFailed
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
