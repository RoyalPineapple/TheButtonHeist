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

        for tool in ToolDefinitions.all {
            guard let contract = TheFence.Command.mcpToolContract(named: tool.name) else {
                Issue.record("MCP tool '\(tool.name)' has no MCPToolContract")
                continue
            }

            if let selector = contract.selector {
                let enumValues = extractEnumValues(from: tool, property: selector.parameter.key)
                let expectedValues = Set(selector.parameter.enumValues ?? [])
                #expect(
                    enumValues == expectedValues,
                    "\(tool.name).\(selector.parameter.key) enum should be rendered from the selector contract"
                )
                for enumValue in enumValues {
                    #expect(
                        selector.command(for: enumValue) != nil,
                        "\(tool.name) selector value '\(enumValue)' is not routed by MCPToolSelector"
                    )
                }
            } else {
                #expect(
                    commandRawValues.contains(tool.name),
                    "MCP tool '\(tool.name)' does not correspond to any TheFence.Command"
                )
                #expect(
                    contract.commands.map(\.rawValue) == [tool.name],
                    "\(tool.name) should be a one-command direct MCP contract"
                )
            }
        }
    }

    @Test("MCP direct tools stay aligned with direct commands")
    func directToolsStayAlignedWithDirectCommands() {
        // Tools that are purely grouped (no matching direct command name)
        let purelyGroupedToolNames = Set(
            TheFence.Command.mcpToolContracts
                .map(\.name)
                .filter { TheFence.Command(rawValue: $0) == nil }
        )

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
    private static let hybridToolNames: Set<String> = Set(
        TheFence.Command.mcpToolContracts.compactMap { contract in
            guard contract.selector != nil,
                  TheFence.Command(rawValue: contract.name)?.mcpExposure == .directTool else {
                return nil
            }
            return contract.name
        }
    )

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

        for contract in TheFence.Command.mcpToolContracts where contract.selector != nil {
            guard let tool = toolsByName[contract.name] else {
                Issue.record("No tool found for group '\(contract.name)'")
                continue
            }
            let schemaKeys = extractPropertyKeys(from: tool)
            let keysToIgnore = contract.selector.map { Set([$0.parameter.key]) } ?? []
            let schemaKeysMinusSynthetic = schemaKeys.subtracting(keysToIgnore)

            var allParamKeys = Set<String>()
            for command in contract.commands {
                for param in command.parameters {
                    allParamKeys.insert(param.key)
                }
            }

            for paramKey in allParamKeys.subtracting(keysToIgnore) {
                #expect(
                    schemaKeysMinusSynthetic.contains(paramKey),
                    "\(contract.name) param '\(paramKey)' is in a grouped command spec but missing from tool schema"
                )
            }
        }
    }

    @Test("Gesture drawing schemas describe array item shapes")
    func gestureDrawingSchemasDescribeArrayItemShapes() {
        guard let gesture = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.gestureMCPToolName }) else {
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
        guard let scroll = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.scroll.rawValue }) else {
            Issue.record("No scroll tool found")
            return
        }

        let pageDirections = extractEnumValues(from: scroll, property: "direction")
        #expect(pageDirections == Set(ScrollDirection.allCases.map(\.rawValue)))
        #expect(ScrollSearchDirection.allCases.allSatisfy { pageDirections.contains($0.rawValue) })
    }

    @Test("MCP enum schemas match advertised command boundaries")
    func mcpEnumSchemasMatchAdvertisedCommandBoundaries() {
        let getInterface = ToolDefinitions.all.first { $0.name == TheFence.Command.getInterface.rawValue }
        #expect(extractEnumValues(from: getInterface, property: "detail") == Set(InterfaceDetail.allCases.map(\.rawValue)))
        if let subtreeSchema = getInterface.flatMap({ extractPropertySchema(from: $0, property: "subtree") }),
           let subtreeProperties = extractObjectField(from: subtreeSchema, key: "properties"),
           let containerSchema = extractObjectField(from: subtreeProperties, key: "container"),
           let containerProperties = extractObjectField(from: containerSchema, key: "properties"),
           let typeSchema = extractObjectField(from: containerProperties, key: "type") {
            #expect(extractEnumValues(from: typeSchema) == Set(ContainerInfo.ContainerTypeName.allCases.map(\.rawValue)))
        } else {
            Issue.record("get_interface.subtree.container.type missing enum schema")
        }

        let scroll = ToolDefinitions.all.first { $0.name == TheFence.Command.scroll.rawValue }
        #expect(extractEnumValues(from: scroll, property: "mode") == Set(ScrollMode.allCases.map(\.rawValue)))
        #expect(extractEnumValues(from: scroll, property: "direction") == Set(ScrollDirection.allCases.map(\.rawValue)))
        #expect(extractEnumValues(from: scroll, property: "edge") == Set(ScrollEdge.allCases.map(\.rawValue)))

        let gesture = ToolDefinitions.all.first { $0.name == TheFence.Command.gestureMCPToolName }
        #expect(extractEnumValues(from: gesture, property: "type") == Set(GestureType.allCases.map(\.rawValue)))

        let editAction = ToolDefinitions.all.first { $0.name == TheFence.Command.editAction.rawValue }
        #expect(
            extractEnumValues(from: editAction, property: "action") ==
                Set(EditAction.allCases.map(\.rawValue) + ["dismiss"])
        )
    }

    @Test("Scroll modes dispatch through command catalog names")
    func scrollModesDispatchThroughCommandCatalogNames() {
        let expectedCommands: [ScrollMode: TheFence.Command] = [
            .page: .scroll,
            .toVisible: .scrollToVisible,
            .search: .elementSearch,
            .toEdge: .scrollToEdge,
        ]

        for (mode, command) in expectedCommands {
            #expect(mode.canonicalCommand == command.rawValue)
        }
    }

    @Test("get_interface schema does not expose diagnostic screen scope")
    func getInterfaceSchemaDoesNotExposeDiagnosticScreenScope() {
        guard let getInterface = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.getInterface.rawValue }) else {
            Issue.record("get_interface tool missing")
            return
        }

        #expect(!extractPropertyKeys(from: getInterface).contains("scope"))
    }

    @Test("get_interface MCP description presents app state and subtree projection")
    func getInterfaceMCPDescriptionPresentsAppStateAndSubtreeProjection() {
        guard let getInterface = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.getInterface.rawValue }) else {
            Issue.record("get_interface tool missing")
            return
        }

        let description = getInterface.description ?? ""
        #expect(description.contains("Omit subtree for the whole hierarchy"))
        #expect(description.contains("project the returned tree"))
        #expect(description.contains("app accessibility hierarchy"))
        #expect(!description.localizedCaseInsensitiveContains("scope=visible"))
        #expect(!description.contains("diagnostic on-screen reads"))
        #expect(!description.localizedCaseInsensitiveContains("viewport"))
    }

    @Test("get_interface subtree schema describes projection without viewport language")
    func getInterfaceSubtreeSchemaDescribesProjectionWithoutViewportLanguage() {
        guard let getInterface = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.getInterface.rawValue }),
              let subtreeSchema = extractPropertySchema(from: getInterface, property: "subtree"),
              let subtreeProperties = extractObjectField(from: subtreeSchema, key: "properties") else {
            Issue.record("get_interface.subtree missing property schema")
            return
        }

        #expect(extractStringField(from: subtreeSchema, key: "type") == "object")
        #expect(
            extractPropertyKeys(from: subtreeSchema) == ["element", "container", "ordinal"]
        )
        #expect(extractStringField(from: subtreeSchema, key: "description")?.contains("Subtree selector") == true)
        #expect(extractStringField(from: subtreeSchema, key: "description")?.contains("whole tree") == true)
        #expect(!((extractStringField(from: subtreeSchema, key: "description") ?? "").localizedCaseInsensitiveContains("viewport")))
        guard case .object(let elementSchema)? = subtreeProperties["element"],
              case .object(let containerSchema)? = subtreeProperties["container"] else {
            Issue.record("get_interface.subtree element/container schemas missing")
            return
        }
        #expect(extractPropertyKeys(from: elementSchema) == ["heistId", "label", "value", "identifier", "traits", "excludeTraits"])
        #expect(extractPropertyKeys(from: containerSchema) == ["stableId", "type", "label", "value", "identifier", "isModalBoundary"])
        guard let containerProperties = extractObjectField(from: containerSchema, key: "properties") else {
            Issue.record("get_interface.subtree.container missing properties")
            return
        }
        if case .object(let stableIdSchema)? = containerProperties["stableId"] {
            #expect(extractStringField(from: stableIdSchema, key: "type") == "string")
        } else {
            Issue.record("get_interface.subtree.container.stableId missing schema")
        }
        if case .object(let modalSchema)? = containerProperties["isModalBoundary"] {
            #expect(extractStringField(from: modalSchema, key: "type") == "boolean")
        } else {
            Issue.record("get_interface.subtree.container.isModalBoundary missing schema")
        }
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

    @Test("run_batch step command schema advertises canonical Fence commands only")
    func runBatchStepCommandSchemaAdvertisesCanonicalFenceCommandsOnly() {
        guard let runBatch = ToolDefinitions.all.first(where: { $0.name == "run_batch" }),
              let stepsSchema = extractPropertySchema(from: runBatch, property: "steps"),
              let stepItemsSchema = extractObjectField(from: stepsSchema, key: "items"),
              let stepProperties = extractObjectField(from: stepItemsSchema, key: "properties"),
              let commandSchemaValue = stepProperties["command"],
              case .object(let commandSchema) = commandSchemaValue else {
            Issue.record("run_batch.steps.items.command schema missing")
            return
        }

        let commandValues = extractEnumValues(from: commandSchema)
        #expect(commandValues == Set(TheFence.Command.batchExecutableCases.map(\.rawValue)))
        #expect(!commandValues.contains(TheFence.Command.help.rawValue))
        #expect(!commandValues.contains(TheFence.Command.status.rawValue))
        #expect(!commandValues.contains(TheFence.Command.quit.rawValue))
        #expect(!commandValues.contains(TheFence.Command.exit.rawValue))
        #expect(!commandValues.contains(TheFence.Command.runBatch.rawValue))
        #expect(!commandValues.contains(TheFence.Command.gestureMCPToolName))
    }

    @Test("Expect schemas are projected from FenceParameterSpec")
    func expectSchemasAreProjectedFromFenceParameterSpec() {
        guard let expectSpec = TheFence.Command.activate.parameters.first(where: { $0.key == "expect" }) else {
            Issue.record("activate command is missing expect parameter spec")
            return
        }
        #expect(
            Set(expectSpec.objectProperties.map(\.key)) == [
                "type", "heistId", "property", "oldValue", "newValue", "matcher", "expectations",
            ],
            "FenceParameterSpec should own the expect object shape"
        )

        let projectedSchema = ToolDefinitions.schemaProperty(for: expectSpec)
        for tool in ToolDefinitions.all where extractPropertyKeys(from: tool).contains("expect") {
            guard let actualSchema = extractPropertySchema(from: tool, property: "expect") else {
                Issue.record("\(tool.name) is missing expect property schema")
                continue
            }
            #expect(
                Value.object(actualSchema) == projectedSchema,
                "\(tool.name).expect should be projected from FenceParameterSpec"
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

    @Test("type_text schema requires non-empty text")
    func typeTextSchemaRequiresNonEmptyText() {
        guard let typeText = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.typeText.rawValue }),
              let textSchema = extractPropertySchema(from: typeText, property: "text") else {
            Issue.record("type_text is missing text schema")
            return
        }

        #expect(extractIntField(from: textSchema, key: "minLength") == 1)
        #expect(extractRequiredKeys(from: typeText).contains("text"))
        #expect(extractPropertySchema(from: typeText, property: "deleteCount") == nil)
        #expect(extractPropertySchema(from: typeText, property: "clearFirst") == nil)
    }

    // MARK: - Exhaustiveness

    @Test("MCP property schemas match enriched FenceParameterSpec metadata")
    func mcpPropertySchemasMatchFenceParameterSpecMetadata() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        for command in TheFence.Command.allCases where command.mcpExposure == .directTool {
            guard !Self.hybridToolNames.contains(command.rawValue) else { continue }
            guard let tool = toolsByName[command.rawValue] else { continue }
            assertPropertySchemas(command.parameters, match: tool, enumPolicy: .exact)
        }

        if let gesture = toolsByName[TheFence.Command.gestureMCPToolName] {
            assertPropertySchemas(
                groupedCommands(under: TheFence.Command.gestureMCPToolName).flatMap(\.parameters),
                match: gesture,
                enumPolicy: .exact
            )
        }
        if let scroll = toolsByName[TheFence.Command.scroll.rawValue] {
            assertPropertySchemas(
                ([.scroll] + groupedCommands(under: TheFence.Command.scroll.rawValue)).flatMap(\.parameters),
                match: scroll,
                enumPolicy: .schemaMayBeSuperset
            )
        }
        if let editAction = toolsByName[TheFence.Command.editAction.rawValue] {
            assertPropertySchemas(TheFence.Command.editAction.parameters, match: editAction, enumPolicy: .schemaMayBeSuperset)
        }
    }

    @Test("MCP tool schemas are rendered from canonical tool contracts")
    func mcpToolSchemasAreRenderedFromCanonicalToolContracts() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })
        let contracts = TheFence.Command.mcpToolContracts

        #expect(Set(toolsByName.keys) == Set(contracts.map(\.name)))

        for contract in contracts {
            guard let tool = toolsByName[contract.name] else {
                Issue.record("Missing rendered MCP tool for contract \(contract.name)")
                continue
            }
            #expect(
                tool.inputSchema == ToolDefinitions.inputSchema(for: contract),
                "\(contract.name) input schema should be rendered from MCPToolContract"
            )
        }
    }

    @Test("MCP adapter source does not mirror Fence command or parameter literals")
    func mcpAdapterSourceDoesNotMirrorFenceCatalogLiterals() throws {
        let source = try readRepositoryFile("ButtonHeistMCP/Sources/ToolDefinitions.swift")

        let sourceWithoutContractRoot = source.replacingOccurrences(of: "TheFence.Command.mcpToolContracts", with: "")
        #expect(
            !sourceWithoutContractRoot.contains("TheFence.Command."),
            "ToolDefinitions.swift should render from MCPToolContract instead of referencing command cases"
        )
        #expect(
            !source.contains(".rawValue"),
            "ToolDefinitions.swift should not render command names through rawValue references"
        )

        let sourceForLiteralScan = Self.removingLineComments(from: source)
        let literalCounts = Self.stringLiteralCounts(in: sourceForLiteralScan)
        for (literal, expectedCount) in Self.expectedSchemaRendererCatalogLiteralCounts {
            #expect(
                literalCounts[literal] == expectedCount,
                """
                ToolDefinitions.swift contains \(literalCounts[literal] ?? 0) occurrences of the \
                catalog literal \(literal), expected \(expectedCount) schema-renderer occurrences
                """
            )
        }

        let literalMirrors = Set(literalCounts.keys)
            .intersection(Self.fenceCatalogLiterals)
            .subtracting(Self.allowedSchemaRendererLiterals)
        #expect(
            literalMirrors.isEmpty,
            "ToolDefinitions.swift should render command/parameter names from Fence specs, not mirror literals: \(literalMirrors.sorted())"
        )
    }

    @Test("FenceParameterKey covers every advertised command parameter")
    func fenceParameterKeyCoversEveryAdvertisedCommandParameter() {
        let advertisedKeys = Self.fenceCatalogLiterals
            .subtracting(TheFence.Command.allCases.map(\.rawValue))
            .subtracting(TheFence.Command.mcpToolContracts.map(\.name))
        let knownKeys = Set(FenceParameterKey.allCases.map(\.rawValue))
        let missingKeys = advertisedKeys.subtracting(knownKeys)

        #expect(
            missingKeys.isEmpty,
            "FenceParameterKey is missing advertised parameter keys: \(missingKeys.sorted())"
        )
    }

    @Test("Grouped MCP selectors are owned by command contracts")
    func groupedMCPSelectorsAreOwnedByCommandContracts() {
        assertSelectorContract(
            toolName: TheFence.Command.gestureMCPToolName,
            key: "type",
            requiredKeys: ["type"],
            enumValues: GestureType.allCases.map(\.rawValue)
        )
        assertSelectorContract(
            toolName: TheFence.Command.scroll.rawValue,
            key: "mode",
            requiredKeys: [],
            enumValues: ScrollMode.allCases.map(\.rawValue)
        )
        assertSelectorContract(
            toolName: TheFence.Command.editAction.rawValue,
            key: "action",
            requiredKeys: ["action"],
            enumValues: EditAction.allCases.map(\.rawValue) + ["dismiss"]
        )
    }

    @Test("Tool input schemas satisfy canonical schema lint in memory")
    func toolInputSchemasSatisfyCanonicalSchemaLintInMemory() {
        let violations = ToolSchemaLint.violations(in: ToolDefinitions.all)
        #expect(
            violations.isEmpty,
            "Tool input schema lint violations:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Serialized ListTools JSON satisfies canonical schema lint")
    func serializedListToolsJSONSatisfiesCanonicalSchemaLint() throws {
        let data = try JSONEncoder().encode(ListTools.Result(tools: ToolDefinitions.all))
        let violations = try ToolSchemaLint.violationsInSerializedListToolsJSON(data)
        #expect(
            violations.isEmpty,
            "Serialized ListTools schema lint violations:\n\(violations.joined(separator: "\n"))"
        )
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

    @Test("Every MCP tool contract has an explicit description")
    func everyMCPToolContractHasExplicitDescription() {
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })
        for contract in TheFence.Command.mcpToolContracts {
            #expect(
                !contract.description.hasPrefix("Execute the"),
                "\(contract.name) is using the generic description fallback"
            )
            #expect(
                toolsByName[contract.name]?.description == contract.description,
                "\(contract.name) rendered description should come from MCPToolContract"
            )
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
        let docsOnly = documentedTools.subtracting(actualTools).sorted()
        let missing = actualTools.subtracting(documentedTools).sorted()

        #expect(
            documentedTools == actualTools,
            "MCP README tool list differs: docs-only \(docsOnly), missing \(missing)"
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

    private static let allowedSchemaRendererLiterals: Set<String> = [
        "additionalProperties",
        "array",
        "boolean",
        "description",
        "enum",
        "integer",
        "items",
        "maximum",
        "minimum",
        "minLength",
        "number",
        "object",
        "properties",
        "required",
        "string",
        "type",
    ]

    private static let expectedSchemaRendererCatalogLiteralCounts: [String: Int] = [
        "type": 5,
    ]

    private static var fenceCatalogLiterals: Set<String> {
        var literals = Set(TheFence.Command.allCases.map(\.rawValue))
        literals.formUnion(TheFence.Command.mcpToolContracts.map(\.name))

        for command in TheFence.Command.allCases {
            collectParameterKeys(from: command.parameters, into: &literals)
        }
        for contract in TheFence.Command.mcpToolContracts {
            if let selector = contract.selector {
                collectParameterKeys(from: [selector.parameter], into: &literals)
            }
        }

        return literals
    }

    private static func collectParameterKeys(
        from specs: [FenceParameterSpec],
        into literals: inout Set<String>
    ) {
        for spec in specs {
            literals.insert(spec.key)
            collectParameterKeys(from: spec.objectProperties, into: &literals)
            collectParameterKeys(from: spec.arrayItemProperties, into: &literals)
        }
    }

    private static func removingLineComments(from source: String) -> String {
        source.replacingOccurrences(of: #"//.*"#, with: "", options: .regularExpression)
    }

    private static func stringLiterals(in source: String) -> Set<String> {
        Set(stringLiteralCounts(in: source).keys)
    }

    private static func stringLiteralCounts(in source: String) -> [String: Int] {
        guard let regex = try? NSRegularExpression(pattern: #""((?:\\.|[^"\\])*)""#) else {
            return [:]
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let literals: [String] = regex.matches(in: source, range: range).compactMap { match in
            guard let literalRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[literalRange])
        }
        return Dictionary(literals.map { ($0, 1) }, uniquingKeysWith: +)
    }

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

    @Test("get_interface MCP schema does not advertise legacy full mode")
    func getInterfaceSchemaDoesNotAdvertiseLegacyFullMode() {
        guard let getInterface = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.getInterface.rawValue }) else {
            Issue.record("get_interface tool missing")
            return
        }

        let propertyKeys = extractPropertyKeys(from: getInterface)
        #expect(!propertyKeys.contains("scope"))
        #expect(!propertyKeys.contains("full"))
    }

    private enum EnumPolicy {
        case exact
        case schemaMayBeSuperset
    }

    private func groupedCommands(under toolName: String) -> [TheFence.Command] {
        TheFence.Command.allCases.filter {
            if case .groupedUnder(let groupedToolName) = $0.mcpExposure {
                return groupedToolName == toolName
            }
            return false
        }
    }

    private func assertPropertySchemas(
        _ specs: [FenceParameterSpec],
        match tool: Tool,
        enumPolicy: EnumPolicy
    ) {
        guard case .object(let rootSchema) = tool.inputSchema,
              let properties = extractObjectField(from: rootSchema, key: "properties") else {
            Issue.record("\(tool.name) missing root properties")
            return
        }

        for spec in specs {
            guard let propertySchema = properties[spec.key],
                  case .object(let schema) = propertySchema else {
                Issue.record("\(tool.name).\(spec.key) missing property schema")
                continue
            }
            assertPropertySchema(schema, matches: spec, context: "\(tool.name).\(spec.key)", enumPolicy: enumPolicy)
        }
    }

    private func assertPropertySchema(
        _ schema: [String: Value],
        matches spec: FenceParameterSpec,
        context: String,
        enumPolicy: EnumPolicy
    ) {
        #expect(
            extractStringField(from: schema, key: "type") == ToolDefinitions.schemaType(for: spec.type),
            "\(context) type should match FenceParameterSpec"
        )

        if let expectedEnumValues = spec.enumValues {
            let expected = Set(expectedEnumValues)
            let actual = extractEnumValues(from: schema)
            switch enumPolicy {
            case .exact:
                #expect(actual == expected, "\(context) enum should match FenceParameterSpec")
            case .schemaMayBeSuperset:
                #expect(actual.isSuperset(of: expected), "\(context) enum should include FenceParameterSpec values")
            }
        }

        if let minimum = spec.minimum {
            #expect(extractNumberField(from: schema, key: "minimum") == minimum, "\(context) minimum should match FenceParameterSpec")
        }
        if let maximum = spec.maximum {
            #expect(extractNumberField(from: schema, key: "maximum") == maximum, "\(context) maximum should match FenceParameterSpec")
        }
        if let minLength = spec.minLength {
            #expect(extractIntField(from: schema, key: "minLength") == minLength, "\(context) minLength should match FenceParameterSpec")
        }

        if spec.type == .stringArray {
            guard let items = extractObjectField(from: schema, key: "items") else {
                Issue.record("\(context) missing array item schema")
                return
            }
            #expect(extractStringField(from: items, key: "type") == "string", "\(context) should be an array of strings")
        }

        if !spec.objectProperties.isEmpty {
            assertObjectShape(
                schema,
                properties: spec.objectProperties,
                additionalProperties: spec.objectAdditionalProperties,
                context: context,
                enumPolicy: enumPolicy
            )
        }

        if let arrayItemType = spec.arrayItemType {
            guard let items = extractObjectField(from: schema, key: "items") else {
                Issue.record("\(context) missing array item schema")
                return
            }
            #expect(
                extractStringField(from: items, key: "type") == ToolDefinitions.schemaType(for: arrayItemType),
                "\(context) array item type should match FenceParameterSpec"
            )
            if arrayItemType == .object {
                assertObjectShape(
                    items,
                    properties: spec.arrayItemProperties,
                    additionalProperties: spec.arrayItemAdditionalProperties,
                    context: "\(context).items",
                    enumPolicy: enumPolicy
                )
            }
        }
    }

    private func assertObjectShape(
        _ schema: [String: Value],
        properties expectedProperties: [FenceParameterSpec],
        additionalProperties expectedAdditionalProperties: Bool,
        context: String,
        enumPolicy: EnumPolicy
    ) {
        guard let properties = extractObjectField(from: schema, key: "properties") else {
            Issue.record("\(context) missing object properties")
            return
        }
        let expectedKeys = Set(expectedProperties.map(\.key))
        #expect(Set(properties.keys) == expectedKeys, "\(context) object properties should match FenceParameterSpec")
        #expect(extractRequiredKeys(from: schema) == Set(expectedProperties.filter(\.required).map(\.key)))
        #expect(extractBoolField(from: schema, key: "additionalProperties") == expectedAdditionalProperties)

        for nestedSpec in expectedProperties {
            guard let nestedValue = properties[nestedSpec.key],
                  case .object(let nestedSchema) = nestedValue else {
                Issue.record("\(context).\(nestedSpec.key) missing nested property schema")
                continue
            }
            assertPropertySchema(
                nestedSchema,
                matches: nestedSpec,
                context: "\(context).\(nestedSpec.key)",
                enumPolicy: enumPolicy
            )
        }
    }

    private func assertSelectorContract(
        toolName: String,
        key: String,
        requiredKeys: Set<String>,
        enumValues: [String]
    ) {
        guard let contract = TheFence.Command.mcpToolContract(named: toolName),
              let selector = contract.selector else {
            Issue.record("\(toolName) missing selector contract")
            return
        }
        guard let tool = ToolDefinitions.all.first(where: { $0.name == toolName }) else {
            Issue.record("\(toolName) missing rendered MCP tool")
            return
        }

        #expect(selector.parameter.key == key)
        #expect(Set(contract.requiredParameterKeys) == requiredKeys)
        #expect(selector.parameter.enumValues == enumValues)
        #expect(extractEnumValues(from: tool, property: key) == Set(enumValues))
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

    private func extractStringField(from schema: [String: Value], key: String) -> String? {
        guard let value = schema[key],
              case .string(let string) = value else {
            return nil
        }
        return string
    }

    private func extractBoolField(from schema: [String: Value], key: String) -> Bool? {
        guard let value = schema[key],
              case .bool(let bool) = value else {
            return nil
        }
        return bool
    }

    private func extractIntField(from schema: [String: Value], key: String) -> Int? {
        guard let value = schema[key],
              case .int(let int) = value else {
            return nil
        }
        return int
    }

    private func extractNumberField(from schema: [String: Value], key: String) -> Double? {
        guard let value = schema[key] else { return nil }
        switch value {
        case .int(let int):
            return Double(int)
        case .double(let double):
            return double
        default:
            return nil
        }
    }
}

