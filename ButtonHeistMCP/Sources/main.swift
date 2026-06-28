import Foundation
import MCP
@_spi(ButtonHeistInternals) import ButtonHeist
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
            switch try routedToolRequest(name: params.name, arguments: params.arguments) {
            case .success(let request):
                let response = try await fence.execute(command: request.command, arguments: request.arguments)
                return renderResponse(response)
            case .failure(let error):
                return renderResponse(.failure(error))
            }
        } catch {
            let response = FenceResponse.failure(error)
            return renderResponse(response)
        }
    }

    static func routedToolRequest(
        name: String,
        arguments: [String: Value]?
    ) throws -> Result<(command: TheFence.Command, arguments: TheFence.CommandArgumentEnvelope), FenceOperationRoutingError> {
        switch TheFence.Command.routeToolCall(named: name) {
        case .success(let command):
            return .success((command: command, arguments: try decodeArguments(arguments)))
        case .failure(let error):
            return .failure(error)
        }
    }

    static func decodeArguments(
        _ arguments: [String: Value]?
    ) throws -> TheFence.CommandArgumentEnvelope {
        TheFence.CommandArgumentEnvelope(values: try MCPArgumentInputPreflight.heistValues(arguments))
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
            return structuredEncodingFailureValue(error)
        }
    }

    static func structuredEncodingFailureValue(_ error: Error) -> Value {
        let failure = DiagnosticFailure(
            message: "Failed to encode structured tool response: \(error.localizedDescription)",
            details: FailureDetails(code: .formattingJSONEncodingFailed)
        )
        return structuredErrorValue(failure)
    }

    private static func structuredErrorValue(_ failure: DiagnosticFailure) -> Value {
        let details: Value = .object([
            "code": .string(failure.code),
            "kind": .string(failure.kind.rawValue),
            "phase": .string(failure.phase.rawValue),
            "retryable": .bool(failure.retryable),
            "hint": failure.hint.map(Value.string) ?? .null,
        ])
        return .object([
            "status": .string("error"),
            "message": .string(failure.message),
            "code": .string(failure.code),
            "kind": .string(failure.kind.rawValue),
            "errorCode": .string(failure.code),
            "phase": .string(failure.phase.rawValue),
            "retryable": .bool(failure.retryable),
            "hint": failure.hint.map(Value.string) ?? .null,
            "details": details,
        ])
    }

}
