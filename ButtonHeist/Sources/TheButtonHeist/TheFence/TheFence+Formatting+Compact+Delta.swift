import Foundation

import TheScore

extension FenceResponse {

    static func compactDeltaKind(_ delta: AccessibilityTrace.Delta) -> String {
        switch DeltaProjection(delta: delta, profile: .summary) {
        case .noChange:
            return DeltaProjectionKind.noChange.rawValue
        case .elementsChanged:
            return DeltaProjectionKind.elementsChanged.rawValue
        case .screenChanged:
            return DeltaProjectionKind.screenChanged.rawValue
        }
    }

    static func compactDelta(_ delta: AccessibilityTrace.Delta, method: String) -> String {
        compactDelta(
            DeltaProjection(delta: delta, profile: .summary, includeScreenInterface: true),
            method: method
        )
    }

    static func compactDelta(_ projection: DeltaProjection, actionMethod: ActionMethodProjection) -> String {
        compactDelta(projection, method: actionMethod.rawValue)
    }

    static func compactDelta(_ projection: DeltaProjection, method: String) -> String {
        switch projection {
        case .noChange(let metadata):
            // Auto-settle can produce a no-change delta carrying transients
            // when an element appeared and disappeared during settle but
            // baseline and final are otherwise identical. Surface those.
            if metadata.transient.elements.isEmpty {
                return "\(method): no change"
            }
            var lines: [String] = ["\(method): no net change (\(metadata.elementCount) elements)"]
            for element in metadata.transient.elements {
                lines.append("  +- \(compactElementLine(element))")
            }
            if let omitted = metadata.transient.omittedCount {
                lines.append("  ... transient omitted \(omitted) observed elements")
            }
            return lines.joined(separator: "\n")

        case .elementsChanged(let delta):
            let metadata = delta.metadata
            var lines: [String] = ["\(method): elements changed (\(metadata.elementCount) elements)"]
            lines.append(contentsOf: compactEditLines(delta.edits))
            for element in metadata.transient.elements {
                lines.append("  +- \(compactElementLine(element))")
            }
            if let omitted = metadata.transient.omittedCount {
                lines.append("  ... transient omitted \(omitted) observed elements")
            }
            return lines.joined(separator: "\n")

        case .screenChanged(let delta):
            var lines: [String] = ["\(method): screen changed"]
            if let interface = delta.screen.interface {
                lines.append(compactInterface(interface))
            } else {
                lines.append("\(delta.screen.screenDescription) (\(delta.screen.elementCount) elements)")
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
