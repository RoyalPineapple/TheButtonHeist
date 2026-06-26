import TheScore
import ThePlans

/// Descriptor-backed public command reference renderer.
///
/// This is intentionally pure: it reads executable command descriptors and MCP
/// descriptors, then renders stable reference artifacts. Adapters and docs can
/// project from this surface without owning command names, defaults, grouping,
/// or parameter shape.
public enum FenceCommandReference {

    public static func commandMarkdown(
        descriptors: [FenceCommandDescriptor] = TheFence.Command.descriptors
    ) -> String {
        let sortedDescriptors = descriptors
            .filter { $0.projection.isPublicRequestContract }
            .sorted { $0.command.rawValue < $1.command.rawValue }
        var lines: [String] = [
            "# ButtonHeist Command Reference",
            "",
            "_Generated from `TheFence.Command.descriptors`._",
            "",
            "## Summary",
            "",
            "| Command | Family | CLI | MCP | Description |",
            "|---------|--------|-----|-----|-------------|",
        ]

        for descriptor in sortedDescriptors {
            let columns = [
                "`\(descriptor.command.rawValue)`",
                "`\(descriptor.family.rawValue)`",
                cliExposureSummary(descriptor),
                mcpExposureSummary(descriptor.projection.mcpExposure),
                markdownCell(firstLine(of: descriptor.projection.description)),
            ]
            lines.append("| \(columns.joined(separator: " | ")) |")
        }

        lines.append(contentsOf: stringMatchContractLines())
        lines.append(contentsOf: ["", "## Details", ""])

        for descriptor in sortedDescriptors {
            lines.append(contentsOf: commandDetailLines(for: descriptor))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    public static func mcpMarkdown(
        descriptors: [FenceCommandDescriptor] = TheFence.Command.descriptors
    ) -> String {
        let sortedDescriptors = descriptors
            .filter { $0.projection.mcpExposure == .directTool }
            .sorted { $0.command.rawValue < $1.command.rawValue }
        var lines: [String] = [
            "# ButtonHeist MCP Tool Reference",
            "",
            "_Generated from `TheFence.Command.descriptors`._",
            "",
            "## Summary",
            "",
            "| Tool | Family | Description |",
            "|------|--------|-------------|",
        ]

        for descriptor in sortedDescriptors {
            let command = descriptor.command.rawValue
            let family = descriptor.family.rawValue
            let description = markdownCell(firstLine(of: descriptor.projection.description))
            lines.append(
                "| `\(command)` | `\(family)` | \(description) |"
            )
        }

        lines.append(contentsOf: stringMatchContractLines())
        lines.append(contentsOf: ["", "## Details", ""])

        for descriptor in sortedDescriptors {
            lines.append(contentsOf: mcpDetailLines(for: descriptor))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func commandDetailLines(for descriptor: FenceCommandDescriptor) -> [String] {
        var lines: [String] = [
            "### `\(descriptor.command.rawValue)`",
            "",
            descriptor.projection.description,
            "",
            "- Family: `\(descriptor.family.rawValue)`",
            "- CLI: \(cliExposureDetail(descriptor))",
            "- MCP: \(mcpExposureDetail(descriptor.projection.mcpExposure))",
            "- Connection before dispatch: \(yesNo(descriptor.requiresConnectionBeforeDispatch))",
        ]

        lines.append(contentsOf: ["", "Parameters:", ""])
        lines.append(contentsOf: parameterTableLines(descriptor.parameters))
        lines.append("")
        return lines
    }

    private static func mcpDetailLines(for descriptor: FenceCommandDescriptor) -> [String] {
        var lines: [String] = [
            "### `\(descriptor.command.rawValue)`",
            "",
            descriptor.projection.description,
            "",
            "- Family: `\(descriptor.family.rawValue)`",
        ]

        lines.append(contentsOf: ["", "Parameters:", ""])
        lines.append(contentsOf: parameterTableLines(descriptor.parameters))
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

    private static func stringMatchContractLines() -> [String] {
        [
            "",
            "## StringMatch",
            "",
            "`stringMatch` fields such as `label`, `identifier`, and `value` accept object form " +
                "`{ \"mode\": \"exact|contains|prefix|suffix\", \"value\": \"...\" }`. " +
                "Use `exact` for exact matching; broad modes require a non-empty value. " +
                "Element matcher fields `label`, `identifier`, and `value` may also accept an array of StringMatch objects; " +
                "every object in the array must match the same property. Prefer `checks` for ordered element predicate chains, " +
                "including repeated string checks and trait checks. A string check item is " +
                "`{ \"kind\": \"label|identifier|value\", \"match\": { \"mode\": \"...\", \"value\": \"...\" } }`; " +
                "a trait check item is `{ \"kind\": \"traits|excludeTraits\", \"values\": [\"button\"] }`. " +
                "Updated element predicates use full `before` and `after` element matcher objects.",
        ]
    }

    private static func cliExposureSummary(_ descriptor: FenceCommandDescriptor) -> String {
        switch descriptor.projection.cliExposure {
        case .directCommand:
            return "`\(descriptor.command.rawValue)`"
        case .notExposed:
            return "-"
        }
    }

    private static func cliExposureDetail(_ descriptor: FenceCommandDescriptor) -> String {
        switch descriptor.projection.cliExposure {
        case .directCommand:
            return "direct command `\(descriptor.command.rawValue)`"
        case .notExposed:
            return "not exposed"
        }
    }

    private static func mcpExposureSummary(_ exposure: MCPExposure) -> String {
        switch exposure {
        case .directTool:
            return "direct"
        case .notExposed:
            return "-"
        }
    }

    private static func mcpExposureDetail(_ exposure: MCPExposure) -> String {
        switch exposure {
        case .directTool:
            return "direct tool"
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
