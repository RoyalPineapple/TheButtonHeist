#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.InteractionResult {
        if let failure = await actionability.makeFirstResponderActionable(method: .editAction) {
            return failure.interactionResult(commandMethod: .editAction)
        }
        let success = safecracker.performEditAction(target.action)
        let message = success ? nil : ActionCapabilityDiagnostic.editActionFailed(
            target.action,
            stash: stash,
            safecracker: safecracker
        )
        return success
            ? .success(method: .editAction)
            : .failure(.editAction, message: message ?? "edit action failed")
    }

    func executeSetPasteboard(_ target: SetPasteboardTarget) async -> TheSafecracker.InteractionResult {
        if let failure = await actionability.makeFirstResponderActionable(method: .setPasteboard) {
            return failure.interactionResult(commandMethod: .setPasteboard)
        }
        UIPasteboard.general.string = target.text
        return .success(method: .setPasteboard, payload: .value(target.text))
    }

    func executeGetPasteboard() -> TheSafecracker.InteractionResult {
        let text = UIPasteboard.general.string
        return .success(
            method: .getPasteboard,
            message: text == nil ? "Pasteboard is empty or contains non-text data" : nil,
            payload: text.map(ResultPayload.value)
        )
    }

    func executeResignFirstResponder() async -> TheSafecracker.InteractionResult {
        if let failure = await actionability.makeFirstResponderActionable(method: .resignFirstResponder) {
            return failure.interactionResult(commandMethod: .resignFirstResponder)
        }
        let success = safecracker.resignFirstResponder()
        if success { return .success(method: .resignFirstResponder) }
        return .failure(
            .resignFirstResponder,
            message: ActionCapabilityDiagnostic.resignFirstResponderFailed(
                stash: stash,
                safecracker: safecracker
            )
        )
    }

    // MARK: - Text Entry

    func executeTypeText(
        _ target: some TypeTextExecutionInput
    ) async -> TheSafecracker.InteractionResult {
        guard !target.text.isEmpty else {
            return .failure(.typeText, message: "type_text requires non-empty text")
        }
        let normalizedTarget = target.typeTextElementTarget.map {
            stash.normalizeTarget($0)
        }
        if let failure = await focusTextInput(normalizedTarget) { return failure }

        let interKeyDelay = min(TheSafecracker.defaultInterKeyDelay, TheSafecracker.maxInterKeyDelay)
        let typingResult = await safecracker.typeText(target.text, interKeyDelay: interKeyDelay)
        if let diagnostic = typingResult.diagnostic {
            return .failure(.typeText, message: typeTextInjectionFailureMessage(for: diagnostic))
        }

        guard await Task.cancellableSleep(for: TheSafecracker.keyboardPollInterval) else { return .failure(.typeText, message: "Cancelled") }
        stash.refresh()

        var fieldValue: String?
        if let normalizedTarget,
           let executableTarget = normalizedTarget.executableTarget {
            if let resolved = stash.resolveTarget(executableTarget).resolved {
                fieldValue = resolved.element.value
            }
        }

        return .success(method: .typeText, payload: fieldValue.map(ResultPayload.value))
    }

    private func typeTextInjectionFailureMessage(for diagnostic: KeyboardTextInjectionDiagnostic) -> String {
        guard diagnostic.reason == .noActiveInput else { return diagnostic.message }
        return "\(diagnostic.message); " + ActionCapabilityDiagnostic.textEntryFailed(
            operation: "typing",
            stash: stash,
            safecracker: safecracker,
            suggestion: "focus an editable text field before typing"
        )
    }

    private func focusTextInput(
        _ normalizedTarget: TheStash.NormalizedTarget?
    ) async -> TheSafecracker.InteractionResult? {
        guard let normalizedTarget else {
            guard safecracker.hasActiveTextInput() else {
                return .failure(
                    .typeText,
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "initial focus check",
                        stash: stash,
                        safecracker: safecracker,
                        suggestion: "provide elementTarget for a text field or focus an editable field before typing"
                    )
                )
            }
            return nil
        }

        let liveTarget: TheStash.LiveActionTarget
        switch await actionability.makeActionable(
            for: normalizedTarget,
            method: .typeText,
            deallocatedBoundary: "text input focus"
        ) {
        case .actionable(let actionableTarget):
            liveTarget = actionableTarget.liveTarget
        case .failed(let failure):
            return failure.interactionResult(commandMethod: .typeText)
        }
        let point = liveTarget.activationPoint
        guard await safecracker.tap(at: point) else {
            return .failure(
                .typeText,
                message: ActionCapabilityDiagnostic.gestureDispatchFailed(
                    method: .syntheticTap,
                    point: point,
                    receiver: safecracker.tapReceiverDiagnostic(at: point)
                )
            )
        }
        safecracker.showFingerprint(at: point)

        guard await waitForActiveTextInput() else {
            return .failure(
                .typeText,
                message: ActionCapabilityDiagnostic.textEntryFailed(
                    operation: "post-tap keyboard readiness",
                    stash: stash,
                    safecracker: safecracker,
                    suggestion: "target an editable text field"
                )
            )
        }
        return nil
    }

    private func waitForActiveTextInput() async -> Bool {
        for _ in 0..<TheSafecracker.keyboardPollMaxAttempts {
            guard await Task.cancellableSleep(for: TheSafecracker.keyboardPollInterval) else { return false }
            if safecracker.hasActiveTextInput() { return true }
        }
        return false
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
