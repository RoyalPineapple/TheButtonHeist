#if canImport(UIKit)
#if DEBUG
import UIKit
import ButtonHeistSupport

import TheScore
import ThePlans

extension Actions {

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.ActionDispatchOutcome {
        if let failure = await navigation.elementInflation.inflateFirstResponder(method: .editAction) {
            return failure.actionDispatchOutcome(commandMethod: .editAction)
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

    func executeSetPasteboard(_ target: SetPasteboardTarget) async -> TheSafecracker.ActionDispatchOutcome {
        if let failure = await navigation.elementInflation.inflateFirstResponder(method: .setPasteboard) {
            return failure.actionDispatchOutcome(commandMethod: .setPasteboard)
        }
        UIPasteboard.general.string = target.text
        return .success(payload: .setPasteboard(target.text))
    }

    func executeGetPasteboard() -> TheSafecracker.ActionDispatchOutcome {
        let text = UIPasteboard.general.string
        guard let text else {
            return .success(
                method: .getPasteboard,
                message: "Pasteboard is empty or contains non-text data"
            )
        }
        return .success(payload: .getPasteboard(text))
    }

    func executeResignFirstResponder() async -> TheSafecracker.ActionDispatchOutcome {
        if let failure = await navigation.elementInflation.inflateFirstResponder(method: .resignFirstResponder) {
            return failure.actionDispatchOutcome(commandMethod: .resignFirstResponder)
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
        _ request: TypeTextTarget
    ) async -> TheSafecracker.ActionDispatchOutcome {
        guard request.replacingExisting || !request.text.isEmpty else {
            return .failure(.typeText, message: "type_text requires non-empty text")
        }
        let target = request.target
        let focusResult = await focusTextInput(target)
        switch focusResult {
        case .alreadyFocused:
            return await executeTypeText(request, using: nil)
        case .focused(let input):
            return await executeTypeText(request, using: input)
        case .failed(let failure):
            return failure
        }
    }

    private func executeTypeText(
        _ target: TypeTextTarget,
        using focusedInput: FocusedTextInput?
    ) async -> TheSafecracker.ActionDispatchOutcome {
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
        for request: TypeTextTarget,
        resolvedElementId: HeistId?,
        in afterState: PostActionObservation.BeforeState
    ) -> ActionResultPayload? {
        if let resolvedElementId,
           let value = afterState.screen.findElement(heistId: resolvedElementId)?.element.value {
            return .typeText(value)
        }
        guard let target = request.target else { return nil }
        return Self.textInputValue(for: target, in: afterState.interface.projectedElements)
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
        case failed(TheSafecracker.ActionDispatchOutcome)
    }

    private struct FocusedTextInput {
        let subjectEvidence: ActionSubjectEvidence
        let resolvedElementId: HeistId
        let resolvedObject: NSObject
        let currentValue: String?
    }

    private func focusTextInput(
        _ target: AccessibilityTarget?
    ) async -> TextInputFocusResult {
        guard let target else {
            guard safecracker.hasActiveTextInput() else {
                return .failed(.failure(
                    .typeText,
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "initial focus check",
                        stash: stash,
                        safecracker: safecracker,
                        suggestion: "provide target for a text field or focus an editable field before typing"
                    )
                ))
            }
            return .alreadyFocused
        }

        let inflatedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflate(
            for: target,
            method: .typeText,
            deallocatedBoundary: "text input focus"
        ) {
        case .inflated(let target):
            inflatedTarget = target
        case .failed(let failure):
            return .failed(failure.actionDispatchOutcome(commandMethod: .typeText))
        }

        if isResolvedTextInputFocused(inflatedTarget) {
            return .focused(focusedTextInput(from: inflatedTarget))
        }

        return await activateTextInputTarget(inflatedTarget.committedTarget)
    }

    private func activateTextInputTarget(
        _ target: ElementInflation.CommittedElementTarget
    ) async -> TextInputFocusResult {
        let refreshedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflateAfterActivationRefresh(for: target) {
        case .inflated(let target):
            refreshedTarget = target
        case .failed(let failure):
            return .failed(failure.actionDispatchOutcome(commandMethod: .typeText))
        }

        let activateOutcome = accessibilityActions.activate(refreshedTarget.liveTarget)
        if activateOutcome == .success {
            safecracker.showFingerprint(at: refreshedTarget.liveTarget.activationPoint)
        }
        if await textInputIsFocused(refreshedTarget) {
            return .focused(focusedTextInput(from: refreshedTarget))
        }

        let point = refreshedTarget.liveTarget.activationPoint
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

        guard await textInputIsFocused(refreshedTarget) else {
            return .failed(.failure(
                .typeText,
                message: ActionCapabilityDiagnostic.textEntryFailed(
                    operation: "post-activation keyboard readiness",
                    stash: stash,
                    safecracker: safecracker,
                    suggestion: "target an editable text field"
                )
            ))
        }
        return .focused(focusedTextInput(from: refreshedTarget))
    }

    private func isResolvedTextInputFocused(
        _ inflatedTarget: ElementInflation.InflatedElementTarget
    ) -> Bool {
        guard safecracker.hasActiveTextInput() else { return false }
        if stash.firstResponderHeistId == inflatedTarget.treeElement.heistId {
            return true
        }
        if let searchBar = inflatedTarget.liveTarget.object as? UISearchBar {
            return searchBar.searchTextField.isFirstResponder
        }
        return (inflatedTarget.liveTarget.object as? UIResponder)?.isFirstResponder == true
    }

    private func textInputIsFocused(
        _ inflatedTarget: ElementInflation.InflatedElementTarget
    ) async -> Bool {
        if isResolvedTextInputFocused(inflatedTarget) { return true }
        if !safecracker.hasActiveTextInput() {
            guard await safecracker.waitForActiveTextInput() else { return false }
        }
        return !(inflatedTarget.liveTarget.object is UIResponder)
    }

    private func focusedTextInput(
        from inflatedTarget: ElementInflation.InflatedElementTarget
    ) -> FocusedTextInput {
        FocusedTextInput(
            subjectEvidence: inflatedTarget.subjectEvidence(source: .textInputTarget),
            resolvedElementId: inflatedTarget.treeElement.heistId,
            resolvedObject: inflatedTarget.liveTarget.object,
            currentValue: inflatedTarget.liveTarget.element.value
        )
    }

    private static func textInputValue(for target: AccessibilityTarget, in elements: [HeistElement]) -> String? {
        switch target {
        case .predicate(let template, let ordinal):
            guard let predicate = try? template.resolve(in: .empty) else { return nil }
            let matches = ElementMatchGraph(elements: elements).resolve(predicate).elements
            if let ordinal {
                guard matches.indices.contains(ordinal) else { return nil }
                return matches[ordinal].value
            }
            guard matches.count == 1 else { return nil }
            return matches[0].value
        case .container, .ref, .within:
            return nil
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
