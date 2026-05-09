import Testing
import MCP
@testable import ButtonHeistMCP
import ButtonHeist

/// Verifies that MCP tool definitions stay in sync with TheFence.Command.
///
/// These tests catch three classes of drift:
/// 1. A new Command case with no corresponding MCP tool
/// 2. An MCP tool with no corresponding Command case
/// 3. Schema property keys that don't match the Command's parameter spec
struct ToolSyncTests {

    // MARK: - Tool Coverage

    @Test("Every externally exposed command has an MCP tool")
    func allExposedCommandsHaveMCPTools() {
        let mcpToolNames = Set(ToolDefinitions.all.map(\.name))

        for command in TheFence.Command.allCases {
            switch command.mcpExposure {
            case .directTool:
                #expect(
                    mcpToolNames.contains(command.rawValue),
                    "Command '\(command.rawValue)' is marked as directTool but has no MCP tool"
                )
            case .groupedUnder(let toolName):
                #expect(
                    mcpToolNames.contains(toolName),
                    "Command '\(command.rawValue)' is grouped under '\(toolName)' but that tool doesn't exist"
                )
            case .notExposed:
                break
            }
        }
    }

    @Test("Every MCP tool maps to a valid command")
    func allMCPToolsMapToValidCommands() {
        let commandRawValues = Set(TheFence.Command.allCases.map(\.rawValue))

        // Collect grouped commands by their group tool name
        var groupedCommands: [String: Set<String>] = [:]
        for command in TheFence.Command.allCases {
            if case .groupedUnder(let toolName) = command.mcpExposure {
                groupedCommands[toolName, default: []].insert(command.rawValue)
            }
        }

        for tool in ToolDefinitions.all {
            if let expectedCommands = groupedCommands[tool.name] {
                // Grouped tool — verify its enum values match the grouped commands.
                // gesture uses "type", scroll uses "mode", edit_action uses "action"
                let enumProperty: String
                switch tool.name {
                case "gesture": enumProperty = "type"
                case "scroll": enumProperty = "mode"
                case "edit_action": enumProperty = "action"
                default: enumProperty = "type"
                }

                let enumValues = extractEnumValues(from: tool, property: enumProperty)

                if tool.name == "scroll" {
                    // Scroll modes are synthetic names (page, to_visible, search, to_edge),
                    // not raw command values. Verify the count matches.
                    let expectedModes: Set<String> = ["page", "to_visible", "search", "to_edge"]
                    #expect(
                        enumValues == expectedModes,
                        "Scroll tool modes \(enumValues.sorted()) don't match expected \(expectedModes.sorted())"
                    )
                } else if tool.name == "edit_action" {
                    // edit_action has "dismiss" which maps to dismiss_keyboard,
                    // plus the standard edit actions. Just verify "dismiss" is present.
                    #expect(
                        enumValues.contains("dismiss"),
                        "edit_action tool missing 'dismiss' in action enum"
                    )
                } else {
                    for typeName in enumValues {
                        #expect(
                            expectedCommands.contains(typeName),
                            "\(tool.name) type '\(typeName)' is not a valid grouped command"
                        )
                    }
                    for groupedCommand in expectedCommands {
                        #expect(
                            enumValues.contains(groupedCommand),
                            "Grouped command '\(groupedCommand)' missing from \(tool.name) tool's enum"
                        )
                    }
                }
            } else {
                #expect(
                    commandRawValues.contains(tool.name),
                    "MCP tool '\(tool.name)' does not correspond to any TheFence.Command"
                )
            }
        }
    }

    @Test("MCP dispatch switch covers all tools")
    func dispatchSwitchCoversAllTools() {
        // Tools that are purely grouped (no matching direct command name)
        let purelyGroupedToolNames: Set<String> = ["gesture"]

        let directToolNames = Set(
            ToolDefinitions.all
                .map(\.name)
                .filter { !purelyGroupedToolNames.contains($0) }
        )
        let directCommands = Set(
            TheFence.Command.allCases
                .filter { $0.mcpExposure == .directTool }
                .map(\.rawValue)
        )
        let toolsOnly = directToolNames.subtracting(directCommands)
        let commandsOnly = directCommands.subtracting(directToolNames)
        #expect(
            directToolNames == directCommands,
            "Direct MCP tools and direct commands differ: tools-only: \(toolsOnly), commands-only: \(commandsOnly)"
        )
    }

    // MARK: - Parameter Schema Sync

    // Hybrid tools: their MCP tool name matches a direct command, but the tool
    // also routes to other commands via a mode/action parameter. Their schemas
    // are supersets of any individual command's spec, so we skip per-command
    // schema checks and validate them via the grouped tool coverage test instead.
    private static let hybridToolNames: Set<String> = ["scroll", "edit_action"]

    @Test("Direct tool schemas contain all parameter spec keys")
    func directToolSchemasContainSpecKeys() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        for command in TheFence.Command.allCases where command.mcpExposure == .directTool {
            guard !Self.hybridToolNames.contains(command.rawValue) else { continue }
            guard let tool = toolsByName[command.rawValue] else { continue }
            let schemaKeys = extractPropertyKeys(from: tool)
            let specKeys = Set(command.parameters.map(\.key))

            for specKey in specKeys {
                #expect(
                    schemaKeys.contains(specKey),
                    "Command '\(command.rawValue)': parameter '\(specKey)' is in the spec but missing from MCP schema"
                )
            }
        }
    }

    @Test("Direct tool schemas don't have extra keys beyond the spec")
    func directToolSchemasMatchSpec() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        for command in TheFence.Command.allCases where command.mcpExposure == .directTool {
            guard !Self.hybridToolNames.contains(command.rawValue) else { continue }
            guard let tool = toolsByName[command.rawValue] else { continue }
            let schemaKeys = extractPropertyKeys(from: tool)
            let specKeys = Set(command.parameters.map(\.key))

            let extraKeys = schemaKeys.subtracting(specKeys)
            #expect(
                extraKeys.isEmpty,
                "Command '\(command.rawValue)': MCP schema has extra keys not in spec: \(extraKeys.sorted())"
            )
        }
    }

    @Test("Required parameters in spec match required in schema")
    func requiredParametersMatch() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        for command in TheFence.Command.allCases where command.mcpExposure == .directTool {
            guard !Self.hybridToolNames.contains(command.rawValue) else { continue }
            guard let tool = toolsByName[command.rawValue] else { continue }
            let schemaRequired = extractRequiredKeys(from: tool)
            let specRequired = Set(command.parameters.filter(\.required).map(\.key))

            #expect(
                specRequired == schemaRequired,
                "Command '\(command.rawValue)': required mismatch — spec: \(specRequired.sorted()), schema: \(schemaRequired.sorted())"
            )
        }
    }

    @Test("Grouped tool schemas contain all grouped command parameter keys")
    func groupedToolsCoverAllGroupedParams() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        // Map of group tool name → synthetic keys added by the group (not in individual command specs)
        let syntheticKeys: [String: Set<String>] = [
            "gesture": ["type"],
            "scroll": ["mode"],
            "edit_action": ["action"],
        ]

        // Collect grouped commands by tool name
        var groupsByTool: [String: [TheFence.Command]] = [:]
        for command in TheFence.Command.allCases {
            if case .groupedUnder(let toolName) = command.mcpExposure {
                groupsByTool[toolName, default: []].append(command)
            }
        }

        for (toolName, commands) in groupsByTool {
            guard let tool = toolsByName[toolName] else {
                Issue.record("No tool found for group '\(toolName)'")
                continue
            }
            let schemaKeys = extractPropertyKeys(from: tool)
            let keysToIgnore = syntheticKeys[toolName] ?? []
            let schemaKeysMinusSynthetic = schemaKeys.subtracting(keysToIgnore)

            var allParamKeys = Set<String>()
            for command in commands {
                for param in command.parameters {
                    allParamKeys.insert(param.key)
                }
            }

            for paramKey in allParamKeys {
                #expect(
                    schemaKeysMinusSynthetic.contains(paramKey),
                    "\(toolName) param '\(paramKey)' is in a grouped command spec but missing from tool schema"
                )
            }
        }
    }

    // MARK: - Exhaustiveness

    @Test("ToolDefinitions.all has no duplicate tool names")
    func noDuplicateToolNames() {
        var seen = Set<String>()
        for tool in ToolDefinitions.all {
            #expect(
                !seen.contains(tool.name),
                "Duplicate MCP tool name: '\(tool.name)'"
            )
            seen.insert(tool.name)
        }
    }

    // MARK: - Helpers

    /// Extract property key names from a Tool's inputSchema.
    private func extractPropertyKeys(from tool: Tool) -> Set<String> {
        guard case .object(let schema) = tool.inputSchema,
              let properties = schema["properties"],
              case .object(let propertyMap) = properties else {
            return []
        }
        return Set(propertyMap.keys)
    }

    /// Extract the "required" array from a Tool's inputSchema.
    private func extractRequiredKeys(from tool: Tool) -> Set<String> {
        guard case .object(let schema) = tool.inputSchema,
              let required = schema["required"],
              case .array(let values) = required else {
            return []
        }
        return Set(values.compactMap { value -> String? in
            guard case .string(let string) = value else { return nil }
            return string
        })
    }

    /// Extract enum string values for a specific property from a Tool's inputSchema.
    private func extractEnumValues(from tool: Tool, property: String) -> Set<String> {
        guard case .object(let schema) = tool.inputSchema,
              let properties = schema["properties"],
              case .object(let propertyMap) = properties,
              let propertyDef = propertyMap[property],
              case .object(let propSchema) = propertyDef,
              let enumValues = propSchema["enum"],
              case .array(let values) = enumValues else {
            return []
        }
        return Set(values.compactMap { value -> String? in
            guard case .string(let string) = value else { return nil }
            return string
        })
    }
}
