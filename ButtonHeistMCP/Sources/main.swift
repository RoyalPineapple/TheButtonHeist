import Foundation
import MCP
import ButtonHeist
import TheScore

@main
struct ButtonHeistMCPServer {
    static func main() async throws {
        let (fence, idleMonitor) = await setUp()

        let server = Server(
            name: "buttonheist",
            version: buttonHeistVersion,
            instructions: Self.instructions,
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

    static var instructions: String {
        TheFence.Command.mcpServerInstructions
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
            let arguments = try decodeArguments(params.arguments)
            let routed = FenceOperationCatalog.normalizeToolCall(name: params.name, arguments: arguments)
            let operation: NormalizedOperation
            switch routed {
            case .success(let value):
                operation = value
            case .failure(let error):
                return .init(content: [.text(text: error.message, annotations: nil, _meta: nil)], isError: true)
            }

            let response = try await fence.execute(operation: operation)
            let backgroundAccessibilityTraces = fence.drainBackgroundAccessibilityTraces()
            return renderResponse(response, backgroundAccessibilityTraces: backgroundAccessibilityTraces)
        } catch {
            let response = FenceResponse.failure(error)
            return .init(content: [.text(text: response.compactFormatted(), annotations: nil, _meta: nil)], isError: true)
        }
    }

    private static func decodeArguments(_ arguments: [String: Value]?) throws -> TheFence.CommandArgumentEnvelope {
        var values: [String: TheFence.CommandArgumentValue] = [:]
        for (key, value) in arguments ?? [:] {
            values[key] = try commandArgumentValue(from: value, field: key)
        }
        return TheFence.CommandArgumentEnvelope(values: values)
    }

    private static func commandArgumentValue(
        from value: Value,
        field: String
    ) throws -> TheFence.CommandArgumentValue {
        switch value {
        case .null:
            return .null
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
        case .data(_, let data):
            return .string(data.base64EncodedString())
        case .array(let values):
            return .array(try values.enumerated().map { index, nested in
                try commandArgumentValue(from: nested, field: "\(field)[\(index)]")
            })
        case .object(let object):
            var result: [String: TheFence.CommandArgumentValue] = [:]
            for (key, nested) in object {
                result[key] = try commandArgumentValue(from: nested, field: "\(field).\(key)")
            }
            return .object(result)
        }
    }

    static func renderResponse(_ response: FenceResponse, backgroundAccessibilityTraces: [AccessibilityTrace]) -> CallTool.Result {
        var content: [Tool.Content] = []

        // Background changes: what happened while the agent was thinking
        for backgroundAccessibilityTrace in backgroundAccessibilityTraces {
            guard let backgroundDelta = backgroundAccessibilityTrace.backgroundDelta else { continue }
            let transient = backgroundDelta.transient
            var lines: [String] = []
            switch backgroundDelta {
            case .screenChanged(let payload):
                lines.append("[while_idle: screen changed (\(payload.elementCount) elements)]")
                for (index, element) in payload.newInterface.elements.enumerated() {
                    lines.append("  \(FenceResponse.compactElementLine(element, displayIndex: index))")
                }
                for element in transient {
                    lines.append("  +- \(FenceResponse.compactElementLine(element))")
                }
            case .elementsChanged(let payload):
                let edits = payload.edits
                var parts: [String] = []
                if !edits.added.isEmpty { parts.append("+\(edits.added.count)") }
                if !edits.removed.isEmpty { parts.append("-\(edits.removed.count)") }
                if !edits.updated.isEmpty { parts.append("~\(edits.updated.count)") }
                if !transient.isEmpty { parts.append("+-\(transient.count)") }
                lines.append("[while_idle: elements changed \(parts.joined(separator: " ")) (\(payload.elementCount) total)]")
                for element in edits.added {
                    lines.append("  + \(FenceResponse.compactElementLine(element))")
                }
                for heistId in edits.removed {
                    lines.append("  - \(heistId)")
                }
                for element in transient {
                    lines.append("  +- \(FenceResponse.compactElementLine(element))")
                }
            case .noChange(let payload):
                lines.append("[while_idle: no net change (\(payload.elementCount) elements)]")
                for element in transient {
                    lines.append("  +- \(FenceResponse.compactElementLine(element))")
                }
            }
            if !lines.isEmpty {
                content.append(.text(text: lines.joined(separator: "\n"), annotations: nil, _meta: nil))
            }
        }

        // Screenshots: embed as image content. File-based screenshots fall through
        // to the compact text below.
        if case .screenshotData(let payload, _) = response {
            content.append(.image(data: payload.pngData, mimeType: "image/png", annotations: nil, _meta: nil))
        }

        if case .recordingExpanded = response,
           let jsonText = Self.jsonText(response) {
            content.append(.text(text: jsonText, annotations: nil, _meta: nil))
        } else {
            content.append(.text(text: response.compactFormatted(), annotations: nil, _meta: nil))
        }
        return .init(content: content, isError: response.isFailure)
    }

    private static func jsonText(_ response: FenceResponse) -> String? {
        guard let data = try? response.jsonData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

}
