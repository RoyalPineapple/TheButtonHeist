#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

@MainActor enum ActionCapabilityDiagnostic {

    // MARK: - Element Actions

    static func nonAdjustableAction(
        _ method: ActionMethod,
        element: InterfaceTree.Element
    ) -> String {
        "\(adjustableBoundary(method)) failed: observed \(elementObservation(element)); "
            + "try target an element with trait adjustable before calling \(method.rawValue)."
    }

    static func unsupportedElementAction(
        _ method: ActionMethod,
        element: InterfaceTree.Element
    ) -> String {
        "\(method.rawValue) failed: observed \(elementObservation(element)); "
            + "try retarget an element whose actions include \(method.rawValue)."
    }

    static func missingCustomAction(
        _ requestedAction: CustomActionName,
        element: InterfaceTree.Element
    ) -> String {
        let customActions = availableCustomActions(for: element)
        let suggestion = customActions.isEmpty
            ? "target an element exposing custom actions"
            : "use one of custom actions \(stringProfile.renderList(customActions.map(\.description), itemStyle: .quoted))"
        return "custom action failed: observed requestedAction=\(stringProfile.renderString(requestedAction.description)) on \(elementObservation(element)); "
            + "try \(suggestion)."
    }

    static func declinedCustomAction(
        _ requestedAction: CustomActionName,
        element: InterfaceTree.Element
    ) -> String {
        let alternatives = availableCustomActions(for: element).filter { $0 != requestedAction }
        let suggestion = alternatives.isEmpty
            ? "wait for the handler state to permit the requested action"
            : "use another custom action \(stringProfile.renderList(alternatives.map(\.description), itemStyle: .quoted))"
        return "custom action failed: observed requestedAction=\(stringProfile.renderString(requestedAction.description)) declined by handler on "
            + "\(elementObservation(element)); try \(suggestion)."
    }

    // MARK: - Text / Edit Actions

    static func textEntryFailed(
        operation: String,
        vault: TheVault,
        safecracker: TheSafecracker,
        suggestion: String
    ) -> String {
        "text entry failed: observed \(formatFocusState(vault: vault, safecracker: safecracker)) "
            + "during \(operation); try \(suggestion)."
    }

    static func editActionFailed(
        _ action: EditAction,
        vault: TheVault,
        safecracker: TheSafecracker
    ) -> String {
        "edit action failed: observed action=\(stringProfile.renderString(action.rawValue)) "
            + "\(formatFocusState(vault: vault, safecracker: safecracker)); "
            + "try focus editable text before \(action.rawValue)."
    }

    static func resignFirstResponderFailed(
        vault: TheVault,
        safecracker: TheSafecracker
    ) -> String {
        "resign first responder failed: observed \(formatFocusState(vault: vault, safecracker: safecracker)); "
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
        element: InterfaceTree.Element,
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
        _ treeElement: InterfaceTree.Element,
        liveObject: NSObject? = nil,
        includeLiveState: Bool = false,
        missingLiveObjectState: String = "notInflated"
    ) -> String {
        let element = treeElement.element
        let summary = ElementDiagnosticSummary(
            label: element.label,
            identifier: element.identifier,
            value: element.value,
            traits: element.traits.heistTraits,
            actions: availableActions(for: treeElement, liveObject: liveObject),
            liveObjectState: liveObject == nil ? missingLiveObjectState : nil
        )
        return summary.rendered(using: .actionCapability(includeLiveState: includeLiveState))
    }

    private static func formatFocusState(
        vault: TheVault,
        safecracker: TheSafecracker
    ) -> String {
        let focus = formatFirstResponder(vault: vault)
        let keyboardVisible = safecracker.isKeyboardVisible
        let activeTextInput = safecracker.hasActiveTextInput
        return "focus=\(focus) keyboardVisible=\(keyboardVisible) activeTextInput=\(activeTextInput)"
    }

    private static func formatFirstResponder(vault: TheVault) -> String {
        guard let heistId = vault.firstResponderHeistId else { return "none" }
        guard let element = vault.firstResponderInterfaceElement() else {
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
        for treeElement: InterfaceTree.Element,
        liveObject: NSObject? = nil
    ) -> [ElementAction] {
        let element = treeElement.element
        var actions = element.projectedActionSet.actions
        if TheVault.Interactivity.isInteractive(element: element, object: liveObject) {
            actions.insert(.activate)
        }
        let liveNames = liveObject?.accessibilityCustomActions?
            .compactMap { try? CustomActionName(validating: $0.name) } ?? []
        actions.formUnion(liveNames.map(ElementAction.custom))
        return ElementActionSet(actions).orderedActions
    }

    private static func availableCustomActions(
        for treeElement: InterfaceTree.Element,
        liveObject: NSObject? = nil
    ) -> [CustomActionName] {
        var names = treeElement.element.projectedActionSet.orderedActions.compactMap { action -> CustomActionName? in
            guard case .custom(let name) = action else { return nil }
            return name
        }
        let liveNames = liveObject?.accessibilityCustomActions?
            .compactMap { try? CustomActionName(validating: $0.name) } ?? []
        names += liveNames.uniqued(on: \.self, excluding: Set(names))
        return names
    }

    static func availableRotors(
        for treeElement: InterfaceTree.Element,
        liveObject: NSObject? = nil
    ) -> [RotorName] {
        var names = treeElement.element.customRotors.compactMap { try? RotorName(validating: $0.name) }
        let liveNames = liveObject?.accessibilityCustomRotors?
            .compactMap { $0.bhInvocableName(locale: liveObject?.accessibilityLanguage) }
            ?? []
        names += liveNames.uniqued(on: \.self, excluding: Set(names))
        return names
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