private enum ToolSchemaLint {
    private static let unsupportedCompositionKeys: Set<String> = ["oneOf", "allOf", "anyOf"]

    static func violations(in tools: [Tool]) -> [String] {
        tools.flatMap { tool in
            lintRootSchema(tool.inputSchema, path: "\(tool.name).inputSchema")
        }
    }

    static func violationsInSerializedListToolsJSON(_ data: Data) throws -> [String] {
        let listToolsJSON = try JSONDecoder().decode(Value.self, from: data)
        guard case .object(let root) = listToolsJSON,
              let toolsValue = root["tools"],
              case .array(let tools) = toolsValue else {
            return ["$.tools missing from serialized ListTools JSON"]
        }

        return tools.enumerated().flatMap { index, toolValue in
            guard case .object(let toolObject) = toolValue else {
                return ["$.tools[\(index)] is not an object"]
            }
            let name = toolObject["name"]?.stringValue ?? "$.tools[\(index)]"
            guard let inputSchema = toolObject["inputSchema"] else {
                return ["\(name).inputSchema missing from serialized ListTools JSON"]
            }
            return lintRootSchema(inputSchema, path: "\(name).inputSchema")
        }
    }

    private static func lintRootSchema(_ schema: Value, path: String) -> [String] {
        guard case .object(let object) = schema else {
            return ["\(path) root schema is not an object"]
        }

        var violations: [String] = []
        if object["additionalProperties"] != .bool(false) {
            violations.append("\(path) root schema must set additionalProperties: false")
        }
        violations += lint(schema, path: path)
        return violations
    }

