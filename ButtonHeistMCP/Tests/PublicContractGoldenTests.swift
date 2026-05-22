import Foundation
import MCP
import Testing
@testable import ButtonHeistMCP
import ButtonHeist
import TheScore

struct PublicContractGoldenTests {

    @Test("MCP tool list/schema public contract golden")
    func mcpToolListSchemaPublicContractGolden() throws {
        let snapshot = try toolSurfaceSnapshot()
        let expected = #"{"selectedToolNames":["activate","get_screen","start_recording"],"tools":["# +
            #"{"inputSchema":{"additionalProperties":false,"properties":{"action":{"type":"string"},"# +
            #""count":{"maximum":100,"minimum":1,"type":"integer"},"# +
            #""expect":{"properties":{"type":{"enum":["delivery","screen_changed","elements_changed","element_updated","# +
            #""element_appeared","element_disappeared","compound"],"type":"string"}},"type":"object"},"# +
            #""heistId":{"type":"string"},"label":{"type":"string"}},"required":[],"type":"object"},"name":"activate"},"# +
            #"{"inputSchema":{"additionalProperties":false,"properties":{"includeInterface":{"type":"boolean"},"# +
            #""inlineData":{"type":"boolean"},"output":{"type":"string"}},"required":[],"type":"object"},"name":"get_screen"},"# +
            #"{"inputSchema":{"additionalProperties":false,"properties":{"fps":{"maximum":15,"minimum":1,"type":"integer"},"# +
            #""inactivity_timeout":{"type":"number"},"max_duration":{"type":"number"},"# +
            #""scale":{"maximum":1,"minimum":0.25,"type":"number"}},"required":[],"type":"object"},"name":"start_recording"}]}"#

        try assertGoldenJSON(
            snapshot,
            equals: expected
        )
    }

