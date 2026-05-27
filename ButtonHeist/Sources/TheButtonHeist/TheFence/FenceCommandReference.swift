import TheScore

/// Descriptor-backed public command reference renderer.
///
/// This is intentionally pure: it reads executable command descriptors and MCP
/// contracts, then renders stable reference artifacts. Adapters and docs can
/// project from this surface without owning command names, defaults, grouping,
/// or parameter shape.
public enum FenceCommandReference {

    public static func commandMarkdown(
        descriptors: [FenceCommandDescriptor] = TheFence.Command.descriptors
    ) -> String {
        let sortedDescriptors = descriptors.sorted { $0.canonicalName < $1.canonicalName }
        var lines: [String] = [
            "# ButtonHeist Command Reference",
            "",
            "_Generated from `TheFence.Command.descriptors`._",
            "",
            "## Summary",
            "",
            "| Command | CLI | MCP | Batch | Description |",
            "|---------|-----|-----|-------|-------------|",
        ]

        for descriptor in sortedDescriptors {
            let columns = [
                "`\(descriptor.canonicalName)`",
                cliExposureSummary(descriptor.cliExposure, cliName: descriptor.cliName),
                mcpExposureSummary(descriptor.mcpExposure),
                yesNo(descriptor.isBatchExecutable),
                markdownCell(firstLine(of: descriptor.description)),
            ]
            lines.append("| \(columns.joined(separator: " | ")) |")
        }

        lines.append(contentsOf: ["", "## Details", ""])

        for descriptor in sortedDescriptors {
            lines.append(contentsOf: commandDetailLines(for: descriptor))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    public static func mcpMarkdown(
        contracts: [MCPToolContract] = TheFence.Command.mcpToolContracts
    ) -> String {
        let sortedContracts = contracts.sorted { $0.name < $1.name }
        var lines: [String] = [
            "# ButtonHeist MCP Tool Reference",
            "",
            "_Generated from `TheFence.Command.mcpToolContracts`._",
            "",
            "## Summary",
            "",
            "| Tool | Commands | Selector | Description |",
            "|------|----------|----------|-------------|",
        ]

        for contract in sortedContracts {
            let commands = contract.commands.map { "`\($0.rawValue)`" }.joined(separator: ", ")
            let selector = contract.selector.map { "`\($0.parameter.key)`" } ?? "-"
            lines.append(
                "| `\(contract.name)` | \(commands) | \(selector) | \(markdownCell(firstLine(of: contract.description))) |"
            )
        }

        lines.append(contentsOf: ["", "## Details", ""])

        for contract in sortedContracts {
            lines.append(contentsOf: mcpDetailLines(for: contract))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func commandDetailLines(for descriptor: FenceCommandDescriptor) -> [String] {
        var lines: [String] = [
            "### `\(descriptor.canonicalName)`",
            "",
            descriptor.description,
            "",
            "- CLI: \(cliExposureDetail(descriptor.cliExposure, cliName: descriptor.cliName))",
            "- MCP: \(mcpExposureDetail(descriptor.mcpExposure))",
            "- Batch: \(yesNo(descriptor.isBatchExecutable))",
            "- Playback: \(yesNo(descriptor.isPlaybackExecutable))",
            "- Connection before dispatch: \(yesNo(descriptor.requiresConnectionBeforeDispatch))",
        ]

        let aliases = descriptor.humanAliases.keys.sorted()
        if !aliases.isEmpty {
            lines.append("- Human aliases: \(aliases.map { "`\($0)`" }.joined(separator: ", "))")
        }

        lines.append(contentsOf: ["", "Parameters:", ""])
        lines.append(contentsOf: parameterTableLines(descriptor.parameters))
        lines.append("")
        return lines
    }

    private static func mcpDetailLines(for contract: MCPToolContract) -> [String] {
        var lines: [String] = [
            "### `\(contract.name)`",
            "",
            contract.description,
            "",
            "- Commands: \(contract.commands.map { "`\($0.rawValue)`" }.joined(separator: ", "))",
        ]

        if let selector = contract.selector {
            lines.append("- Selector: `\(selector.parameter.key)`")
            if let defaultValue = selector.defaultValue {
                lines.append("- Selector default: `\(defaultValue)`")
            }
            let routes = selector.commandByValue
                .sorted { $0.key < $1.key }
                .map { "`\($0.key)` -> `\($0.value.rawValue)`" }
                .joined(separator: ", ")
            lines.append("- Selector routes: \(routes)")
        }

        lines.append(contentsOf: ["", "Parameters:", ""])
        lines.append(contentsOf: parameterTableLines(contract.parameters))
        lines.append("")
        return lines
    }

    private static func parameterTableLines(_ parameters: [FenceParameterSpec]) -> [String] {
        guard !parameters.isEmpty else {
            return ["_None._"]
        }

        var lines = [
            "| Parameter | Type | Required | Default | Values |",
            "|-----------|------|----------|---------|--------|",
        ]
        for parameter in parameters {
            let defaultValue = parameter.defaultValue.map(markdownValue) ?? "-"
            let values = parameter.enumValues?.map { "`\($0)`" }.joined(separator: ", ") ?? "-"
            lines.append(
                "| `\(parameter.key)` | `\(parameter.type.rawValue)` | \(yesNo(parameter.required)) | \(defaultValue) | \(values) |"
            )
        }
        return lines
    }

    private static func cliExposureSummary(_ exposure: CLIExposure, cliName: String?) -> String {
        switch exposure {
        case .directCommand, .sessionOnly:
            return cliName.map { "`\($0)`" } ?? "-"
        case .groupedUnder(let commandName):
            return "`\(commandName)`"
        case .notExposed:
            return "-"
        }
    }

    private static func cliExposureDetail(_ exposure: CLIExposure, cliName: String?) -> String {
        switch exposure {
        case .directCommand:
            return cliName.map { "direct command `\($0)`" } ?? "direct command"
        case .groupedUnder(let commandName):
            return "grouped under `\(commandName)`"
        case .sessionOnly:
            return cliName.map { "session-only `\($0)`" } ?? "session-only"
        case .notExposed:
            return "not exposed"
        }
    }

    private static func mcpExposureSummary(_ exposure: MCPExposure) -> String {
        switch exposure {
        case .directTool:
            return "direct"
        case .groupedUnder(let toolName):
            return "`\(toolName)`"
        case .notExposed:
            return "-"
        }
    }

    private static func mcpExposureDetail(_ exposure: MCPExposure) -> String {
        switch exposure {
        case .directTool:
            return "direct tool"
        case .groupedUnder(let toolName):
            return "grouped under `\(toolName)`"
        case .notExposed:
            return "not exposed"
        }
    }

    private static func firstLine(of text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    private static func markdownCell(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private static func markdownValue(_ value: HeistValue) -> String {
        "`\(value.description.replacingOccurrences(of: "`", with: "\\`"))`"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}
