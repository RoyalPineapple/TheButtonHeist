import Foundation
import MCP
@_spi(ButtonHeistInternals) @_spi(ButtonHeistTooling) import ButtonHeist
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
            switch routedToolRequest(try MCPToolRequest(name: params.name, arguments: params.arguments)) {
            case .success(let request):
                let response = try await fence.execute(request)
                return renderResponse(response)
            case .failure(let error):
                return renderResponse(.failure(error))
            }
        } catch {
            let response = FenceResponse.failure(error)
            return renderResponse(response)
        }
    }

    static func routedToolRequest(_ request: MCPToolRequest) -> Result<FenceOperationRequest, FenceOperationRoutingError> {
        return TheFence.Command.routeToolRequest(
            named: request.name,
            arguments: request.arguments.commandEnvelope
        )
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
        return structuredErrorValue(failure, presenter: FenceResponsePresenter(profile: .mcp))
    }

    private static func structuredErrorValue(
        _ failure: DiagnosticFailure,
        presenter: FenceResponsePresenter
    ) -> Value {
        do {
            let data = try presenter.jsonData(
                for: .error(failure),
                outputFormatting: []
            )
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            return MCPStructuredErrorFallback(failure: failure).value
        }
    }

}

private struct MCPStructuredErrorFallback {
    let failure: DiagnosticFailure

    var value: Value {
        .object([
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

    private var details: Value {
        .object([
            "code": .string(failure.code),
            "kind": .string(failure.kind.rawValue),
            "phase": .string(failure.phase.rawValue),
            "retryable": .bool(failure.retryable),
            "hint": failure.hint.map(Value.string) ?? .null,
        ])
    }
}
