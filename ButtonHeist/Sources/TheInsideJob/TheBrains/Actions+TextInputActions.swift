#if canImport(UIKit)
#if DEBUG
import UIKit
import ButtonHeistSupport

import TheScore
import ThePlans

extension Actions {

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(
        _ target: EditActionTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        let inflatedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflateFirstResponder(
            method: .editAction,
        ) {
        case .unavailable:
            return .failure(
                .editAction,
                message: ActionCapabilityDiagnostic.editActionFailed(
                    target.action,
                    vault: vault,
                    safecracker: safecracker
                )
            )
        case .failed(let failure):
            return failure.actionDispatchResult(payload: .editAction)
        case .inflated(let target):
            inflatedTarget = target
        }
        let dispatch = vault.dispatchOnFreshLiveActionTarget(
            inflatedTarget.liveTarget,
        ) { liveTarget in
            safecracker.performEditAction(target.action, on: liveTarget.object)
        }
        let success: Bool
        switch dispatch {
        case .success(let dispatched):
            success = dispatched
        case .failure(let staleness):
            return staleLiveTargetFailure(staleness, payload: .editAction)
        }
        let message = success ? nil : ActionCapabilityDiagnostic.editActionFailed(
            target.action,
            vault: vault,
            safecracker: safecracker
        )
        return success
            ? .success(
                payload: .editAction,
                subjectEvidence: inflatedTarget.subjectEvidence(source: .textInputTarget),
                resolvedElementId: inflatedTarget.treeElement.heistId
            )
            : .failure(.editAction, message: message ?? "edit action failed")
    }

    func executeSetPasteboard(
        _ target: SetPasteboardTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        UIPasteboard.general.string = target.text.rawText
        return .success(payload: .setPasteboard(target.text.rawText))
    }

    func executeGetPasteboard() -> TheSafecracker.ActionDispatchResult {
        let text = UIPasteboard.general.string
        guard let text else {
            return .success(
                payload: .getPasteboard(nil),
                message: "Pasteboard is empty or contains non-text data"
            )
        }
        return .success(payload: .getPasteboard(text))
    }

    func executeResignFirstResponder(
    ) async -> TheSafecracker.ActionDispatchResult {
        let inflatedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflateFirstResponder(
            method: .dismissKeyboard,
        ) {
        case .unavailable:
            return .failure(
                .dismissKeyboard,
                message: ActionCapabilityDiagnostic.resignFirstResponderFailed(
                    vault: vault,
                    safecracker: safecracker
                )
            )
        case .failed(let failure):
            return failure.actionDispatchResult(payload: .dismissKeyboard)
        case .inflated(let target):
            inflatedTarget = target
        }
        let dispatch = vault.dispatchOnFreshLiveActionTarget(
            inflatedTarget.liveTarget,
        ) { liveTarget in
            safecracker.dismissKeyboard(liveTarget.object)
        }
        let success: Bool
        switch dispatch {
        case .success(let dispatched):
            success = dispatched
        case .failure(let staleness):
            return staleLiveTargetFailure(staleness, payload: .dismissKeyboard)
        }
        if success {
            return .success(
                payload: .dismissKeyboard,
                subjectEvidence: inflatedTarget.subjectEvidence(source: .textInputTarget),
                resolvedElementId: inflatedTarget.treeElement.heistId
            )
        }
        return .failure(
            .dismissKeyboard,
            message: ActionCapabilityDiagnostic.resignFirstResponderFailed(
                vault: vault,
                safecracker: safecracker
            )
        )
    }

    // MARK: - Text Entry

    func executeTypeText(
        text: TextInputText,
        target: ResolvedAccessibilityTarget?,
    ) async -> TheSafecracker.ActionDispatchResult {
        let focusResult = await focusTextInput(target)
        switch focusResult {
        case .alreadyFocused:
            return await executeTypeText(text: text, using: nil)
        case .focused(let input):
            return await executeTypeText(text: text, using: input)
        case .failed(let failure):
            return failure
        }
    }

    private func executeTypeText(
        text: TextInputText,
        using focusedInput: FocusedTextInput?
    ) async -> TheSafecracker.ActionDispatchResult {
        if text.mode == .replace {
            let clearResult = await safecracker.clearText(existingValue: focusedInput?.currentValue)
            if let diagnostic = clearResult.diagnostic {
                return .failure(
                    .typeText(nil),
                    message: typeTextInjectionFailureMessage(for: diagnostic, operation: "clearing")
                )
            }
        }

        if !text.rawText.isEmpty {
            let typingResult = await safecracker.typeText(text.rawText)
            if let diagnostic = typingResult.diagnostic {
                return .failure(
                    .typeText(nil),
                    message: typeTextInjectionFailureMessage(for: diagnostic, operation: "typing")
                )
            }
        }

        return .success(
            payload: .typeText(focusedInput.flatMap { currentTextInputValue(from: $0.object) }),
            subjectEvidence: focusedInput?.subjectEvidence,
            resolvedElementId: focusedInput?.resolvedElementId
        )
    }

    private func typeTextInjectionFailureMessage(
        for diagnostic: KeyboardTextInjectionDiagnostic,
        operation: String
    ) -> String {
        guard diagnostic.reason == .noActiveInput else { return diagnostic.message }
        return "\(diagnostic.message); " + ActionCapabilityDiagnostic.textEntryFailed(
            operation: operation,
            vault: vault,
            safecracker: safecracker,
            suggestion: "focus an editable text field before \(operation)"
        )
    }

    private enum TextInputFocusResult {
        case alreadyFocused
        case focused(FocusedTextInput)
        case failed(TheSafecracker.ActionDispatchResult)
    }

