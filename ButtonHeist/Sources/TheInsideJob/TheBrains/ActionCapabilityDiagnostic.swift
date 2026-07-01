#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

@MainActor enum ActionCapabilityDiagnostic { // swiftlint:disable:this agent_main_actor_value_type

    // MARK: - Element Actions

    static func nonAdjustableAction(
        _ method: ActionMethod,
        element: TheStash.ScreenElement
    ) -> String {
        "\(adjustableBoundary(method)) failed: observed \(elementObservation(element)); "
            + "try target an element with trait adjustable before calling \(method.rawValue)."
    }

    static func elementDeallocated(
        boundary: String,
        element: TheStash.ScreenElement,
        isInflated: Bool
    ) -> String {
        let observed = elementObservation(
            element,
            includeLiveState: true,
            missingLiveObjectState: isInflated ? "deallocated" : "notInflated"
        )
        return "\(boundary) failed: observed \(observed); live target became stale during element inflation."
    }

    static func unsupportedElementAction(
        _ method: ActionMethod,
        element: TheStash.ScreenElement
    ) -> String {
        "\(method.rawValue) failed: observed \(elementObservation(element)); "
            + "try retarget an element whose actions include \(method.rawValue)."
    }

    static func missingCustomAction(
        _ requestedAction: String,
        element: TheStash.ScreenElement
    ) -> String {
        let customActions = availableCustomActions(for: element)
        let suggestion = customActions.isEmpty
            ? "target an element exposing custom actions"
            : "use one of custom actions \(stringProfile.renderList(customActions, itemStyle: .quoted))"
        return "custom action failed: observed requestedAction=\(stringProfile.renderString(requestedAction)) on \(elementObservation(element)); "
            + "try \(suggestion)."
    }

    static func declinedCustomAction(
        _ requestedAction: String,
        element: TheStash.ScreenElement
    ) -> String {
        let alternatives = availableCustomActions(for: element).filter { $0 != requestedAction }
        let suggestion = alternatives.isEmpty
            ? "wait for the handler state to permit the requested action"
            : "use another custom action \(stringProfile.renderList(alternatives, itemStyle: .quoted))"
        return "custom action failed: observed requestedAction=\(stringProfile.renderString(requestedAction)) declined by handler on "
            + "\(elementObservation(element)); try \(suggestion)."
    }

    // MARK: - Text / Edit Actions

    static func textEntryFailed(
        operation: String,
        stash: TheStash,
        safecracker: TheSafecracker,
        suggestion: String
    ) -> String {
        "text entry failed: observed \(formatFocusState(stash: stash, safecracker: safecracker)) "
            + "during \(operation); try \(suggestion)."
    }

    static func editActionFailed(
        _ action: EditAction,
        stash: TheStash,
        safecracker: TheSafecracker
    ) -> String {
        "edit action failed: observed action=\(stringProfile.renderString(action.rawValue)) "
            + "\(formatFocusState(stash: stash, safecracker: safecracker)); "
            + "try focus editable text before \(action.rawValue)."
    }

    static func resignFirstResponderFailed(
        stash: TheStash,
        safecracker: TheSafecracker
    ) -> String {
        "resign first responder failed: observed \(formatFocusState(stash: stash, safecracker: safecracker)); "
            + "try focus a text input before dismissing the keyboard."
    }

    // MARK: - Gesture Dispatch

    static func gestureDispatchFailed(
        method: ActionMethod,
        point: CGPoint,
        receiver: TheSafecracker.TapReceiverDiagnostic?
    ) -> String {
        "gesture dispatch failed: observed method=\(method.rawValue) phase=dispatch "
            + "\(formatPointObservation(point: point, receiver: receiver)); "
            + "try target a semantic element that can be made actionable, or choose a point inside an app window."
    }

    static func gestureTargetUnavailable(
        method: ActionMethod,
        element: TheStash.ScreenElement,
        isVisible: Bool
    ) -> String {
        "gesture target unavailable: observed method=\(method.rawValue) phase=targeting "
            + "\(elementObservation(element)) visible=\(isVisible); "
            + "element-derived gesture points require fresh live geometry from element inflation."
    }

    // MARK: - Private Helpers

    private static let stringProfile = ElementDiagnosticSummary.RenderProfile.actionCapability

    private static func adjustableBoundary(_ method: ActionMethod) -> String {
        switch method {
        case .increment, .decrement:
            return "adjustable action"
        default:
            return method.rawValue
        }
    }

