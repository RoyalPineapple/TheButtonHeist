import Foundation
import ThePlans
import TheScore

public extension TheFence.Command {
    static var mcpServerInstructions: String {
        return """
            Button Heist turns the app's accessibility hierarchy into a world model for agents. \
            Read it with \(inlineCode(getInterface.rawValue)); use \(inlineCode(getScreen.rawValue)) \
            only when pixels or viewport geometry matter. Target controls by accessibility language: \
            \(inlineCode(#".label("Pay")"#)), \(inlineCode(#".identifier("pay_button")"#)), \
            \(inlineCode(#".value("Milk")"#)), \(inlineCode(#".element(.label("Pay"), .traits([.button]))"#)), \
            and \(inlineCode(#".target(.label("Delete"), ordinal: 1)"#)) when duplicates need an ordinal. \
            Act with \(inlineCode(perform.rawValue)) for one DSL step; use \(inlineCode(runHeist.rawValue)) \
            for a full \(inlineCode("HeistPlan { ... }")). Runtime ButtonHeist source is the authoring \
            surface; raw JSON plan IR is internal/generated. \
            Full guide: docs/MCP-AGENT-GUIDE.md.
            """
    }

    static var cliJSONLinesHelp: String {
        let commandLines = descriptorHelpLines()

        return """
        Commands:

        Commands:
        \(commandLines.joined(separator: "\n"))

        StringMatch:
          label, identifier, and value matcher fields accept
          {"mode":"exact|contains|prefix|suffix","value":"..."}. Broad modes require a non-empty value.
          Use checks for ordered matcher chains, including traits:
          {"checks":[{"kind":"label","match":{"mode":"prefix","value":"foo"}},{"kind":"traits","values":["button"]}]}
        """
    }
}

private extension TheFence.Command {
    static func inlineList(_ values: [String]) -> String {
        values.map { inlineCode($0) }.joined(separator: ", ")
    }

    static func inlineCode(_ value: String) -> String {
        "`\(value)`"
    }

    static func descriptorHelpLines() -> [String] {
        let descriptors = Self.descriptors
            .filter { descriptor in descriptor.projection.cliExposure != .notExposed }
            .sorted { $0.command.rawValue < $1.command.rawValue }
        let width = descriptors.map(\.command.rawValue.count).max() ?? 0

        return descriptors.map { descriptor in
            let family = "[\(descriptor.family.rawValue)]"
            return "  \(padded(descriptor.command.rawValue, to: width))  \(family)  \(oneLineDescription(descriptor.projection.description))"
        }
    }

    static func oneLineDescription(_ description: String) -> String {
        description
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    static func padded(_ value: String, to width: Int) -> String {
        guard value.count < width else { return value }
        return value + String(repeating: " ", count: width - value.count)
    }
}