    private struct FocusedTextInput {
        let subjectEvidence: ActionSubjectEvidence
        let resolvedElementId: HeistId
        let currentValue: String?
        let object: NSObject
    }

    private func focusTextInput(
        _ target: ResolvedAccessibilityTarget?,
    ) async -> TextInputFocusResult {
        guard let target else {
            guard safecracker.hasActiveTextInput else {
                return .failed(.failure(
                    .typeText(nil),
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "initial focus check",
                        vault: vault,
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
        ) {
        case .inflated(let target):
            inflatedTarget = target
        case .failed(let failure):
            return .failed(failure.actionDispatchResult(payload: .typeText(nil)))
        }

        if let focused = await focusedFirstResponder(
            candidate: inflatedTarget,
            waitForInput: false
        ) {
            return .focused(focused)
        }

        return await activateTextInputTarget(inflatedTarget.committedTarget)
    }

    private func activateTextInputTarget(
        _ target: ElementInflation.CommittedElementTarget,
    ) async -> TextInputFocusResult {
        let refreshedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.refreshCommittedTarget(
            target,
            method: .activate,
        ) {
        case .inflated(let target):
            refreshedTarget = target
        case .failed(let failure):
            return .failed(failure.actionDispatchResult(payload: .typeText(nil)))
        }

        let activateOutcome: AccessibilityActionDispatcher.ActivateOutcome
        let activationPoint: CGPoint
        switch vault.dispatchOnFreshLiveActionTarget(
            refreshedTarget.liveTarget,
            operation: { liveTarget in
                ActivationDispatchEvidence(
                    outcome: accessibilityActions.activate(liveTarget),
                    activationPoint: liveTarget.activationPoint
                )
            }
        ) {
        case .success(let dispatch):
            activateOutcome = dispatch.outcome
            activationPoint = dispatch.activationPoint
        case .failure(let staleness):
            return .failed(staleLiveTargetFailure(staleness, payload: .typeText(nil)))
        }
        if activateOutcome == .success {
            safecracker.showFingerprint(at: activationPoint)
        }
        if let focused = await focusedFirstResponder(
            candidate: refreshedTarget,
            waitForInput: false
        ) {
            return .focused(focused)
        }

        let preparedDispatch: TheSafecracker.PreparedTouchDispatch?
        let point: CGPoint
        switch vault.dispatchOnFreshLiveActionTarget(
            refreshedTarget.liveTarget,
            operation: { liveTarget in
                let point = liveTarget.activationPoint
                return (point, safecracker.prepareTap(at: point))
            }
        ) {
        case .success(let preparation):
            point = preparation.0
            preparedDispatch = preparation.1
        case .failure(let staleness):
            return .failed(staleLiveTargetFailure(staleness, payload: .typeText(nil)))
        }
        guard let preparedDispatch,
              await safecracker.completePreparedTouch(preparedDispatch) else {
            return .failed(.failure(
                .typeText(nil),
                message: ActionCapabilityDiagnostic.gestureDispatchFailed(
                    method: .oneFingerTap,
                    point: point,
                    receiver: safecracker.tapReceiverDiagnostic(at: point)
                )
            ))
        }

        guard let focused = await focusedFirstResponder(
            candidate: refreshedTarget,
            waitForInput: true
        ) else {
            return .failed(.failure(
                .typeText(nil),
                message: ActionCapabilityDiagnostic.textEntryFailed(
                    operation: "post-activation keyboard readiness",
                    vault: vault,
                    safecracker: safecracker,
                    suggestion: "target an editable text field"
                )
            ))
        }
        return .focused(focused)
    }

    private func focusedFirstResponder(
        candidate: ElementInflation.InflatedElementTarget,
        waitForInput: Bool
    ) async -> FocusedTextInput? {
        if !safecracker.hasActiveTextInput {
            guard waitForInput,
                  await safecracker.waitForActiveTextInput() else { return nil }
        }
        let liveFocus = vault.dispatchOnFreshLiveActionTarget(
            candidate.liveTarget,
            operation: { liveTarget -> FocusedTextInput? in
                guard isFirstResponder(liveTarget.object) else { return nil }
                return focusedTextInput(from: candidate, liveTarget: liveTarget)
            }
        )
        if case .success(let focused?) = liveFocus {
            return focused
        }
        let heistId = candidate.treeElement.heistId
        switch await navigation.elementInflation.inflateFirstResponder(method: .typeText) {
        case .inflated(let target) where target.treeElement.heistId == heistId:
            return focusedTextInput(from: target, liveTarget: target.liveTarget)
        case .unavailable, .failed, .inflated:
            return nil
        }
    }

    private func isFirstResponder(_ object: NSObject) -> Bool {
        if let searchBar = object as? UISearchBar {
            return searchBar.searchTextField.isFirstResponder
        }
        return (object as? UIResponder)?.isFirstResponder == true
    }

    private func focusedTextInput(
        from inflatedTarget: ElementInflation.InflatedElementTarget,
        liveTarget: TheVault.LiveActionTarget
    ) -> FocusedTextInput {
        FocusedTextInput(
            subjectEvidence: inflatedTarget.subjectEvidence(source: .textInputTarget),
            resolvedElementId: inflatedTarget.treeElement.heistId,
            currentValue: liveTarget.element.value,
            object: liveTarget.object
        )
    }

    private func currentTextInputValue(from object: NSObject) -> String? {
        if let searchBar = object as? UISearchBar {
            return searchBar.searchTextField.accessibilityValue ?? searchBar.searchTextField.text
        }
        if let textField = object as? UITextField {
            return textField.accessibilityValue ?? textField.text
        }
        if let textView = object as? UITextView {
            return textView.accessibilityValue ?? textView.text
        }
        return object.accessibilityValue
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
