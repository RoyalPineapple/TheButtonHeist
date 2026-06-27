import Foundation
import MCP
import ButtonHeist
import TheScore

@main
struct ButtonHeistMCPServer {
    static func main() async throws {
        let (fence, idleMonitor) = try await setUp()

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
    private static func setUp() throws -> (TheFence, IdleMonitor) {
        let config = try EnvironmentConfig.resolve()
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
            let arguments = try decodeArguments(params.arguments)
            let routed = TheFence.Command.routeToolCall(named: params.name)
            let command: TheFence.Command
            switch routed {
            case .success(let value):
                command = value
            case .failure(let error):
                return renderResponse(.failure(error))
            }

            let response = try await fence.execute(command: command, arguments: arguments)
            return renderResponse(response)
        } catch {
            let response = FenceResponse.failure(error)
            return renderResponse(response)
        }
    }

    static func decodeArguments(
        _ arguments: [String: Value]?
    ) throws -> TheFence.CommandArgumentEnvelope {
        try MCPArgumentInputPreflight.validate(arguments)
        var values: [String: HeistValue] = [:]
        for (key, value) in arguments ?? [:] {
            values[key] = try heistValue(from: value, field: key)
        }
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
        let presenter = FenceResponsePresenter(profile: .mcp)

        // Screenshots: embed as image content. File-based screenshots fall through
        // to the compact text below.
        if case .screenshotData(let payload, _) = response {
            content.append(.image(data: payload.pngData, mimeType: "image/png", annotations: nil, _meta: nil))
        }

        content.append(.text(text: presenter.compactText(for: response), annotations: nil, _meta: nil))
        let structuredContent: Value? = structuredContent(for: response, presenter: presenter)
        return .init(
            content: content,
            structuredContent: structuredContent,
            isError: response.isFailure
        )
    }

    private static func structuredContent(
        for response: FenceResponse,
        presenter: FenceResponsePresenter
    ) -> Value {
        do {
            let data = try presenter.jsonData(for: response, outputFormatting: [])
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            return .object([
                "status": .string("error"),
                "message": .string("Failed to encode structured tool response: \(error.localizedDescription)"),
            ])
        }
    }

}
