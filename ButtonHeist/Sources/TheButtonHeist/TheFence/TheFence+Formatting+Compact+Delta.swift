import Foundation

import TheScore

extension FenceResponse {

    static func compactDelta(_ projection: DeltaProjection, method: String) -> String {
        compactDeltaRendering(projection).lines(method: method).joined(separator: "\n")
    }

    static func compactDeltaRendering(_ projection: DeltaProjection) -> CompactDeltaRendering {
        switch projection {
        case .noChange:
            return CompactDeltaRendering(summary: "no change")

        case .elementsChanged(let delta):
            let metadata = delta.metadata
            return CompactDeltaRendering(
                summary: "elements changed (\(metadata.elementCount) elements)",
                detailLines: compactEditLines(delta.edits)
            )

        case .screenChanged(let delta):
            var lines: [String] = []
            if let interface = delta.screen.interface {
                lines.append(compactInterface(interface))
            } else {
                lines.append("\(delta.screen.screenDescription) (\(delta.screen.elementCount) elements)")
            }
            return CompactDeltaRendering(summary: "screen changed", detailLines: lines)
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
        let assertable = element.semantics.assertable
        if let label = assertable.label, !label.isEmpty { return label }
        if let value = assertable.value, !value.isEmpty { return value }
        if let identifier = assertable.identifier, !identifier.isEmpty { return identifier }
        return element.semantics.spokenDescription
    }

}

extension FenceResponse {
    struct CompactDeltaRendering: Sendable, Equatable {
        let summary: String
        let detailLines: [String]

        init(summary: String, detailLines: [String] = []) {
            self.summary = summary
            self.detailLines = detailLines
        }

        func lines(method: String) -> [String] {
            ["\(method): \(summary)"] + detailLines
        }
    }
}