    private static func lint(_ value: Value, path: String) -> [String] {
        switch value {
        case .object(let object):
            var violations: [String] = []

            for key in object.keys where unsupportedCompositionKeys.contains(key) {
                violations.append("\(path).\(key) uses unsupported JSON Schema composition")
            }

            if let typeValue = object["type"] {
                if case .array = typeValue {
                    violations.append("\(path).type is an array-valued JSON Schema type")
                }
                if typeValue == .string("array"), object["items"] == nil {
                    violations.append("\(path) is an array schema without items")
                }
            }

            if let requiredValue = object["required"] {
                guard case .array(let requiredItems) = requiredValue else {
                    violations.append("\(path).required is not an array")
                    return violations + lintNestedValues(in: object, path: path)
                }

                var requiredKeys: [String] = []
                for (index, item) in requiredItems.enumerated() {
                    guard case .string(let key) = item else {
                        violations.append("\(path).required[\(index)] is not a string")
                        continue
                    }
                    requiredKeys.append(key)
                }

                let uniqueRequiredKeys = Set(requiredKeys)
                if uniqueRequiredKeys.count != requiredKeys.count {
                    violations.append("\(path).required contains duplicate keys")
                }

                guard let propertiesValue = object["properties"],
                      case .object(let properties) = propertiesValue else {
                    violations.append("\(path).required is present without object properties")
                    return violations + lintNestedValues(in: object, path: path)
                }

                for key in uniqueRequiredKeys where properties[key] == nil {
                    violations.append("\(path).required contains key '\(key)' not present in properties")
                }
            }

            return violations + lintNestedValues(in: object, path: path)

        case .array(let values):
            return values.enumerated().flatMap { index, nestedValue in
                lint(nestedValue, path: "\(path)[\(index)]")
            }

        default:
            return []
        }
    }

    private static func lintNestedValues(in object: [String: Value], path: String) -> [String] {
        object.flatMap { key, nestedValue in
            lint(nestedValue, path: "\(path).\(key)")
        }
    }
}
