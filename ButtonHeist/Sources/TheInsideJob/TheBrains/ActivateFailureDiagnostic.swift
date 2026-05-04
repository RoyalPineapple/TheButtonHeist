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
        lines.append("- activationPoint: \(formatPoint(element.activationPoint))")

        if !screenBounds.contains(frame) {
            lines.append("- onScreen: false (screen: \(formatSize(screenBounds.size)))")
        }

        if !traitNames.isEmpty {
            lines.append("- traits: \(traitNames.joined(separator: ","))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

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
