import Foundation
import TheScore

public extension TheFence.Command {
    static var mcpServerInstructions: String {
        let selectorKeys = inlineList(ElementTarget.selectorFieldNames.map { "target.\($0)" })
        let disambiguatorKeys = inlineList(ElementTarget.disambiguatorFieldNames.map { "target.\($0)" })
        let expectationKey = activate.parameter(named: .expect)?.key ?? FenceParameterKey.expect.rawValue
        return """
            Button Heist drives iOS apps through the accessibility layer — the same interface \
            VoiceOver uses. Target elements with flat ElementTarget selector fields: \(selectorKeys), \
            not by screen coordinates. \(disambiguatorKeys) only disambiguates matcher results. \
            The core loop is: \(inlineCode(getInterface.rawValue)) \
            to read the app accessibility state, then \(inlineCode(activate.rawValue))/\
            \(inlineCode(typeText.rawValue))/\(inlineCode(scroll.rawValue))/\
            \(inlineCode(swipe.rawValue)) to act with an \(inlineCode(expectationKey)) \
            attached. When an action produces a transient state (spinner, \
            loading overlay), call \(inlineCode(waitForChange.rawValue)) with the same \
            expectation to ride through intermediate states. Use \
            \(inlineCode(runBatch.rawValue)) for multi-step sequences with per-step \
            expectations. Use \(inlineCode(startHeist.rawValue))/\
            \(inlineCode(stopHeist.rawValue)) to record replayable .heist files. \
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
            "  \(padded(descriptor.command.rawValue, to: width))  \(oneLineDescription(descriptor.description))"
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