    @Test("Descriptor surface count golden")
    func descriptorSurfaceCountGolden() {
        let descriptors = TheFence.Command.descriptors
        let surface: [String: Int] = [
            "totalCommands": descriptors.count,
            "batchEligible": descriptors.filter(\.isBatchExecutable).count,
            "playbackEligible": descriptors.filter(\.isPlaybackExecutable).count,
            "heistRecordable": descriptors.filter(\.isHeistRecordable).count,
            "requiresConnection": descriptors.filter(\.requiresConnectionBeforeDispatch).count,
            "humanAliases": TheFence.Command.humanCommandAliases.count,
            "cliDirectCommands": descriptors.filter { descriptor in
                if case .directCommand = descriptor.cliExposure { return true }
                return false
            }.count,
            "cliGroupedCommands": descriptors.filter { descriptor in
                if case .groupedUnder = descriptor.cliExposure { return true }
                return false
            }.count,
            "cliSessionOnly": descriptors.filter { descriptor in
                if case .sessionOnly = descriptor.cliExposure { return true }
                return false
            }.count,
            "mcpDirectTools": descriptors.filter { $0.mcpExposure == .directTool }.count,
            "mcpGroupedCommands": descriptors.filter { descriptor in
                if case .groupedUnder = descriptor.mcpExposure { return true }
                return false
            }.count,
            "mcpNotExposed": descriptors.filter { $0.mcpExposure == .notExposed }.count,
            "mcpToolContracts": TheFence.Command.mcpToolContracts.count,
        ]
        let expected: [String: Int] = [
            "totalCommands": 44,
            "batchEligible": 24,
            "playbackEligible": 24,
            "heistRecordable": 24,
            "requiresConnection": 34,
            "humanAliases": 18,
            "cliDirectCommands": 37,
            "cliGroupedCommands": 3,
            "cliSessionOnly": 4,
            "mcpDirectTools": 24,
            "mcpGroupedCommands": 13,
            "mcpNotExposed": 7,
            "mcpToolContracts": 25,
        ]

        #expect(
            surface == expected,
            "Descriptor surface counts changed: \(surface)"
        )
    }

    @Test("MCP action failure rendering public contract golden")
    func mcpActionFailureRenderingPublicContractGolden() throws {
        let actionResult = ActionResult(
            success: false,
            method: .activate,
            message: "No element matching label \"Buy\"",
            errorKind: .elementNotFound
        )
        let result = ButtonHeistMCPServer.renderResponse(
            .action(result: actionResult),
            backgroundAccessibilityTraces: []
        )

        #expect(result.isError == true)
        #expect(textContents(result) == ["activate: error[elementNotFound]: No element matching label \"Buy\""])
    }

    @Test("MCP expanded recording rendering public contract golden")
    func mcpExpandedRecordingRenderingPublicContractGolden() throws {
        let payload = RecordingPayload(
            videoData: "dmlkZW8=",
            width: 390,
            height: 844,
            duration: 2.5,
            frameCount: 20,
            fps: 8,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 2.5),
            stopReason: .manual,
            interactionLog: [
                InteractionEvent(
                    timestamp: 0.25,
                    command: .activate(.matcher(ElementMatcher(label: "Buy"))),
                    result: ActionResult(success: true, method: .activate)
                ),
            ]
        )
        let response = FenceResponse.recordingExpanded(
            path: "/tmp/buttonheist-recording.mp4",
            payload: payload,
            options: RecordingResponseOptions(inlineData: true, includeInteractionLog: true)
        )
        let result = ButtonHeistMCPServer.renderResponse(response, backgroundAccessibilityTraces: [])
        let expectedText = #"{"duration":2.5,"fps":8,"frameCount":20,"height":844,"interactionCount":1,"# +
            #""interactionLog":[{"command":{"payload":{"label":"Buy"},"type":"activate"},"# +
            #""result":{"method":"activate","success":true},"timestamp":0.25}],"# +
            #""path":"\/tmp\/buttonheist-recording.mp4","status":"ok","stopReason":"manual","videoData":"dmlkZW8=","width":390}"#

        #expect(result.isError == false)
        #expect(textContents(result) == [expectedText])
    }

    private func toolSurfaceSnapshot() throws -> [String: Any] {
        let selectedToolNames = [
            TheFence.Command.activate.rawValue,
            TheFence.Command.getScreen.rawValue,
            TheFence.Command.startRecording.rawValue,
        ]
        let toolsByName = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })
        let propertyNamesByTool = [
            TheFence.Command.activate.rawValue: ["heistId", "label", "action", "count", "expect"],
            TheFence.Command.getScreen.rawValue: ["output", "inlineData", "includeInterface"],
            TheFence.Command.startRecording.rawValue: ["fps", "scale", "max_duration", "inactivity_timeout"],
        ]
        let nestedPropertyNamesByTool = [
            "\(TheFence.Command.activate.rawValue).expect": ["type"],
        ]

        return [
            "selectedToolNames": selectedToolNames,
            "tools": try selectedToolNames.map { toolName in
                let tool = try #require(toolsByName[toolName])
                return try toolSnapshot(
                    tool,
                    propertyNames: propertyNamesByTool[toolName] ?? [],
                    nestedPropertyNamesByProperty: nestedPropertyNamesByTool
                )
            },
        ]
    }

    private func toolSnapshot(
        _ tool: Tool,
        propertyNames: [String],
        nestedPropertyNamesByProperty: [String: [String]]
    ) throws -> [String: Any] {
        guard case .object(let rootSchema) = tool.inputSchema,
              case .object(let properties)? = rootSchema["properties"] else {
            Issue.record("\(tool.name) missing object input schema")
            return [:]
        }

        var propertySnapshots: [String: Any] = [:]
        for propertyName in propertyNames {
            guard case .object(let propertySchema)? = properties[propertyName] else {
                Issue.record("\(tool.name).\(propertyName) missing property schema")
                continue
            }
            let nestedPropertyNames = nestedPropertyNamesByProperty["\(tool.name).\(propertyName)"]
            propertySnapshots[propertyName] = schemaSnapshot(propertySchema, nestedPropertyNames: nestedPropertyNames)
        }
        guard let type = stringField(rootSchema, "type") else {
            Issue.record("\(tool.name) missing input schema type")
            return [:]
        }
        guard let additionalProperties = boolField(rootSchema, "additionalProperties") else {
            Issue.record("\(tool.name) missing additionalProperties schema flag")
            return [:]
        }

        return [
            "name": tool.name,
            "inputSchema": [
                "type": type,
                "additionalProperties": additionalProperties,
                "required": stringArrayField(rootSchema, "required"),
                "properties": propertySnapshots,
            ],
        ]
    }

    private func schemaSnapshot(
        _ schema: [String: Value],
        nestedPropertyNames: [String]? = nil
    ) -> [String: Any] {
        var snapshot: [String: Any] = [:]
        if let type = stringField(schema, "type") {
            snapshot["type"] = type
        }
        if let values = stringArrayFieldIfPresent(schema, "enum") {
            snapshot["enum"] = values
        }
        if let minimum = numberField(schema, "minimum") {
            snapshot["minimum"] = minimum
        }
        if let maximum = numberField(schema, "maximum") {
            snapshot["maximum"] = maximum
        }
        if let nestedPropertyNames,
           case .object(let nestedProperties)? = schema["properties"] {
            var nestedSnapshots: [String: Any] = [:]
            for nestedPropertyName in nestedPropertyNames {
                guard case .object(let nestedSchema)? = nestedProperties[nestedPropertyName] else {
                    Issue.record("Nested property \(nestedPropertyName) missing from schema")
                    continue
                }
                nestedSnapshots[nestedPropertyName] = schemaSnapshot(nestedSchema)
            }
            snapshot["properties"] = nestedSnapshots
        }
        return snapshot
    }

    private func textContents(_ result: CallTool.Result) -> [String] {
        result.content.compactMap { content in
            guard case .text(let text, _, _) = content else { return nil }
            return text
        }
    }

    private func assertGoldenJSON(
        _ object: [String: Any],
        equals expected: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let actual = try jsonString(object)
        #expect(actual == expected, sourceLocation: sourceLocation)
    }

    private func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try #require(String(data: data, encoding: .utf8))
    }

    private func stringField(_ schema: [String: Value], _ key: String) -> String? {
        guard case .string(let string)? = schema[key] else { return nil }
        return string
    }

    private func boolField(_ schema: [String: Value], _ key: String) -> Bool? {
        guard case .bool(let bool)? = schema[key] else { return nil }
        return bool
    }

    private func numberField(_ schema: [String: Value], _ key: String) -> Any? {
        switch schema[key] {
        case .int(let int):
            return int
        case .double(let double):
            return double
        default:
            return nil
        }
    }

    private func stringArrayField(_ schema: [String: Value], _ key: String) -> [String] {
        stringArrayFieldIfPresent(schema, key) ?? []
    }

    private func stringArrayFieldIfPresent(_ schema: [String: Value], _ key: String) -> [String]? {
        guard case .array(let values)? = schema[key] else { return nil }
        return values.compactMap { value in
            guard case .string(let string) = value else { return nil }
            return string
        }
    }
}
