import Foundation
import ThePlans

import TheScore

extension FenceResponse {

    func compactHeistCatalog(_ descriptions: [HeistDescription], detail: HeistCatalogDetail) -> String {
        guard !descriptions.isEmpty else { return "heists: none" }
        let lines = descriptions.flatMap { description in
            catalogLines(for: description, detail: detail, indent: "  ")
        }
        return (["heists:"] + lines).joined(separator: "\n")
    }

    func compactHeistDescription(_ description: HeistDescription) -> String {
        var lines = [
            "heist \(description.identity.displayName) [\(description.role.rawValue)] "
                + "\(parameterSummary(description))",
        ]
        appendSurfaceLines(description.semanticSurface, to: &lines)
        return lines.joined(separator: "\n")
    }

    func formatHeistCatalogHuman(_ descriptions: [HeistDescription], detail: HeistCatalogDetail) -> String {
        guard !descriptions.isEmpty else { return "No heists" }
        var lines = ["Heists:"]
        lines.append(contentsOf: descriptions.flatMap { description in
            catalogLines(for: description, detail: detail, indent: "  ", paddedRole: true)
        })
        return lines.joined(separator: "\n")
    }

    func formatHeistDescriptionHuman(_ description: HeistDescription) -> String {
        var lines = [
            "Heist: \(description.identity.displayName)",
            "Role: \(description.role.rawValue)",
            "Parameter: \(parameterSummary(description))",
        ]
        appendSurfaceLines(description.semanticSurface, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func catalogLines(
        for description: HeistDescription,
        detail: HeistCatalogDetail,
        indent: String,
        paddedRole: Bool = false
    ) -> [String] {
        let role = paddedRole
            ? description.role.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            : description.role.rawValue
        let firstLine = "\(indent)\(role) \(description.identity.displayName) "
            + "\(parameterSummary(description, includeName: detail == .detailed))"
            + " summary=\(description.heistCatalogSummary)"
            + " tags=\(description.heistCatalogTags.joined(separator: ","))"
        var lines = [firstLine]
        if detail == .detailed {
            let surface = description.semanticSurface
            if !surface.nestedRunHeists.isEmpty {
                lines.append("\(indent)  nested RunHeist: \(surface.nestedRunHeists.map(\.heistDiscoveryDisplayValue).joined(separator: ", "))")
            }
            if !surface.actionCommands.isEmpty {
                lines.append("\(indent)  actions: \(surface.actionCommands.map(\.heistDiscoveryDisplayValue).joined(separator: ", "))")
            }
            lines.append("\(indent)  waits=\(surface.waits.count) expectations=\(surface.expectations.count)")
            if !surface.semanticSurfaces.isEmpty {
                lines.append("\(indent)  semantic surfaces: \(surface.semanticSurfaces.map(\.heistDiscoveryDisplayValue).joined(separator: ", "))")
            }
        }
        return lines
    }

    private func parameterSummary(_ description: HeistDescription, includeName: Bool = true) -> String {
        parameterSummary(
            kind: description.parameterKind,
            name: includeName ? description.parameterName?.rawValue : nil,
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

extension HeistDescription {
    var heistCatalogSummary: String {
        var summary = role == .entry ? "Root entry heist" : "Reusable heist capability"
        if parameterKind.requiresArgument {
            summary += " requiring \(parameterKind.rawValue) argument"
        }
        return summary
    }

    var heistCatalogTags: [String] {
        let surface = semanticSurface
        var tags = [role == .entry ? "entry" : "capability"]
        if parameterKind.requiresArgument {
            tags.append("parameterized")
        }
        if !surface.nestedRunHeists.isEmpty {
            tags.append("composed")
        }
        if !surface.waits.isEmpty || !surface.expectations.isEmpty {
            tags.append("assertion")
        }
        for command in surface.actionCommands {
            let tag: String? = switch command {
            case .typeText:
                "text-input"
            case .scroll, .scrollToVisible, .scrollToEdge:
                "scroll"
            case .oneFingerTap, .longPress, .swipe, .drag:
                "gesture"
            case .activate, .increment, .decrement, .performCustomAction, .rotor, .dismiss, .magicTap,
                 .editAction, .setPasteboard, .dismissKeyboard:
                "semantic-action"
            case .takeScreenshot:
                nil
            }
            if let tag, !tags.contains(tag) {
                tags.append(tag)
            }
        }
        return tags
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

extension ElementPredicateCheck {
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
            return "traits=\(traits.canonicalHeistTraitArray.map(\.rawValue).joined(separator: "|"))"
        case .actions(let actions):
            return "actions=\(actions.canonicalElementActionArray.map(\.heistDiscoveryDisplayValue).joined(separator: "|"))"
        case .customContent(let match):
            return "customContent=\(match.heistDiscoveryDisplayValue)"
        case .rotors(let matches):
            return "rotors=\(matches.map(\.heistDiscoveryDisplayValue).joined(separator: "|"))"
        case .exclude(let check):
            return "exclude(\(check.heistDiscoveryDisplayValue))"
        }
    }
}

extension CustomContentMatch {
    var heistDiscoveryDisplayValue: String {
        [
            label.map { "label=\($0.heistDiscoveryDisplayValue)" },
            value.map { "value=\($0.heistDiscoveryDisplayValue)" },
            isImportant.map { "isImportant=\($0)" },
        ].compactMap { $0 }.joined(separator: ",")
    }
}

extension StringMatch {
    var heistDiscoveryDisplayValue: String {
        guard let value else { return mode.rawValue }
        guard mode != .exact else { return value.heistDiscoveryDisplayValue }
        return "\(mode.rawValue)(\(value.heistDiscoveryDisplayValue))"
    }
}

extension AuthoredString {
    var heistDiscoveryDisplayValue: String {
        switch self {
        case .literal(let literal):
            return literal
        case .ref(let reference):
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
