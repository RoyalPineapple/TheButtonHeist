import Foundation
import MCP
import ButtonHeist
import TheScore
import ThePlans

@main
struct ButtonHeistMCPServer {
    typealias SwiftHeistCompiler = (_ source: URL, _ entry: String) throws -> HeistPlan

    static func main() async throws {
        let (fence, idleMonitor) = await setUp()

        let server = Server(
            name: "buttonheist",
            version: buttonHeistVersion,
            instructions: TheFence.Command.mcpServerInstructions,
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ToolDefinitions.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await handleToolCall(params, fence: fence, idleMonitor: idleMonitor)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    @ButtonHeistActor
    private static func setUp() -> (TheFence, IdleMonitor) {
        let config = EnvironmentConfig.resolve()
        let fence = TheFence(configuration: config.fenceConfiguration)
        let idleMonitor = IdleMonitor(timeout: config.sessionTimeout) { [fence] in
            fence.stop()
        }
        return (fence, idleMonitor)
    }

    @ButtonHeistActor
    private static func handleToolCall(
        _ params: CallTool.Parameters,
        fence: TheFence,
        idleMonitor: IdleMonitor
    ) async -> CallTool.Result {
        defer { idleMonitor.resetTimer() }
        do {
            let arguments = try decodeArguments(params.arguments, forTool: params.name)
            let routed = TheFence.Command.routeToolCall(named: params.name)
            let command: TheFence.Command
            switch routed {
            case .success(let value):
                command = value
            case .failure(let error):
                return .init(content: [.text(text: error.message, annotations: nil, _meta: nil)], isError: true)
            }

            let response = try await fence.execute(command: command, arguments: arguments)
            return renderResponse(response)
        } catch {
            let response = FenceResponse.failure(error)
            return .init(content: [.text(text: response.compactFormatted(), annotations: nil, _meta: nil)], isError: true)
        }
    }

    static func decodeArguments(
        _ arguments: [String: Value]?,
        forTool toolName: String? = nil,
        compileSwiftFile: SwiftHeistCompiler = { source, entry in
            try HeistSourceCompiler().compileSwiftFile(source, entry: entry)
        }
    ) throws -> TheFence.CommandArgumentEnvelope {
        if toolName == TheFence.Command.runHeist.rawValue,
           let sourceValue = arguments?["source_file"] {
            return try decodeSwiftRunHeistArguments(
                arguments ?? [:],
                sourceValue: sourceValue,
                compileSwiftFile: compileSwiftFile
            )
        }

        var values: [String: HeistValue] = [:]
        for (key, value) in arguments ?? [:] {
            values[key] = try heistValue(from: value, field: key)
        }
        return TheFence.CommandArgumentEnvelope(values: values)
    }

    private static func decodeSwiftRunHeistArguments(
        _ arguments: [String: Value],
        sourceValue: Value,
        compileSwiftFile: SwiftHeistCompiler
    ) throws -> TheFence.CommandArgumentEnvelope {
        guard case .string(let sourceFile) = sourceValue,
              !sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchemaValidationError(field: "source_file", observed: "invalid", expected: "non-empty string")
        }
        guard case .string(let entry)? = arguments["entry"],
              !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchemaValidationError(field: "entry", observed: "missing", expected: "non-empty string")
        }

        do {
            let plan = try compileSwiftFile(
                URL(fileURLWithPath: sourceFile),
                entry
            )
            return try runHeistArguments(for: plan)
        } catch {
            throw MCPAdapterError(message: "failed to compile Swift heist source: \(error)")
        }
    }

    private static func runHeistArguments(for plan: HeistPlan) throws -> TheFence.CommandArgumentEnvelope {
        let data = try JSONEncoder().encode(plan)
        let values = try JSONDecoder().decode([String: HeistValue].self, from: data)
        return TheFence.CommandArgumentEnvelope(values: values)
    }

    private static func heistValue(
        from value: Value,
        field: String
    ) throws -> HeistValue {
        switch value {
        case .null:
            throw SchemaValidationError(field: field, observed: "null", expected: "JSON scalar, array, or object")
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            guard double.isFinite else {
                throw SchemaValidationError(field: field, observed: double, expected: "finite number")
            }
            return .double(double)
        case .string(let string):
            return .string(string)
        case .data:
            throw SchemaValidationError(
                field: field,
                observed: "data",
                expected: "JSON boolean, number, string, array, or object"
            )
        case .array(let values):
            return .array(try values.enumerated().map { index, nested in
                try heistValue(from: nested, field: "\(field)[\(index)]")
            })
        case .object(let object):
            var result: [String: HeistValue] = [:]
            for (key, nested) in object {
                result[key] = try heistValue(from: nested, field: "\(field).\(key)")
            }
            return .object(result)
        }
    }

    static func renderResponse(_ response: FenceResponse) -> CallTool.Result {
        var content: [Tool.Content] = []

        // Screenshots: embed as image content. File-based screenshots fall through
        // to the compact text below.
        if case .screenshotData(let payload, _) = response {
            content.append(.image(data: payload.pngData, mimeType: "image/png", annotations: nil, _meta: nil))
        }

        content.append(.text(text: response.compactFormatted(), annotations: nil, _meta: nil))
        return .init(content: content, isError: response.isFailure)
    }

}

struct MCPAdapterError: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}
