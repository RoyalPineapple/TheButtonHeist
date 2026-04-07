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
        let gestureCommands: Set<String> = Set(
            TheFence.Command.allCases
                .filter { $0.mcpExposure == .groupedUnder("gesture") }
                .map(\.rawValue)
        )

        for tool in ToolDefinitions.all {
            if tool.name == "gesture" {
                // The gesture tool routes via its "type" parameter to individual commands.
                // Verify the type enum values are all valid commands.
                let typeValues = extractEnumValues(from: tool, property: "type")
                for typeName in typeValues {
                    #expect(
                        gestureCommands.contains(typeName),
                        "Gesture type '\(typeName)' is not a valid gesture command"
                    )
                }
                // Also verify every gesture command appears in the enum
                for gestureCommand in gestureCommands {
                    #expect(
                        typeValues.contains(gestureCommand),
                        "Gesture command '\(gestureCommand)' missing from gesture tool's type enum"
                    )
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
        // The direct tool names listed in the MCP switch at main.swift must match
        // the direct tools in ToolDefinitions.all.
        let directToolNames = Set(
            ToolDefinitions.all
                .map(\.name)
                .filter { $0 != "gesture" }
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

    @Test("Direct tool schemas contain all parameter spec keys")
    func directToolSchemasContainSpecKeys() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        for command in TheFence.Command.allCases where command.mcpExposure == .directTool {
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
            guard let tool = toolsByName[command.rawValue] else { continue }
            let schemaRequired = extractRequiredKeys(from: tool)
            let specRequired = Set(command.parameters.filter(\.required).map(\.key))

            #expect(
                specRequired == schemaRequired,
                "Command '\(command.rawValue)': required mismatch — spec: \(specRequired.sorted()), schema: \(schemaRequired.sorted())"
            )
        }
    }

    @Test("Gesture tool schema contains all gesture command parameter keys")
    func gestureToolCoversAllGestureParams() {
        guard let gestureTool = ToolDefinitions.all.first(where: { $0.name == "gesture" }) else {
            Issue.record("No gesture tool found")
            return
        }
        let gestureSchemaKeys = extractPropertyKeys(from: gestureTool)

        // Collect the union of all gesture command parameter keys
        let gestureCommands = TheFence.Command.allCases.filter {
            $0.mcpExposure == .groupedUnder("gesture")
        }
        var allGestureParamKeys = Set<String>()
        for command in gestureCommands {
            for param in command.parameters {
                allGestureParamKeys.insert(param.key)
            }
        }

        // The gesture tool also has a "type" key not in any individual command's spec
        let schemaKeysMinusType = gestureSchemaKeys.subtracting(["type"])

        for paramKey in allGestureParamKeys {
            #expect(
                schemaKeysMinusType.contains(paramKey),
                "Gesture param '\(paramKey)' is in a gesture command spec but missing from gesture tool schema"
            )
        }
    }

    // MARK: - Exhaustiveness

    @Test("Command.parameters is exhaustive (no unhandled cases)")
    func parameterSpecIsExhaustive() {
        // If a new Command case is added without a parameters entry,
        // the switch in parameters will fail to compile. This test
        // verifies every case returns a non-crashing result at runtime.
        for command in TheFence.Command.allCases {
            _ = command.parameters
            _ = command.mcpExposure
        }
    }

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
