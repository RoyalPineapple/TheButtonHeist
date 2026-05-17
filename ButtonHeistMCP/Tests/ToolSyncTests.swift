import Testing
import MCP
@testable import ButtonHeistMCP
import ButtonHeist
import Foundation
import TheScore

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
                    // not raw command values. The boundary parses them into ScrollMode,
                    // so the schema enum must match ScrollMode.allCases exactly.
                    let expectedModes = Set(ScrollMode.allCases.map(\.rawValue))
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

    @Test("MCP direct tools stay aligned with direct commands")
    func directToolsStayAlignedWithDirectCommands() {
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

    @Test("Gesture drawing schemas describe array item shapes")
    func gestureDrawingSchemasDescribeArrayItemShapes() {
        guard let gesture = ToolDefinitions.all.first(where: { $0.name == "gesture" }) else {
            Issue.record("No gesture tool found")
            return
        }

        guard let pointsSchema = extractPropertySchema(from: gesture, property: "points"),
              let pointItems = extractObjectField(from: pointsSchema, key: "items") else {
            Issue.record("gesture.points missing object item schema")
            return
        }
        #expect(extractStringField(from: pointsSchema, key: "type") == "array")
        #expect(extractPropertyKeys(from: pointItems) == ["x", "y"])
        #expect(extractRequiredKeys(from: pointItems) == ["x", "y"])

        guard let segmentsSchema = extractPropertySchema(from: gesture, property: "segments"),
              let segmentItems = extractObjectField(from: segmentsSchema, key: "items") else {
            Issue.record("gesture.segments missing object item schema")
            return
        }
        let segmentKeys: Set<String> = ["cp1X", "cp1Y", "cp2X", "cp2Y", "endX", "endY"]
        #expect(extractStringField(from: segmentsSchema, key: "type") == "array")
        #expect(extractPropertyKeys(from: segmentItems) == segmentKeys)
        #expect(extractRequiredKeys(from: segmentItems) == segmentKeys)
    }

    @Test("Scroll direction schema lists all server-validated directions")
    func scrollDirectionSchemaListsAllServerValidatedDirections() {
        guard let scroll = ToolDefinitions.all.first(where: { $0.name == "scroll" }) else {
            Issue.record("No scroll tool found")
            return
        }

        let pageDirections = extractEnumValues(from: scroll, property: "direction")
        #expect(pageDirections == Set(ScrollDirection.allCases.map(\.rawValue)))
        #expect(ScrollSearchDirection.allCases.allSatisfy { pageDirections.contains($0.rawValue) })
    }

    @Test("MCP enum schemas match wire-boundary enums")
    func mcpEnumSchemasMatchWireBoundaryEnums() {
        let getInterface = ToolDefinitions.all.first { $0.name == "get_interface" }
        #expect(extractEnumValues(from: getInterface, property: "scope") == Set(GetInterfaceScope.allCases.map(\.rawValue)))
        #expect(extractEnumValues(from: getInterface, property: "detail") == Set(InterfaceDetail.allCases.map(\.rawValue)))

        let scroll = ToolDefinitions.all.first { $0.name == "scroll" }
        #expect(extractEnumValues(from: scroll, property: "mode") == Set(ScrollMode.allCases.map(\.rawValue)))
        #expect(extractEnumValues(from: scroll, property: "direction") == Set(ScrollDirection.allCases.map(\.rawValue)))
        #expect(extractEnumValues(from: scroll, property: "edge") == Set(ScrollEdge.allCases.map(\.rawValue)))

        let gesture = ToolDefinitions.all.first { $0.name == "gesture" }
        #expect(extractEnumValues(from: gesture, property: "type") == Set(GestureType.allCases.map(\.rawValue)))

        let editAction = ToolDefinitions.all.first { $0.name == "edit_action" }
        #expect(
            extractEnumValues(from: editAction, property: "action") ==
                Set(EditAction.allCases.map(\.rawValue) + ["dismiss"])
        )
    }

    @Test("get_interface scope schema is Claude-compatible")
    func getInterfaceScopeSchemaIsClaudeCompatible() {
        guard let getInterface = ToolDefinitions.all.first(where: { $0.name == "get_interface" }),
              let scopeSchema = extractPropertySchema(from: getInterface, property: "scope") else {
            Issue.record("get_interface.scope missing property schema")
            return
        }

        #expect(extractStringField(from: scopeSchema, key: "type") == "string")
        #expect(extractEnumValues(from: scopeSchema) == Set(GetInterfaceScope.allCases.map(\.rawValue)))

        let violations = unsupportedCompositionKeywordPaths(in: .object(scopeSchema))
        #expect(
            violations.isEmpty,
            "get_interface.scope schema uses unsupported composition keywords at: \(violations.joined(separator: ", "))"
        )
    }

    @Test("Expect schema advertises Claude-compatible object form")
    func expectSchemaAdvertisesClaudeCompatibleObjectForm() throws {
        let toolsWithExpect = ToolDefinitions.all.filter { extractPropertyKeys(from: $0).contains("expect") }
        #expect(!toolsWithExpect.isEmpty)

        for tool in toolsWithExpect {
            guard let expectSchema = extractPropertySchema(from: tool, property: "expect") else {
                Issue.record("\(tool.name) is missing expect property schema")
                continue
            }
            #expect(
                extractStringField(from: expectSchema, key: "type") == "object",
                "\(tool.name).expect should advertise only object form to avoid client-side anyOf/oneOf normalization"
            )
        }
    }

    @Test("Expect object type enum matches ActionExpectation wire types")
    func expectObjectTypeEnumMatchesActionExpectationWireTypes() {
        for tool in ToolDefinitions.all where extractPropertyKeys(from: tool).contains("expect") {
            guard let expectSchema = extractPropertySchema(from: tool, property: "expect"),
                  let expectProperties = extractObjectField(from: expectSchema, key: "properties"),
                  let typeSchema = extractObjectField(from: expectProperties, key: "type") else {
                Issue.record("\(tool.name).expect missing object type schema")
                continue
            }

            #expect(
                extractEnumValues(from: typeSchema) == Set(ActionExpectation.wireTypeValues),
                "\(tool.name).expect type enum should match ActionExpectation wire type values"
            )
        }
    }

    @Test("Expect object property enum matches ElementProperty")
    func expectObjectPropertyEnumMatchesElementProperty() {
        for tool in ToolDefinitions.all where extractPropertyKeys(from: tool).contains("expect") {
            guard let expectSchema = extractPropertySchema(from: tool, property: "expect"),
                  let expectProperties = extractObjectField(from: expectSchema, key: "properties"),
                  let propertySchema = extractObjectField(from: expectProperties, key: "property") else {
                Issue.record("\(tool.name).expect missing element property schema")
                continue
            }

            #expect(
                extractEnumValues(from: propertySchema) == Set(ElementProperty.allCases.map(\.rawValue)),
                "\(tool.name).expect property enum should match ElementProperty cases"
            )
        }
    }

    @Test("type_text schema rejects no-op scalar values")
    func typeTextSchemaRejectsNoOpScalarValues() {
        guard let typeText = ToolDefinitions.all.first(where: { $0.name == "type_text" }),
              let textSchema = extractPropertySchema(from: typeText, property: "text"),
              let deleteCountSchema = extractPropertySchema(from: typeText, property: "deleteCount") else {
            Issue.record("type_text is missing text or deleteCount schema")
            return
        }

        #expect(extractIntField(from: textSchema, key: "minLength") == 1)
        #expect(extractIntField(from: deleteCountSchema, key: "minimum") == 1)
    }

    // MARK: - Exhaustiveness

    @Test("Tool input schemas avoid Claude-incompatible composition keywords")
    func toolInputSchemasAvoidUnsupportedCompositionKeywords() {
        for tool in ToolDefinitions.all {
            let violations = unsupportedCompositionKeywordPaths(in: tool.inputSchema)
            #expect(
                violations.isEmpty,
                "\(tool.name) input schema uses unsupported composition keywords at: \(violations.joined(separator: ", "))"
            )
        }
    }

    @Test("Tool input schemas avoid JSON Schema type unions")
    func toolInputSchemasAvoidTypeUnions() {
        for tool in ToolDefinitions.all {
            let violations = typeUnionPaths(in: tool.inputSchema)
            #expect(
                violations.isEmpty,
                "\(tool.name) input schema uses array-valued type unions at: \(violations.joined(separator: ", "))"
            )
        }
    }

    @Test("Array schemas declare item schemas")
    func arraySchemasDeclareItems() {
        for tool in ToolDefinitions.all {
            let violations = arrayWithoutItemsPaths(in: tool.inputSchema)
            #expect(
                violations.isEmpty,
                "\(tool.name) input schema has array fields without items at: \(violations.joined(separator: ", "))"
            )
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

    // MARK: - Documentation Drift

    @Test("Documented MCP tool counts match ToolDefinitions")
    func documentedMCPToolCountsMatchToolDefinitions() throws {
        let expectedCount = ToolDefinitions.all.count
        for path in ["README.md", "ButtonHeistMCP/README.md", "docs/API.md", "docs/ARCHITECTURE.md"] {
            let contents = try readRepositoryFile(path)
            let countMatches = regexMatches(in: contents, pattern: #"expos(?:es|ing) ([0-9]+) (?:[A-Za-z-]+ )*tools"#)
            #expect(!countMatches.isEmpty, "\(path) should document the MCP tool count")

            for match in countMatches {
                #expect(
                    match == "\(expectedCount)",
                    "\(path) documents \(match) MCP tools, expected \(expectedCount)"
                )
            }
        }
    }

    @Test("MCP README tool surface matches ToolDefinitions")
    func mcpReadmeToolSurfaceMatchesToolDefinitions() throws {
        let contents = try readRepositoryFile("ButtonHeistMCP/README.md")
        let toolSurface = try section(named: "## Tool Surface", endingBefore: "## Runtime Behavior", in: contents)
        let documentedTools = Set(
            toolSurface.split(separator: "\n").compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- `") else { return nil }
                return trimmed.dropFirst(3).split(separator: "`", maxSplits: 1).first.map(String.init)
            }
        )
        let actualTools = Set(ToolDefinitions.all.map(\.name))

        #expect(
            documentedTools == actualTools,
            "MCP README tool list differs: docs-only \(documentedTools.subtracting(actualTools).sorted()), missing \(actualTools.subtracting(documentedTools).sorted())"
        )
    }

    @Test("Documented command catalog counts match TheFence.Command")
    func documentedCommandCatalogCountsMatchFenceCommands() throws {
        let expectedCount = TheFence.Command.allCases.count
        let api = try readRepositoryFile("docs/API.md")
        let totalCasesMatches = regexMatches(in: api, pattern: #"// \.\.\. ([0-9]+) total cases"#)
        #expect(totalCasesMatches.contains("\(expectedCount)"), "docs/API.md Command snippet should document \(expectedCount) total cases")

        for path in ["docs/API.md", "docs/ARCHITECTURE.md"] {
            let contents = try readRepositoryFile(path)
            let countMatches = regexMatches(in: contents, pattern: #"([0-9]+) supported commands"#)
            #expect(!countMatches.isEmpty, "\(path) should document the command catalog count")
            #expect(
                countMatches.allSatisfy { $0 == "\(expectedCount)" },
                "\(path) documents stale command counts: \(countMatches)"
            )
        }
    }

    // MARK: - Helpers

    private func readRepositoryFile(_ path: String) throws -> String {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent(path))
        guard let contents = String(bytes: data, encoding: .utf8) else {
            Issue.record("\(path) is not UTF-8")
            return ""
        }
        return contents
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func section(named heading: String, endingBefore nextHeading: String, in contents: String) throws -> String {
        guard let startRange = contents.range(of: heading),
              let endRange = contents[startRange.upperBound...].range(of: nextHeading) else {
            Issue.record("Missing section \(heading)")
            return ""
        }
        return String(contents[startRange.upperBound..<endRange.lowerBound])
    }

    private func regexMatches(in contents: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: contents) else { return nil }
            return String(contents[matchRange])
        }
    }

    /// Extract property key names from a Tool's inputSchema.
    private func extractPropertyKeys(from tool: Tool) -> Set<String> {
        guard case .object(let schema) = tool.inputSchema,
              let properties = schema["properties"],
              case .object(let propertyMap) = properties else {
            return []
        }
        return Set(propertyMap.keys)
    }

    private func extractPropertyKeys(from schema: [String: Value]) -> Set<String> {
        guard let properties = schema["properties"],
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

    private func extractRequiredKeys(from schema: [String: Value]) -> Set<String> {
        guard let required = schema["required"],
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

    private func extractEnumValues(from tool: Tool?, property: String) -> Set<String> {
        guard let tool else { return [] }
        return extractEnumValues(from: tool, property: property)
    }

    private func extractEnumValues(from schema: [String: Value]) -> Set<String> {
        guard let enumValues = schema["enum"],
              case .array(let values) = enumValues else {
            return []
        }
        return Set(values.compactMap { value -> String? in
            guard case .string(let string) = value else { return nil }
            return string
        })
    }

    private func extractPropertySchema(from tool: Tool, property: String) -> [String: Value]? {
        guard case .object(let schema) = tool.inputSchema,
              let properties = schema["properties"],
              case .object(let propertyMap) = properties,
              let propertyDef = propertyMap[property],
              case .object(let propertySchema) = propertyDef else {
            return nil
        }
        return propertySchema
    }

    private func extractObjectField(from schema: [String: Value], key: String) -> [String: Value]? {
        guard let value = schema[key],
              case .object(let object) = value else {
            return nil
        }
        return object
    }

    private func arrayWithoutItemsPaths(in value: Value, path: String = "$") -> [String] {
        switch value {
        case .object(let object):
            let directViolations: [String]
            if let typeValue = object["type"], case .string("array") = typeValue, object["items"] == nil {
                directViolations = [path]
            } else {
                directViolations = []
            }
            let nestedViolations = object.flatMap { key, nestedValue in
                arrayWithoutItemsPaths(in: nestedValue, path: "\(path).\(key)")
            }
            return directViolations + nestedViolations
        case .array(let values):
            return values.enumerated().flatMap { index, nestedValue in
                arrayWithoutItemsPaths(in: nestedValue, path: "\(path)[\(index)]")
            }
        default:
            return []
        }
    }

    private func typeUnionPaths(in value: Value, path: String = "$") -> [String] {
        switch value {
        case .object(let object):
            let directViolations: [String]
            if let typeValue = object["type"], case .array = typeValue {
                directViolations = ["\(path).type"]
            } else {
                directViolations = []
            }
            let nestedViolations = object.flatMap { key, nestedValue in
                typeUnionPaths(in: nestedValue, path: "\(path).\(key)")
            }
            return directViolations + nestedViolations
        case .array(let values):
            return values.enumerated().flatMap { index, nestedValue in
                typeUnionPaths(in: nestedValue, path: "\(path)[\(index)]")
            }
        default:
            return []
        }
    }

    private func unsupportedCompositionKeywordPaths(in value: Value, path: String = "$") -> [String] {
        let unsupportedKeys: Set<String> = ["oneOf", "allOf", "anyOf"]

        switch value {
        case .object(let object):
            let directViolations = object.keys
                .filter { unsupportedKeys.contains($0) }
                .map { "\(path).\($0)" }
            let nestedViolations = object.flatMap { key, nestedValue in
                unsupportedCompositionKeywordPaths(in: nestedValue, path: "\(path).\(key)")
            }
            return directViolations + nestedViolations
        case .array(let values):
            return values.enumerated().flatMap { index, nestedValue in
                unsupportedCompositionKeywordPaths(in: nestedValue, path: "\(path)[\(index)]")
            }
        default:
            return []
        }
    }

    private func extractStringField(from schema: [String: Value], key: String) -> String? {
        guard let value = schema[key],
              case .string(let string) = value else {
            return nil
        }
        return string
    }

    private func extractIntField(from schema: [String: Value], key: String) -> Int? {
        guard let value = schema[key],
              case .int(let int) = value else {
            return nil
        }
        return int
    }
}
