import Foundation

import TheScore

extension FenceResponse {

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
        for id in edits.removed {
            lines.append("  - \(id)")
        }
        // Omit geometry changes (frame/activationPoint) — layout shifts are structural noise.
        for update in edits.updated {
            for change in update.changes where !change.property.isGeometry {
                lines.append("  ~ \(update.heistId): \(change.property.rawValue) \"\(change.old ?? "nil")\" → \"\(change.new ?? "nil")\"")
            }
        }
        let structuralCount = edits.treeInserted.count + edits.treeRemoved.count + edits.treeMoved.count
        if structuralCount > 0 {
            var parts: [String] = []
            if !edits.treeInserted.isEmpty { parts.append("+\(edits.treeInserted.count)") }
            if !edits.treeRemoved.isEmpty { parts.append("-\(edits.treeRemoved.count)") }
            if !edits.treeMoved.isEmpty { parts.append("moved \(edits.treeMoved.count)") }
            lines.append("  hierarchy changed (\(parts.joined(separator: ", ")))")
        }
        return lines
    }

}
