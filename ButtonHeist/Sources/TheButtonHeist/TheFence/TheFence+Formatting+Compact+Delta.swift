import Foundation

import TheScore

extension FenceResponse {

    static func compactDeltaKind(_ delta: AccessibilityTrace.Delta) -> String {
        DeltaProjection(delta: delta, profile: .summary).kind.rawValue
    }

    static func compactDelta(_ delta: AccessibilityTrace.Delta, method: String) -> String {
        compactDelta(
            DeltaProjection(delta: delta, profile: .summary, includeScreenInterface: true),
            method: method
        )
    }

    static func compactDelta(_ projection: DeltaProjection, method: String) -> String {
        switch projection.kind {
        case .noChange:
            // Auto-settle can produce a no-change delta carrying transients
            // when an element appeared and disappeared during settle but
            // baseline and final are otherwise identical. Surface those.
            if projection.transient.elements.isEmpty {
                return "\(method): no change"
            }
            var lines: [String] = ["\(method): no net change (\(projection.elementCount) elements)"]
            for element in projection.transient.elements {
                lines.append("  +- \(compactElementLine(element))")
            }
            if let omitted = projection.transient.omittedCount {
                lines.append("  ... transient omitted \(omitted) observed elements")
            }
            return lines.joined(separator: "\n")

        case .elementsChanged:
            var lines: [String] = ["\(method): elements changed (\(projection.elementCount) elements)"]
            if let edits = projection.edits {
                lines.append(contentsOf: compactEditLines(edits))
            }
            for element in projection.transient.elements {
                lines.append("  +- \(compactElementLine(element))")
            }
            if let omitted = projection.transient.omittedCount {
                lines.append("  ... transient omitted \(omitted) observed elements")
            }
            return lines.joined(separator: "\n")

        case .screenChanged:
            var lines: [String] = ["\(method): screen changed"]
            if let interface = projection.screen?.interface {
                lines.append(compactInterface(interface))
            } else if let screen = projection.screen {
                lines.append("\(screen.screenDescription) (\(screen.elementCount) elements)")
            }
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
                lines.append(compactChangeLine(name: name, change: change))
            }
        }
        return lines
    }

    private static func compactEditLines(_ edits: DeltaEditsProjection) -> [String] {
        var lines: [String] = []
        for element in edits.added.elements {
            lines.append("  + \(compactElementLine(element))")
        }
        if let omitted = edits.added.omittedCount {
            lines.append("  ... added omitted \(omitted) observed elements")
        }
        for element in edits.removed.elements {
            lines.append("  - \(compactElementLine(element))")
        }
        if let omitted = edits.removed.omittedCount {
            lines.append("  ... removed omitted \(omitted) observed elements")
        }
        for update in edits.updated.updates {
            let name = nonEmptyDescription(update.after)
            for change in update.changes {
                lines.append(compactChangeLine(name: name, change: change))
            }
        }
        if let omitted = edits.updated.omittedCount {
            lines.append("  ... updated omitted \(omitted) observed elements")
        }
        return lines
    }

    private static func compactChangeLine(name: String, change: PropertyChange) -> String {
        "  ~ \(name): \(change.property.rawValue) \"\(display(change.oldValue))\" → \"\(display(change.newValue))\""
    }

    private static func display(_ value: ElementPropertyValue?) -> String {
        value?.displayText ?? "nil"
    }

    private static func nonEmptyDescription(_ element: HeistElement) -> String {
        if let label = element.label, !label.isEmpty { return label }
        if let value = element.value, !value.isEmpty { return value }
        if let identifier = element.identifier, !identifier.isEmpty { return identifier }
        return element.description
    }

}
