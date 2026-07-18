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
    ) async -> TheSafecracker.ActionDispatchOutcome {
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
            return failure.actionDispatchOutcome(commandMethod: .editAction)
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
            return staleLiveTargetFailure(staleness, method: .editAction)
        }
        let message = success ? nil : ActionCapabilityDiagnostic.editActionFailed(
            target.action,
            vault: vault,
            safecracker: safecracker
        )
        return success
            ? .success(
                method: .editAction,
                subjectEvidence: inflatedTarget.subjectEvidence(source: .textInputTarget),
                resolvedElementId: inflatedTarget.treeElement.heistId
            )
            : .failure(.editAction, message: message ?? "edit action failed")
    }

    func executeSetPasteboard(
        _ target: SetPasteboardTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        UIPasteboard.general.string = target.text.rawText
        return .success(payload: .setPasteboard(target.text.rawText))
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

    func executeResignFirstResponder(
    ) async -> TheSafecracker.ActionDispatchOutcome {
        let inflatedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflateFirstResponder(
            method: .resignFirstResponder,
        ) {
        case .unavailable:
            return .failure(
                .resignFirstResponder,
                message: ActionCapabilityDiagnostic.resignFirstResponderFailed(
                    vault: vault,
                    safecracker: safecracker
                )
            )
        case .failed(let failure):
            return failure.actionDispatchOutcome(commandMethod: .resignFirstResponder)
        case .inflated(let target):
            inflatedTarget = target
        }
        let dispatch = vault.dispatchOnFreshLiveActionTarget(
            inflatedTarget.liveTarget,
        ) { liveTarget in
            safecracker.resignFirstResponder(liveTarget.object)
        }
        let success: Bool
        switch dispatch {
        case .success(let dispatched):
            success = dispatched
        case .failure(let staleness):
            return staleLiveTargetFailure(staleness, method: .resignFirstResponder)
        }
        if success {
            return .success(
                method: .resignFirstResponder,
                subjectEvidence: inflatedTarget.subjectEvidence(source: .textInputTarget),
                resolvedElementId: inflatedTarget.treeElement.heistId
            )
        }
        return .failure(
            .resignFirstResponder,
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
    ) async -> TheSafecracker.ActionDispatchOutcome {
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
    ) async -> TheSafecracker.ActionDispatchOutcome {
        if text.mode == .replace {
            let clearResult = await safecracker.clearText(existingValue: focusedInput?.currentValue)
            if let diagnostic = clearResult.diagnostic {
                return .failure(.typeText, message: typeTextInjectionFailureMessage(for: diagnostic, operation: "clearing"))
            }
        }

        if !text.rawText.isEmpty {
            let typingResult = await safecracker.typeText(text.rawText)
            if let diagnostic = typingResult.diagnostic {
                return .failure(.typeText, message: typeTextInjectionFailureMessage(for: diagnostic, operation: "typing"))
            }
        }

        return .success(
            method: .typeText,
            subjectEvidence: focusedInput?.subjectEvidence,
            resolvedElementId: focusedInput?.resolvedElementId
        )
    }

    func typeTextPayload(
        resolvedElementId: HeistId,
        in baseline: PostActionObservation.ObservationBaseline
    ) -> ActionResultPayload? {
        guard let element = baseline.observation.tree.findElement(heistId: resolvedElementId),
              let value = element.element.value else { return nil }
        return .typeText(value)
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
        case failed(TheSafecracker.ActionDispatchOutcome)
    }

    private struct FocusedTextInput {
        let subjectEvidence: ActionSubjectEvidence
        let resolvedElementId: HeistId
        let currentValue: String?
    }

    private func focusTextInput(
        _ target: ResolvedAccessibilityTarget?,
    ) async -> TextInputFocusResult {
        guard let target else {
            guard safecracker.hasActiveTextInput() else {
                return .failed(.failure(
                    .typeText,
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
            return .failed(failure.actionDispatchOutcome(commandMethod: .typeText))
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
            return .failed(failure.actionDispatchOutcome(commandMethod: .typeText))
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
            return .failed(staleLiveTargetFailure(staleness, method: .typeText))
        }
        if activateOutcome == .success {
            safecracker.showFingerprint(at: activationPoint)
        }
        if let focused = await focusedFirstResponder(
            candidate: refreshedTarget,
            waitForInput: true
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
            return .failed(staleLiveTargetFailure(staleness, method: .typeText))
        }
        guard let preparedDispatch,
              await safecracker.completePreparedTouch(preparedDispatch) else {
            return .failed(.failure(
                .typeText,
                message: ActionCapabilityDiagnostic.gestureDispatchFailed(
                    method: .syntheticTap,
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
                .typeText,
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
        if !safecracker.hasActiveTextInput() {
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
            currentValue: liveTarget.element.value
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
