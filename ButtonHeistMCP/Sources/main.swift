import Foundation
import MCP
@_spi(ButtonHeistInternals) @_spi(ButtonHeistTooling) import ButtonHeist
import TheScore

@main
struct ButtonHeistMCPServer {
    static func main() async throws {
        let context = try await setUp()

        let server = Server(
            name: "buttonheist",
            version: buttonHeistVersion.description,
            instructions: TheFence.Command.mcpServerInstructions,
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ToolDefinitions.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await handleToolCall(params, context: context)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    @ButtonHeistActor
    private static func setUp() throws -> MCPServerContext {
        let config = try EnvironmentConfig.resolve()
        let fence = TheFence(configuration: config.fenceConfiguration)
        let idleMonitor = IdleMonitor(timeout: config.sessionTimeout) { [fence] in
            fence.stop()
        }
        return MCPServerContext(fence: fence, idleMonitor: idleMonitor)
    }

    @ButtonHeistActor
    private static func handleToolCall(
        _ params: CallTool.Parameters,
        context: MCPServerContext
    ) async -> CallTool.Result {
        defer { context.idleMonitor.resetTimer() }
        do {
            let arguments = try MCPValueBridge.commandEnvelope(from: params.arguments)
            switch TheFence.Command.routeToolRequest(named: params.name, arguments: arguments) {
            case .success(let input):
                let response = try await context.fence.execute(try context.fence.admit(input))
                return renderResponse(response)
            case .failure(let error):
                return renderResponse(.failure(error))
            }
        } catch {
            let response = FenceResponse.failure(error)
            return renderResponse(response)
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
            return try MCPValueBridge.structuredContent(for: response, presenter: presenter)
        } catch {
            return structuredEncodingFailureValue(error)
        }
    }

    static func structuredEncodingFailureValue(_ error: Error) -> Value {
        let failure = DiagnosticFailure(
            message: "Failed to encode structured tool response: \(error.localizedDescription)",
            details: FailureDetails(code: .formattingJSONEncodingFailed)
        )
        return (try? MCPValueBridge.structuredContent(
            for: .error(failure),
            presenter: FenceResponsePresenter(profile: .mcp)
        )) ?? .object([
            "status": .string("error"),
            "message": .string(failure.message),
        ])
    }

}

private struct MCPServerContext {
    let fence: TheFence
    let idleMonitor: IdleMonitor
}
