import Foundation

import TheScore

extension FenceResponse {

    static func compactDeltaKind(_ delta: AccessibilityTrace.Delta) -> String {
        switch delta {
        case .noChange:
            return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged:
            return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged:
            return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
    }

    static func compactDelta(_ delta: AccessibilityTrace.Delta, method: String) -> String {
        switch delta {
        case .noChange(let payload):
            // Auto-settle can produce a no-change delta carrying transients
            // when an element appeared and disappeared during settle but
            // baseline and final are otherwise identical. Surface those.
            if payload.transient.isEmpty {
                return "\(method): no change"
            }
            var lines: [String] = ["\(method): no net change (\(payload.elementCount) elements)"]
            for element in payload.transient {
                lines.append("  +- \(compactElementLine(element))")
            }
            return lines.joined(separator: "\n")

        case .elementsChanged(let payload):
            var lines: [String] = ["\(method): elements changed (\(payload.elementCount) elements)"]
            lines.append(contentsOf: compactEditLines(payload.edits))
            for element in payload.transient {
                lines.append("  +- \(compactElementLine(element))")
            }
            return lines.joined(separator: "\n")

        case .screenChanged(let payload):
            var lines: [String] = ["\(method): screen changed"]
            lines.append(compactInterface(payload.newInterface))
            return lines.joined(separator: "\n")
        }
    }

    private static func compactEditLines(_ edits: ElementEdits) -> [String] {
        var lines: [String] = []
        for element in edits.added {
            lines.append("  + \(compactElementLine(element))")
        }
        for element in edits.removed {
            lines.append("  - \(compactElementLine(element))")
        }
        // Omit geometry changes (frame/activationPoint) — layout shifts are structural noise.
        for update in edits.updated {
            let name = nonEmptyDescription(update.after)
            for change in update.changes where !change.property.isGeometry {
                lines.append("  ~ \(name): \(change.property.rawValue) \"\(change.old ?? "nil")\" → \"\(change.new ?? "nil")\"")
            }
        }
        return lines
    }

    private static func nonEmptyDescription(_ element: HeistElement) -> String {
        if let label = element.label, !label.isEmpty { return label }
        if let value = element.value, !value.isEmpty { return value }
        if let identifier = element.identifier, !identifier.isEmpty { return identifier }
        return element.description
    }

}