    static func elementObservation(
        _ screenElement: TheStash.ScreenElement,
        liveObject: NSObject? = nil,
        includeLiveState: Bool = false,
        missingLiveObjectState: String = "notInflated"
    ) -> String {
        let element = screenElement.element
        let summary = ElementDiagnosticSummary(
            label: element.label,
            identifier: element.identifier,
            value: element.value,
            traits: element.traits.heistTraits,
            actions: availableActions(for: screenElement, liveObject: liveObject),
            liveObjectState: liveObject == nil ? missingLiveObjectState : nil
        )
        return summary.rendered(using: .actionCapability(includeLiveState: includeLiveState))
    }

    private static func formatFocusState(
        stash: TheStash,
        safecracker: TheSafecracker
    ) -> String {
        let focus = formatFirstResponder(stash: stash)
        let keyboardVisible = safecracker.isKeyboardVisible()
        let activeTextInput = safecracker.hasActiveTextInput()
        return "focus=\(focus) keyboardVisible=\(keyboardVisible) activeTextInput=\(activeTextInput)"
    }

    private static func formatFirstResponder(stash: TheStash) -> String {
        guard let heistId = stash.firstResponderHeistId else { return "none" }
        guard let element = stash.firstResponderScreenElement() else {
            return "focused element \(stringProfile.renderString(heistId.description)) liveObject=unknown"
        }
        return elementObservation(element)
    }

    private static func formatPointObservation(
        point: CGPoint,
        receiver: TheSafecracker.TapReceiverDiagnostic?
    ) -> String {
        let pointDescription = "point=(\(formatNumber(point.x)),\(formatNumber(point.y)))"
        guard let receiver else { return "\(pointDescription) window=none" }
        var parts = [
            pointDescription,
            "windowLevel=\(formatNumber(receiver.windowLevel))",
            "receiver=\(receiver.receiverClass)",
        ]
        if let label = receiver.receiverAxLabel, !label.isEmpty {
            parts.append("receiverLabel=\(stringProfile.renderString(label))")
        } else if let identifier = receiver.receiverAxIdentifier, !identifier.isEmpty {
            parts.append("receiverIdentifier=\(stringProfile.renderString(identifier))")
        }
        if receiver.interactionDisabledInChain {
            parts.append("userInteractionEnabled=false")
        }
        if receiver.hiddenInChain {
            parts.append("hidden=true")
        }
        if receiver.isSwiftUIGestureContainer {
            parts.append("swiftUIGestureContainer=true")
        }
        return parts.joined(separator: " ")
    }

    private static func availableActions(
        for screenElement: TheStash.ScreenElement,
        liveObject: NSObject? = nil
    ) -> [ElementAction] {
        var actions: [ElementAction] = []
        let element = screenElement.element
        let isInteractive = TheStash.Interactivity.isInteractive(element: element, object: liveObject)
        if isInteractive {
            actions.append(.activate)
        }
        if isInteractive, element.traits.contains(.adjustable) {
            actions.append(.increment)
            actions.append(.decrement)
        }
        appendUniqueActions(
            element.customActions.map { $0.name }.filter { !$0.isEmpty }.map(ElementAction.custom),
            to: &actions
        )
        let liveNames = liveObject?.accessibilityCustomActions?
            .map { $0.name }
            .filter { !$0.isEmpty } ?? []
        appendUniqueActions(liveNames.map(ElementAction.custom), to: &actions)
        return actions
    }

    private static func availableCustomActions(
        for screenElement: TheStash.ScreenElement,
        liveObject: NSObject? = nil
    ) -> [String] {
        var names = screenElement.element.customActions.map { $0.name }.filter { !$0.isEmpty }
        let liveNames = liveObject?.accessibilityCustomActions?
            .map { $0.name }
            .filter { !$0.isEmpty } ?? []
        appendUnique(liveNames, to: &names)
        return names
    }

    static func availableRotors(
        for screenElement: TheStash.ScreenElement,
        liveObject: NSObject? = nil
    ) -> [String] {
        var names = screenElement.element.customRotors.map { $0.name }.filter { !$0.isEmpty }
        let liveNames = liveObject?.accessibilityCustomRotors?
            .map { $0.bhInvocableName(locale: liveObject?.accessibilityLanguage) }
            .filter { !$0.isEmpty } ?? []
        appendUnique(liveNames, to: &names)
        return names
    }

    private static func appendUnique(_ additions: [String], to names: inout [String]) {
        for name in additions where !names.contains(name) {
            names.append(name)
        }
    }

    private static func appendUniqueActions(_ additions: [ElementAction], to actions: inout [ElementAction]) {
        for action in additions where !actions.contains(where: { $0.description == action.description }) {
            actions.append(action)
        }
    }

    private static func formatNumber(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", Double(rounded))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
