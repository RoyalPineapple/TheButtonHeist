#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.InteractionResult {
        if let failure = await navigation.actionability.makeFirstResponderActionable(method: .editAction) {
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
        if let failure = await navigation.actionability.makeFirstResponderActionable(method: .setPasteboard) {
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
        if let failure = await navigation.actionability.makeFirstResponderActionable(method: .resignFirstResponder) {
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
        guard !target.text.isEmpty else {
            return .failure(.typeText, message: "type_text requires non-empty text")
        }
        let elementTarget = target.elementTarget
        if let failure = await focusTextInput(elementTarget) { return failure }

        let postcondition = TextInputPostcondition(
            target: elementTarget,
            beforeValue: elementTarget.flatMap { stash.resolveTarget($0).resolved?.element.value },
            afterSequence: stash.latestSettledSemanticObservationEvent?.sequence
        )
        let typingResult = await safecracker.typeText(target.text)
        if let diagnostic = typingResult.diagnostic {
            return .failure(.typeText, message: typeTextInjectionFailureMessage(for: diagnostic))
        }

        return .success(method: .typeText, payload: await postcondition.payload(stash: stash))
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
        _ elementTarget: ElementTarget?
    ) async -> TheSafecracker.InteractionResult? {
        guard let elementTarget else {
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
        switch await navigation.actionability.makeActionable(
            for: elementTarget,
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

    private struct TextInputPostcondition {
        private static let timeout: Double = 1.0
        private static let observationStepTimeout: Double = 0.25

        let target: ElementTarget?
        let beforeValue: String?
        let afterSequence: UInt64?

        @MainActor
        func payload(stash: TheStash) async -> ResultPayload? {
            guard let target else { return nil }
            let deadline = CFAbsoluteTimeGetCurrent() + Self.timeout
            var observedSequence = afterSequence
            var lastObservedValue: String?

            while CFAbsoluteTimeGetCurrent() < deadline {
                let remaining = deadline - CFAbsoluteTimeGetCurrent()
                guard remaining > 0 else { break }
                guard let event = await stash.settledSemanticObservationEvent(
                    scope: .visible,
                    after: observedSequence,
                    timeout: min(remaining, Self.observationStepTimeout)
                ) else {
                    continue
                }
                observedSequence = event.sequence
                guard let value = Self.value(for: target, in: event.observation.screen) else {
                    continue
                }
                lastObservedValue = value
                if value != beforeValue {
                    return .value(value)
                }
            }

            return lastObservedValue.map(ResultPayload.value)
        }

        private static func value(for target: ElementTarget, in screen: Screen) -> String? {
            let visibleElements = screen.visibleOnly.orderedElements
            switch target {
            case .predicate(let predicate, let ordinal):
                let matches = visibleElements.filter { predicate.matches($0.element) }
                if let ordinal {
                    guard matches.indices.contains(ordinal) else { return nil }
                    return matches[ordinal].element.value
                }
                guard matches.count == 1 else { return nil }
                return matches[0].element.value
            }
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
