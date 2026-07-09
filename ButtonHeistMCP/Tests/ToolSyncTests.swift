import Testing
import MCP
import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist
@testable import ButtonHeistMCP

struct ToolSyncTests {
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

    @Test("MCP tool surface stays source-oriented")
    func mcpToolSurfaceStaysSourceOriented() {
        let expected = [
            "connect",
            "describe_heist",
            "get_announcements",
            "get_interface",
            "get_pasteboard",
            "get_screen",
            "get_session_state",
            "list_heists",
            "perform",
            "run_heist",
        ].sorted()

        #expect(ToolDefinitions.all.map(\.name).sorted() == expected)
    }

    @Test("StringMatch command schemas advertise object form without combinators")
    func stringMatchCommandSchemasAdvertiseObjectFormWithoutCombinators() throws {
        let removedFlatFields = ["label", "identifier", "value"]
        let schemaCases: [(command: TheFence.Command, basePath: [String], label: String)] = [
            (.activate, ["properties", "target", "properties"], "target"),
            (.oneFingerTap, ["properties", "element", "properties"], "gesture element"),
            (.wait, ["properties", "predicate", "properties", "element", "properties"], "wait.predicate.element"),
            (.activate, ["properties", "expect", "properties", "element", "properties"], "expect.element"),
            (.getInterface, ["properties"], "get_interface matcher"),
            (.getInterface, ["properties", "subtree", "properties", "element", "properties"], "subtree.element"),
        ]

        for schemaCase in schemaCases {
            let inputSchema = try inputSchemaValue(for: schemaCase.command)
            for field in removedFlatFields {
                #expect(
                    schemaValue(at: schemaCase.basePath + [field], in: inputSchema) == nil,
                    "\(schemaCase.command.rawValue) \(schemaCase.label).\(field) must not expose flat matcher aliases"
                )
            }

            let checksPath = schemaCase.basePath + ["checks"]
            let checksSchema = try #require(
                schemaValue(at: checksPath, in: inputSchema),
                "\(schemaCase.command.rawValue) \(schemaCase.label).checks missing from input schema"
            )
            #expect(checksSchema.objectValue?["type"] == .string("array"))
            #expect(
                schemaValue(at: checksPath + ["items", "properties", "kind", "enum"], in: inputSchema) == .array([
                    .string("label"),
                    .string("identifier"),
                    .string("value"),
                    .string("hint"),
                    .string("traits"),
                    .string("actions"),
                    .string("customContent"),
                    .string("rotors"),
                    .string("exclude"),
                ])
            )
            let matchSchema = try #require(
                schemaValue(at: checksPath + ["items", "properties", "match"], in: inputSchema),
                "\(schemaCase.command.rawValue) \(schemaCase.label).checks[].match missing from input schema"
            )
            assertStringMatchSchema(
                matchSchema,
                path: "\(schemaCase.command.rawValue).inputSchema.\((checksPath + ["items", "properties", "match"]).joined(separator: "."))"
            )
        }
    }

    @Test("get_interface subtree container is an object-only predicate")
    func getInterfaceSubtreeContainerSchemaIsObjectOnly() throws {
        let tool = try #require(ToolDefinitions.all.first { $0.name == "get_interface" })
        let containerPath = ["properties", "subtree", "properties", "container"]
        let container = try #require(schemaValue(at: containerPath, in: tool.inputSchema))

        #expect(container.objectValue?["type"] == .string("object"))

        let properties = try #require(schemaValue(at: containerPath + ["properties"], in: tool.inputSchema)?.objectValue)
        #expect(properties["containerName"] == nil)
        #expect(properties["checks"] != nil)
        #expect(
            schemaValue(at: containerPath + ["properties", "checks", "items", "properties", "kind", "enum"], in: tool.inputSchema) == .array([
                .string("type"),
                .string("semantic"),
                .string("rowCount"),
                .string("columnCount"),
                .string("modalBoundary"),
                .string("scrollable"),
                .string("actions"),
            ])
        )

        // No schema combinator anywhere under the container subschema.
        #expect(schemaValue(at: containerPath + ["oneOf"], in: tool.inputSchema) == nil)
        #expect(schemaValue(at: containerPath + ["anyOf"], in: tool.inputSchema) == nil)
        #expect(schemaValue(at: containerPath + ["allOf"], in: tool.inputSchema) == nil)
        #expect(SchemaCombinatorScanner.combinatorPaths(in: container, path: "container").isEmpty)
    }

    @Test("get_interface schema exposes bounded discovery limits")
    func getInterfaceSchemaExposesBoundedDiscoveryLimits() throws {
        let tool = try #require(ToolDefinitions.all.first { $0.name == "get_interface" })
        for field in ["maxScrollsPerContainer", "maxScrollsPerDiscovery"] {
            let schema = try #require(
                schemaValue(at: ["properties", field], in: tool.inputSchema)?.objectValue,
                "get_interface missing \(field)"
            )
            #expect(schema["type"] == .string("integer"))
            #expect(schema["minimum"] == .int(1))
            #expect(schema["maximum"] == .int(2_000))
        }
    }

    @Test("No MCP tool input schema contains a combinator at any depth")
    func noToolSchemaContainsCombinatorAtAnyDepth() {
        let offending = ToolDefinitions.all.flatMap { tool in
            SchemaCombinatorScanner.combinatorPaths(
                in: tool.inputSchema,
                path: "\(tool.name).inputSchema"
            )
        }
        #expect(
            offending.isEmpty,
            "MCP tool input schemas must not advertise oneOf/anyOf/allOf:\n\(offending.joined(separator: "\n"))"
        )
    }

    @Test("No generated MCP tool input schema has a top-level combinator")
    func noGeneratedToolSchemaHasTopLevelCombinator() {
        let offending = ToolDefinitions.all.flatMap { tool -> [String] in
            guard case .object(let schema) = tool.inputSchema else {
                return ["\(tool.name).inputSchema is not an object"]
            }
            return SchemaCombinatorScanner.bannedKeywords.compactMap { keyword in
                schema[keyword] == nil ? nil : "\(tool.name).inputSchema.\(keyword)"
            }
        }

        #expect(
            offending.isEmpty,
            "MCP tool input schemas must not use top-level oneOf/anyOf/allOf:\n\(offending.joined(separator: "\n"))"
        )
    }

    @Test("run_heist schema exposes plan sources and root argument without schema combinators")
    func runHeistSchemaExposesOnlyPlan() throws {
        let tool = try #require(ToolDefinitions.all.first { $0.name == "run_heist" })

        // The MCP run_heist tool exposes only public authoring sources:
        // canonical ButtonHeist source, .heist artifact path, and root
        // argument. Raw JSON IR fields remain internal and are not advertised.
        for field in ["path", "plan", "argument"] {
            #expect(
                schemaValue(at: ["properties", field], in: tool.inputSchema) != nil,
                "run_heist schema must expose \(field)"
            )
        }
        for field in ["version", "name", "parameter", "definitions", "body"] {
            #expect(
                schemaValue(at: ["properties", field], in: tool.inputSchema) == nil,
                "run_heist schema must not expose raw JSON IR field \(field)"
            )
        }
        #expect(schemaValue(at: ["properties", "argument", "properties", "type", "enum"], in: tool.inputSchema) == .array([
            .string("none"),
            .string("string"),
            .string("element_target"),
        ]))
        #expect(
            schemaValue(at: ["properties", "argument", "properties", "target", "additionalProperties"], in: tool.inputSchema)
                == .bool(false)
        )
        #expect(schemaValue(at: ["properties", "argument", "properties", "target", "properties", "checks"], in: tool.inputSchema) != nil)
        #expect(schemaValue(at: ["properties", "argument", "properties", "target", "properties", "label"], in: tool.inputSchema) == nil)
        #expect(schemaValue(at: ["properties", "argument", "properties", "target", "properties", "unexpected"], in: tool.inputSchema) == nil)

        #expect(schemaValue(at: ["oneOf"], in: tool.inputSchema) == nil)
        #expect(schemaValue(at: ["anyOf"], in: tool.inputSchema) == nil)
        #expect(schemaValue(at: ["allOf"], in: tool.inputSchema) == nil)
    }

    @Test("perform schema exposes one step source without plan IR")
    func performSchemaExposesOneStepSourceWithoutPlanIR() throws {
        let tool = try #require(ToolDefinitions.all.first { $0.name == "perform" })

        #expect(schemaValue(at: ["properties", "step"], in: tool.inputSchema) != nil)
        #expect(schemaValue(at: ["required"], in: tool.inputSchema) == .array([.string("step")]))
        for field in ["source", "path", "plan", "version", "name", "parameter", "definitions", "body"] {
            #expect(
                schemaValue(at: ["properties", field], in: tool.inputSchema) == nil,
                "perform schema must not expose \(field)"
            )
        }
        #expect(schemaValue(at: ["oneOf"], in: tool.inputSchema) == nil)
        #expect(schemaValue(at: ["anyOf"], in: tool.inputSchema) == nil)
        #expect(schemaValue(at: ["allOf"], in: tool.inputSchema) == nil)
    }

    @Test("heist discovery schemas expose validated plan source without top-level combinators")
    func heistDiscoverySchemasExposePlanSourceWithoutTopLevelCombinators() throws {
        let listHeists = try #require(ToolDefinitions.all.first { $0.name == "list_heists" })
        let describeHeist = try #require(ToolDefinitions.all.first { $0.name == "describe_heist" })

        for tool in [listHeists, describeHeist] {
            for field in ["path", "plan"] {
                #expect(
                    schemaValue(at: ["properties", field], in: tool.inputSchema) != nil,
                    "\(tool.name) schema must expose \(field)"
                )
            }
            for field in ["version", "name", "parameter", "definitions", "body"] {
                #expect(
                    schemaValue(at: ["properties", field], in: tool.inputSchema) == nil,
                    "\(tool.name) schema must not expose raw JSON IR field \(field)"
                )
            }
            #expect(schemaValue(at: ["oneOf"], in: tool.inputSchema) == nil)
            #expect(schemaValue(at: ["anyOf"], in: tool.inputSchema) == nil)
            #expect(schemaValue(at: ["allOf"], in: tool.inputSchema) == nil)
        }

        #expect(schemaValue(at: ["properties", "heist"], in: describeHeist.inputSchema) != nil)
        #expect(schemaValue(at: ["required"], in: describeHeist.inputSchema) == .array([.string("heist")]))
        #expect(schemaValue(at: ["properties", "heist"], in: listHeists.inputSchema) == nil)
        #expect(schemaValue(at: ["properties", "detail", "enum"], in: listHeists.inputSchema) == .array([
            .string("summary"),
            .string("detailed"),
        ]))
        #expect(schemaValue(at: ["properties", "detail", "default"], in: listHeists.inputSchema) == .string("summary"))
    }
}

