import Foundation

import TheScore

extension FenceResponse {

    func compactHeistCatalog(_ catalog: HeistCatalog) -> String {
        guard !catalog.heists.isEmpty else { return "heists: none" }
        let lines = catalog.heists.flatMap { entry in
            catalogLines(for: entry, indent: "  ")
        }
        return (["heists:"] + lines).joined(separator: "\n")
    }

    func compactHeistDescription(_ description: HeistDescription) -> String {
        var lines = [
            "heist \(description.name) [\(description.role.rawValue)] \(parameterSummary(description)) validation=\(description.validationStatus.rawValue)",
        ]
        if let summary = description.summary, !summary.isEmpty {
            lines.append("summary: \(summary)")
        }
        appendSurfaceLines(description.semanticSurface, to: &lines)
        return lines.joined(separator: "\n")
    }

    func formatHeistCatalogHuman(_ catalog: HeistCatalog) -> String {
        guard !catalog.heists.isEmpty else { return "No heists" }
        var lines = ["Heists:"]
        lines.append(contentsOf: catalog.heists.flatMap { entry in
            catalogLines(for: entry, indent: "  ", paddedRole: true)
        })
        return lines.joined(separator: "\n")
    }

    func formatHeistDescriptionHuman(_ description: HeistDescription) -> String {
        var lines = [
            "Heist: \(description.name)",
            "Role: \(description.role.rawValue)",
            "Parameter: \(parameterSummary(description))",
            "Validation: \(description.validationStatus.rawValue)",
        ]
        if let summary = description.summary, !summary.isEmpty {
            lines.append("Summary: \(summary)")
        }
        appendSurfaceLines(description.semanticSurface, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func parameterSummary(_ entry: HeistCatalogEntry) -> String {
        parameterSummary(
            kind: entry.parameterKind,
            name: entry.parameterName,
            requiresArgument: entry.requiresArgument
        )
    }

    private func catalogLines(
        for entry: HeistCatalogEntry,
        indent: String,
        paddedRole: Bool = false
    ) -> [String] {
        let role = paddedRole
            ? entry.role.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            : entry.role.rawValue
        var firstLine = "\(indent)\(role) \(entry.name) \(parameterSummary(entry))"
        if let summary = entry.summary, !summary.isEmpty {
            firstLine += " summary=\(summary)"
        }
        if !entry.tags.isEmpty {
            firstLine += " tags=\(entry.tags.joined(separator: ","))"
        }
        var lines = [firstLine]
        if let nestedRunHeists = entry.nestedRunHeists, !nestedRunHeists.isEmpty {
            lines.append("\(indent)  nested RunHeist: \(nestedRunHeists.joined(separator: ", "))")
        }
        if let actionCommands = entry.actionCommands, !actionCommands.isEmpty {
            lines.append("\(indent)  actions: \(actionCommands.joined(separator: ", "))")
        }
        if let waitCount = entry.waitCount, let expectationCount = entry.expectationCount {
            lines.append("\(indent)  waits=\(waitCount) expectations=\(expectationCount)")
        }
        if let semanticSurfaces = entry.semanticSurfaces, !semanticSurfaces.isEmpty {
            lines.append("\(indent)  semantic surfaces: \(semanticSurfaces.joined(separator: ", "))")
        }
        if let validationStatus = entry.validationStatus {
            lines.append("\(indent)  validation=\(validationStatus.rawValue)")
        }
        return lines
    }

    private func parameterSummary(_ description: HeistDescription) -> String {
        parameterSummary(
            kind: description.parameterKind,
            name: description.parameterName,
            requiresArgument: description.requiresArgument
        )
    }

    private func parameterSummary(
        kind: HeistParameterKind,
        name: String?,
        requiresArgument: Bool
    ) -> String {
        var text = "parameter=\(kind.rawValue)"
        if let name {
            text += " \(name)"
        }
        text += " requiresArgument=\(requiresArgument)"
        return text
    }

    private func appendSurfaceLines(_ surface: HeistSemanticSurface, to lines: inout [String]) {
        appendLine("actions", values: surface.actionCommands, to: &lines)
        appendLine("targets", values: surface.targetPredicates, to: &lines)
        appendLine("waits", values: surface.waits, to: &lines)
        appendLine("expectations", values: surface.expectations, to: &lines)
        appendLine("nested RunHeist", values: surface.nestedRunHeists, to: &lines)
        appendLine("expectedEffects", values: surface.expectedEffects, to: &lines)
    }

    private func appendLine(_ label: String, values: [String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append("\(label): \(values.joined(separator: ", "))")
    }
}
