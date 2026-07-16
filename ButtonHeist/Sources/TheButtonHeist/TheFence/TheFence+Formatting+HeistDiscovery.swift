import Foundation
import ThePlans

import TheScore

extension FenceResponse {

    func compactHeistCatalog(_ catalog: HeistDiscoveryCatalog) -> String {
        guard !catalog.heists.isEmpty else { return "heists: none" }
        let lines = catalog.heists.flatMap { entry in
            catalogLines(for: entry, indent: "  ")
        }
        return (["heists:"] + lines).joined(separator: "\n")
    }

    func compactHeistDescription(_ description: HeistDescription) -> String {
        var lines = [
            "heist \(description.identity.displayName) [\(description.role.rawValue)] "
                + "\(parameterSummary(description)) validation=\(description.validationStatus.rawValue)",
        ]
        if let summary = description.summary, !summary.isEmpty {
            lines.append("summary: \(summary)")
        }
        appendSurfaceLines(description.semanticSurface, to: &lines)
        return lines.joined(separator: "\n")
    }

    func formatHeistCatalogHuman(_ catalog: HeistDiscoveryCatalog) -> String {
        guard !catalog.heists.isEmpty else { return "No heists" }
        var lines = ["Heists:"]
        lines.append(contentsOf: catalog.heists.flatMap { entry in
            catalogLines(for: entry, indent: "  ", paddedRole: true)
        })
        return lines.joined(separator: "\n")
    }

    func formatHeistDescriptionHuman(_ description: HeistDescription) -> String {
        var lines = [
            "Heist: \(description.identity.displayName)",
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
            name: entry.parameterName?.rawValue,
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
        var firstLine = "\(indent)\(role) \(entry.identity.displayName) \(parameterSummary(entry))"
        if let summary = entry.summary, !summary.isEmpty {
            firstLine += " summary=\(summary)"
        }
        if !entry.tags.isEmpty {
            firstLine += " tags=\(entry.tags.map(\.heistDiscoveryDisplayValue).joined(separator: ","))"
        }
        var lines = [firstLine]
        if let nestedRunHeists = entry.nestedRunHeists, !nestedRunHeists.isEmpty {
            lines.append("\(indent)  nested RunHeist: \(nestedRunHeists.map(\.heistDiscoveryDisplayValue).joined(separator: ", "))")
        }
        if let actionCommands = entry.actionCommands, !actionCommands.isEmpty {
            lines.append("\(indent)  actions: \(actionCommands.map(\.heistDiscoveryDisplayValue).joined(separator: ", "))")
        }
        if let waitCount = entry.waitCount, let expectationCount = entry.expectationCount {
            lines.append("\(indent)  waits=\(waitCount) expectations=\(expectationCount)")
        }
        if let semanticSurfaces = entry.semanticSurfaces, !semanticSurfaces.isEmpty {
            lines.append("\(indent)  semantic surfaces: \(semanticSurfaces.map(\.heistDiscoveryDisplayValue).joined(separator: ", "))")
        }
        if let validationStatus = entry.validationStatus {
            lines.append("\(indent)  validation=\(validationStatus.rawValue)")
        }
        return lines
    }

    private func parameterSummary(_ description: HeistDescription) -> String {
        parameterSummary(
            kind: description.parameterKind,
            name: description.parameterName?.rawValue,
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
        appendLine("actions", values: surface.actionCommands.map(\.heistDiscoveryDisplayValue), to: &lines)
        appendLine("targets", values: surface.targetPredicates.map(\.heistDiscoveryDisplayValue), to: &lines)
        appendLine("waits", values: surface.waits.map(\.heistDiscoveryDisplayValue), to: &lines)
        appendLine("expectations", values: surface.expectations.map(\.heistDiscoveryDisplayValue), to: &lines)
        appendLine("nested RunHeist", values: surface.nestedRunHeists.map(\.heistDiscoveryDisplayValue), to: &lines)
        appendLine("expectedEffects", values: surface.expectedEffects.map(\.heistDiscoveryDisplayValue), to: &lines)
    }

    private func appendLine(_ label: String, values: [String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append("\(label): \(values.joined(separator: ", "))")
    }
}

extension HeistCatalogTag {
    var heistDiscoveryDisplayValue: String {
        rawValue
    }
}

extension HeistInvocationPath {
    var heistDiscoveryDisplayValue: String {
        description
    }
}

extension HeistActionCommandType {
    var heistDiscoveryDisplayValue: String {
        rawValue
    }
}

extension AccessibilityPredicate {
    var heistDiscoveryDisplayValue: String {
        description
    }
}

extension HeistTargetPredicateFact {
    var heistDiscoveryDisplayValue: String {
        switch self {
        case .predicate(let predicate):
            return predicate.description
        case .container(let predicate):
            return predicate.description
        case .targetReference(let reference):
            return "ref(\(reference.rawValue))"
        }
    }
}

extension HeistSemanticSurfaceFact {
    var heistDiscoveryDisplayValue: String {
        switch self {
        case .label(let match):
            return "label=\(match.heistDiscoveryDisplayValue)"
        case .identifier(let match):
            return "identifier=\(match.heistDiscoveryDisplayValue)"
        case .value(let match):
            return "value=\(match.heistDiscoveryDisplayValue)"
        case .hint(let match):
            return "hint=\(match.heistDiscoveryDisplayValue)"
        case .traits(let traits):
            return "traits=\(traits.map(\.rawValue).joined(separator: "|"))"
        case .actions(let actions):
            return "actions=\(actions.map(\.heistDiscoveryDisplayValue).joined(separator: "|"))"
        case .customContent(let match):
            return "customContent=\(match.heistDiscoveryDisplayValue)"
        case .rotors(let matches):
            return "rotors=\(matches.map(\.heistDiscoveryDisplayValue).joined(separator: "|"))"
        case .exclude(let fact):
            return "exclude(\(fact.heistDiscoveryDisplayValue))"
        }
    }
}

extension HeistSemanticCustomContentMatch {
    var heistDiscoveryDisplayValue: String {
        [
            label.map { "label=\($0.heistDiscoveryDisplayValue)" },
            value.map { "value=\($0.heistDiscoveryDisplayValue)" },
            isImportant.map { "isImportant=\($0)" },
        ].compactMap { $0 }.joined(separator: ",")
    }
}

extension HeistSemanticStringMatch {
    var heistDiscoveryDisplayValue: String {
        guard let value else { return mode.rawValue }
        guard mode != .exact else { return value.heistDiscoveryDisplayValue }
        return "\(mode.rawValue)(\(value.heistDiscoveryDisplayValue))"
    }
}

extension HeistSemanticStringValue {
    var heistDiscoveryDisplayValue: String {
        switch self {
        case .literal(let literal):
            return literal
        case .reference(let reference):
            return "\(reference.rawValue)_ref"
        }
    }
}

extension ElementAction {
    var heistDiscoveryDisplayValue: String {
        switch self {
        case .activate:
            return "activate"
        case .typeText:
            return "typeText"
        case .increment:
            return "increment"
        case .decrement:
            return "decrement"
        case .custom(let name):
            return "custom(\(name))"
        }
    }
}