private func schemaValue(at path: [String], in root: Value) -> Value? {
    path.reduce(Optional(root)) { value, key in
        value?.objectValue?[key]
    }
}

private func inputSchemaValue(for command: TheFence.Command) throws -> Value {
    let data = try JSONEncoder().encode(command.descriptor.inputJSONSchema)
    return try JSONDecoder().decode(Value.self, from: data)
}

private func assertStringMatchSchema(_ schema: Value, path: String) {
    let object = schema.objectValue
    #expect(object?["type"] == .string("object"), "\(path) must advertise object-form StringMatch")
    #expect(object?["additionalProperties"] == .bool(false), "\(path) must close object-form StringMatch fields")
    #expect(object?["required"] == .array([.string("mode")]), "\(path) must require mode in object form")
    #expect(object?["description"]?.stringValue?.contains("mode exact") == true, "\(path) should describe exact matching through object-form StringMatch")
    #expect(
        object?["properties"]?.objectValue?["mode"] == .object([
            "type": .string("string"),
            "enum": .array([
                .string("exact"),
                .string("contains"),
                .string("prefix"),
                .string("suffix"),
                .string("isEmpty"),
            ]),
        ]),
        "\(path).properties.mode must enumerate StringMatch modes"
    )
    #expect(
        object?["properties"]?.objectValue?["value"] == .object(["type": .string("string")]),
        "\(path).properties.value must be a string"
    )
    #expect(
        SchemaCombinatorScanner.combinatorPaths(in: schema, path: path).isEmpty,
        "\(path) must not use oneOf/anyOf/allOf for StringMatch"
    )
}

