import Foundation

public extension TheFence.Command {
    static var cliSessionStartupPrompt: String {
        "Session started. Type '\(help.canonicalName)' for commands, '\(quit.canonicalName)' to exit."
    }

    static var cliSessionUnknownCommandMessage: String {
        "Unknown command. Type '\(help.canonicalName)' for available commands."
    }

    static var mcpServerInstructions: String {
        let matcherKeys = inlineList(activate.descriptor.elementTargetParameterKeys)
        let expectationKey = activate.parameter(named: .expect)?.key ?? FenceParameterKey.expect.rawValue
        return """
            Button Heist drives iOS apps through the accessibility layer — the same interface \
            VoiceOver uses. Target elements with schema matcher fields: \(matcherKeys), not \
            by screen coordinates. The core loop is: \(inlineMCPToolName(for: .getInterface)) \
            to read the app accessibility state, then \(inlineMCPToolName(for: .activate))/\
            \(inlineMCPToolName(for: .typeText))/\(inlineMCPToolName(for: .scroll))/\
            \(inlineMCPToolName(for: .swipe)) to act with an \(inlineCode(expectationKey)) \
            attached. Every response carries a \
            `[while_idle: ...]` block describing what changed since your last call — read it \
            before deciding to re-fetch. When an action produces a transient state (spinner, \
            loading overlay), call \(inlineMCPToolName(for: .waitForChange)) with the same \
            expectation to ride through intermediate states. Use \
            \(inlineMCPToolName(for: .runBatch)) for multi-step sequences with per-step \
            expectations. Use \(inlineMCPToolName(for: .startHeist))/\
            \(inlineMCPToolName(for: .stopHeist)) to record replayable .heist files. \
            Full guide: docs/MCP-AGENT-GUIDE.md.
            """
    }

    static var cliSessionHelp: String {
        let commandLines = descriptorHelpLines()

        return """
        Commands (type a command, or use JSON for full control):

        Commands:
        \(commandLines.joined(separator: "\n"))

        Bare words are looked up as current heistId handles (from get_interface).
        Key=value pairs work for any parameter: one_finger_tap identifier=btn x=100 y=200
        JSON input still works: {"command":"activate","heistId":"button_save"}
        """
    }
}

private extension TheFence.Command {
    static func inlineMCPToolName(for command: TheFence.Command) -> String {
        inlineCode(mcpToolName(for: command))
    }

    static func mcpToolName(for command: TheFence.Command) -> String {
        mcpToolContracts.first { $0.command == command }?.name ?? command.canonicalName
    }

    static func inlineList(_ values: [String]) -> String {
        values.map { inlineCode($0) }.joined(separator: ", ")
    }

    static func inlineCode(_ value: String) -> String {
        "`\(value)`"
    }

    static func descriptorHelpLines() -> [String] {
        let descriptors = Self.descriptors
            .filter { descriptor in descriptor.cliExposure != .notExposed }
            .sorted { $0.canonicalName < $1.canonicalName }
        let width = descriptors.map(\.canonicalName.count).max() ?? 0

        return descriptors.map { descriptor in
            "  \(padded(descriptor.canonicalName, to: width))  \(oneLineDescription(descriptor.description))"
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
