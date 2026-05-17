#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// Pure formatter for `activate` failure diagnostics.
///
/// All fields are observation-only — frame, activation point, and screen
/// containment are direct measurements; the receiver block is a UIKit
/// hit-test snapshot and explicitly does not claim to identify a specific
/// AX element. Lines appear only when their underlying observation is
/// meaningful (e.g. `onScreen` is omitted when the element is on-screen),
/// keeping the message compact.
enum ActivateFailureDiagnostic {

    static func build(
        element: AccessibilityElement,
        traitNames: [String],
        activateOutcome: TheStash.ActivateOutcome,
        tapAttempted: Bool,
        tapReceiver: TheSafecracker.TapReceiverDiagnostic?,
        screenBounds: CGRect
    ) -> String {
        var lines = ["activate failed"]

        switch activateOutcome {
        case .success:
            break
        case .objectDeallocated:
            lines.append("- liveObject: deallocated (after refresh+rescroll retry)")
        case .refused:
            lines.append("- accessibilityActivate: returned false (after refresh+rescroll retry)")
        }

        if tapAttempted {
            if let receiver = tapReceiver {
                lines.append(formatReceiverLine(receiver))
                if receiver.interactionDisabledInChain {
                    lines.append("- syntheticTap.userInteractionEnabled: false (in chain)")
                }
                if receiver.hiddenInChain {
                    lines.append("- syntheticTap.hidden: true (in chain)")
                }
                if receiver.isSwiftUIGestureContainer {
                    lines.append("- syntheticTap.note: SwiftUI gesture container; accessibilityActivate is the canonical path")
                }
            } else {
                lines.append("- syntheticTap: no targetable window at activation point")
            }
        }

        let frame = element.shape.frame
        lines.append("- frame: \(formatRect(frame))")
        lines.append("- activationPoint: \(formatPoint(element.activationPoint.cgPoint))")

        if !screenBounds.contains(frame) {
            lines.append("- onScreen: false (screen: \(formatSize(screenBounds.size)))")
        }

        if !traitNames.isEmpty {
            lines.append("- traits: \(traitNames.joined(separator: ","))")
        }

        let tryNext = tryNextLine(
            element: element,
            activateOutcome: activateOutcome,
            tapAttempted: tapAttempted,
            tapReceiver: tapReceiver,
            screenBounds: screenBounds
        )
        lines.append("- tryNext: \(tryNext)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private static func tryNextLine(
        element: AccessibilityElement,
        activateOutcome: TheStash.ActivateOutcome,
        tapAttempted: Bool,
        tapReceiver: TheSafecracker.TapReceiverDiagnostic?,
        screenBounds: CGRect
    ) -> String {
        if !screenBounds.contains(element.shape.frame) {
            return "scroll the element into view, then refetch with get_interface before retrying activate"
        }

        if activateOutcome == .objectDeallocated {
            return "refetch with get_interface and retarget the refreshed element before retrying activate"
        }

        guard tapAttempted else {
            return "retarget an element whose actions include activate, then retry activate"
        }

        guard let tapReceiver else {
            return "wait for a visible app window, then refetch with get_interface before retrying activate"
        }

        if tapReceiver.hiddenInChain {
            return "wait for the target to become visible, then refetch with get_interface before retrying activate"
        }

        if tapReceiver.interactionDisabledInChain {
            return "wait for the target to become enabled, then refetch with get_interface before retrying activate"
        }

        if tapReceiver.isSwiftUIGestureContainer {
            return "retarget the accessible control inside the SwiftUI container before retrying activate"
        }

        return "retarget from a fresh get_interface snapshot before retrying activate"
    }

    private static func formatReceiverLine(_ receiver: TheSafecracker.TapReceiverDiagnostic) -> String {
        var parts = ["- syntheticTap.receiver:", receiver.receiverClass]
        if let label = receiver.receiverAxLabel, !label.isEmpty {
            parts.append("\"\(label)\"")
        } else if let identifier = receiver.receiverAxIdentifier, !identifier.isEmpty {
            parts.append("(id: \(identifier))")
        }
        return parts.joined(separator: " ")
    }

    private static func formatRect(_ rect: CGRect) -> String {
        "\(formatNumber(rect.origin.x)),\(formatNumber(rect.origin.y)),\(formatNumber(rect.size.width)),\(formatNumber(rect.size.height))"
    }

    private static func formatPoint(_ point: CGPoint) -> String {
        "\(formatNumber(point.x)),\(formatNumber(point.y))"
    }

    private static func formatSize(_ size: CGSize) -> String {
        "\(formatNumber(size.width))x\(formatNumber(size.height))"
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
