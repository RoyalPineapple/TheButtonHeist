import Foundation
import MCP
import ButtonHeist

@main
struct ButtonHeistMCPServer {
    static func main() async throws {
        let fence = TheFence(
            configuration: .init(
                deviceFilter: ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"],
                connectionTimeout: 30,
                forceSession: ProcessInfo.processInfo.environment["BUTTONHEIST_FORCE"] == "1",
                token: ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"],
                autoReconnect: true
            )
        )

        let server = Server(
            name: "buttonheist",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [ToolDefinitions.run])
        }

        await server.withMethodHandler(CallTool.self) { params in
            await handleToolCall(params, fence: fence)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    @MainActor
    private static func handleToolCall(
        _ params: CallTool.Parameters,
        fence: TheFence
    ) async -> CallTool.Result {
        guard params.name == "run" else {
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
        }

        do {
            let request = try decodeArguments(params.arguments)
            guard request["command"] is String else {
                return .init(content: [.text("Missing required parameter: command")], isError: true)
            }

            let response = try await fence.execute(request: request)
            return try renderResponse(response)
        } catch {
            return .init(content: [.text(errorMessage(error))], isError: true)
        }
    }

    private static func decodeArguments(_ arguments: [String: Value]?) throws -> [String: Any] {
        guard let arguments else { return [:] }
        var request: [String: Any] = [:]
        for (key, value) in arguments {
            request[key] = anyValue(from: value)
        }
        return request
    }

    private static func anyValue(from value: Value) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .data(_, let data):
            return data.base64EncodedString()
        case .array(let values):
            return values.map(anyValue(from:))
        case .object(let object):
            var result: [String: Any] = [:]
            for (key, nested) in object {
                result[key] = anyValue(from: nested)
            }
            return result
        }
    }

    private static func renderResponse(_ response: FenceResponse) throws -> CallTool.Result {
        var content: [Tool.Content] = []
        var payload = response.jsonDict() ?? [:]

        if let pngData = payload["pngData"] as? String {
            content.append(.image(data: pngData, mimeType: "image/png", metadata: nil))
            payload["pngData"] = "<omitted base64 png data>"
        }

        if let videoData = payload["videoData"] as? String {
            payload["videoData"] = "<omitted base64 video data (\(videoData.count) chars)>"
        }

        let isError = (payload["status"] as? String) == "error"
        content.append(.text(try compactJSON(payload)))
        return .init(content: content, isError: isError)
    }

    private static func compactJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
