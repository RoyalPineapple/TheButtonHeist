#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Actions {

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.InteractionResult {
        if let failure = await navigation.elementInflation.inflateFirstResponder(method: .editAction) {
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
        if let failure = await navigation.elementInflation.inflateFirstResponder(method: .setPasteboard) {
            return failure.interactionResult(commandMethod: .setPasteboard)
        }
        UIPasteboard.general.string = target.text
        return .success(payload: .setPasteboard(target.text))
    }

    func executeGetPasteboard() -> TheSafecracker.InteractionResult {
        let text = UIPasteboard.general.string
        guard let text else {
            return .success(
                method: .getPasteboard,
                message: "Pasteboard is empty or contains non-text data"
            )
        }
        return .success(payload: .getPasteboard(text))
    }

    func executeResignFirstResponder() async -> TheSafecracker.InteractionResult {
        if let failure = await navigation.elementInflation.inflateFirstResponder(method: .resignFirstResponder) {
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
        _ target: TypeTextTarget
    ) async -> TheSafecracker.InteractionResult {
        guard target.replacingExisting || !target.text.isEmpty else {
            return .failure(.typeText, message: "type_text requires non-empty text")
        }
        let elementTarget = target.elementTarget
        let focusResult = await focusTextInput(elementTarget)
        switch focusResult {
        case .alreadyFocused:
            return await executeTypeText(target, using: nil)
        case .focused(let input):
            return await executeTypeText(target, using: input)
        case .failed(let failure):
            return failure
        }
    }

    private func executeTypeText(
        _ target: TypeTextTarget,
        using focusedInput: FocusedTextInput?
    ) async -> TheSafecracker.InteractionResult {
        if target.replacingExisting {
            let clearResult = await safecracker.clearText(existingValue: focusedInput?.currentValue)
            if let diagnostic = clearResult.diagnostic {
                return .failure(.typeText, message: typeTextInjectionFailureMessage(for: diagnostic, operation: "clearing"))
            }
        }

        if !target.text.isEmpty {
            let typingResult = await safecracker.typeText(target.text)
            if let diagnostic = typingResult.diagnostic {
                return .failure(.typeText, message: typeTextInjectionFailureMessage(for: diagnostic, operation: "typing"))
            }
        }

        if let value = Self.liveTextInputValue(for: focusedInput?.resolvedObject) {
            return .success(
                payload: .typeText(value),
                subjectEvidence: focusedInput?.subjectEvidence,
                resolvedElementId: focusedInput?.resolvedElementId
            )
        }
        return .success(
            method: .typeText,
            subjectEvidence: focusedInput?.subjectEvidence,
            resolvedElementId: focusedInput?.resolvedElementId
        )
    }

    func typeTextPayload(
        for target: TypeTextTarget,
        resolvedElementId: HeistId?,
        in afterState: PostActionObservation.BeforeState
    ) -> ActionResultPayload? {
        if let resolvedElementId,
           let value = afterState.screen.findElement(heistId: resolvedElementId)?.element.value {
            return .typeText(value)
        }
        guard let elementTarget = target.elementTarget else { return nil }
        return Self.textInputValue(for: elementTarget, in: afterState.interface.projectedElements)
            .map(ActionResultPayload.typeText)
    }

    private func typeTextInjectionFailureMessage(
        for diagnostic: KeyboardTextInjectionDiagnostic,
        operation: String
    ) -> String {
        guard diagnostic.reason == .noActiveInput else { return diagnostic.message }
        return "\(diagnostic.message); " + ActionCapabilityDiagnostic.textEntryFailed(
            operation: operation,
            stash: stash,
            safecracker: safecracker,
            suggestion: "focus an editable text field before \(operation)"
        )
    }

    private enum TextInputFocusResult {
        case alreadyFocused
        case focused(FocusedTextInput)
        case failed(TheSafecracker.InteractionResult)
    }

    private struct FocusedTextInput {
        let subjectEvidence: ActionSubjectEvidence
        let resolvedElementId: HeistId
        let resolvedObject: NSObject
        let currentValue: String?
    }

    private func focusTextInput(
        _ elementTarget: ElementTarget?
    ) async -> TextInputFocusResult {
        guard let elementTarget else {
            guard safecracker.hasActiveTextInput() else {
                return .failed(.failure(
                    .typeText,
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "initial focus check",
                        stash: stash,
                        safecracker: safecracker,
                        suggestion: "provide elementTarget for a text field or focus an editable field before typing"
                    )
                ))
            }
            return .alreadyFocused
        }

        let liveTarget: TheStash.LiveActionTarget
        let subjectEvidence: ActionSubjectEvidence
        let resolvedElementId: HeistId
        switch await navigation.elementInflation.inflate(
            for: elementTarget,
            method: .typeText,
            deallocatedBoundary: "text input focus"
        ) {
        case .inflated(let inflatedTarget):
            liveTarget = inflatedTarget.liveTarget
            subjectEvidence = inflatedTarget.subjectEvidence(source: .textInputTarget)
            resolvedElementId = inflatedTarget.screenElement.heistId
        case .failed(let failure):
            return .failed(failure.interactionResult(commandMethod: .typeText))
        }
        let point = liveTarget.activationPoint
        guard await safecracker.tap(at: point) else {
            return .failed(.failure(
                .typeText,
                message: ActionCapabilityDiagnostic.gestureDispatchFailed(
                    method: .syntheticTap,
                    point: point,
                    receiver: safecracker.tapReceiverDiagnostic(at: point)
                )
            ))
        }

        guard await waitForActiveTextInput() else {
            return .failed(.failure(
                .typeText,
                message: ActionCapabilityDiagnostic.textEntryFailed(
                    operation: "post-tap keyboard readiness",
                    stash: stash,
                    safecracker: safecracker,
                    suggestion: "target an editable text field"
                )
            ))
        }
        return .focused(FocusedTextInput(
            subjectEvidence: subjectEvidence,
            resolvedElementId: resolvedElementId,
            resolvedObject: liveTarget.object,
            currentValue: liveTarget.element.value
        ))
    }

    private func waitForActiveTextInput() async -> Bool {
        for _ in 0..<TheSafecracker.keyboardPollMaxAttempts {
            guard await Task.cancellableSleep(for: TheSafecracker.keyboardPollInterval) else { return false }
            if safecracker.hasActiveTextInput() { return true }
        }
        return false
    }

    private static func textInputValue(for target: ElementTarget, in elements: [HeistElement]) -> String? {
        switch target {
        case .predicate(let predicate, let ordinal):
            let matches = ElementMatchSet(elements: elements).matching(predicate).elements
            if let ordinal {
                guard matches.indices.contains(ordinal) else { return nil }
                return matches[ordinal].value
            }
            guard matches.count == 1 else { return nil }
            return matches[0].value
        }
    }

    private static func liveTextInputValue(for object: NSObject?) -> String? {
        switch object {
        case let textField as UITextField:
            return textField.text
        case let textView as UITextView:
            return textView.text
        case let searchBar as UISearchBar:
            return searchBar.text
        case let object?:
            return object.accessibilityValue
        case nil:
            return nil
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
