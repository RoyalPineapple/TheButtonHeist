import Foundation
import TheScore

public extension TheFence.Command {
    static var mcpServerInstructions: String {
        return """
            Button Heist drives iOS apps through the accessibility layer — the same interface \
            VoiceOver uses. Read state with \(inlineCode(getInterface.rawValue)) and \
            \(inlineCode(getScreen.rawValue)); act with \(inlineCode(perform.rawValue)) using a \
            single ButtonHeist DSL step in the \(inlineCode("step")) field, such as \
            \(inlineCode(#"Activate(.label("Pay")).expect(.changed(.screen()))"#)). \
            Use \(inlineCode(runHeist.rawValue)) for full `HeistPlan { ... }` programs with \
            definitions, branching, waits with bodies, loops, warnings, failures, or multiple steps. \
            Runtime ButtonHeist source is not arbitrary Swift and never uses host-language compilation. \
            JSON plan IR is internal/generated, not the agent authoring surface. \
            Full guide: docs/MCP-AGENT-GUIDE.md.
            """
    }

    static var cliJSONLinesHelp: String {
        let commandLines = descriptorHelpLines()

        return """
        Commands:

        Commands:
        \(commandLines.joined(separator: "\n"))
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
            .filter { descriptor in descriptor.cliExposure != .notExposed }
            .sorted { $0.command.rawValue < $1.command.rawValue }
        let width = descriptors.map(\.command.rawValue.count).max() ?? 0

        return descriptors.map { descriptor in
            let family = "[\(descriptor.family.rawValue)]"
            return "  \(padded(descriptor.command.rawValue, to: width))  \(family)  \(oneLineDescription(descriptor.description))"
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