private extension Value {
    var objectValue: [String: Value]? {
        guard case .object(let object) = self else { return nil }
        return object
    }
}

/// Recursively scans a JSON Schema value for banned combinator keywords,
/// returning the exact dotted path to each occurrence (e.g.
/// `get_interface.inputSchema.properties.subtree.properties.container.oneOf`).
private enum SchemaCombinatorScanner {
    static let bannedKeywords = ["oneOf", "anyOf", "allOf"]

    static func combinatorPaths(in value: Value, path: String) -> [String] {
        switch value {
        case .object(let object):
            var paths: [String] = []
            for keyword in bannedKeywords where object[keyword] != nil {
                paths.append("\(path).\(keyword)")
            }
            for (key, nestedValue) in object {
                paths += combinatorPaths(in: nestedValue, path: "\(path).\(key)")
            }
            return paths

        case .array(let values):
            return values.enumerated().flatMap { index, nestedValue in
                combinatorPaths(in: nestedValue, path: "\(path)[\(index)]")
            }

        default:
            return []
        }
    }
}

private enum ToolSchemaLint {
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

            // Schema combinators are banned entirely on the MCP surface — OpenAI
            // tool input schemas reject oneOf/anyOf/allOf at any depth.
            for combinator in SchemaCombinatorScanner.bannedKeywords where object[combinator] != nil {
                violations.append("\(path).\(combinator) is a forbidden JSON Schema combinator")
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
