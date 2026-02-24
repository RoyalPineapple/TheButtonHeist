import Foundation
import MCP

func log(_ msg: String) {
    FileHandle.standardError.write(Data("[buttonheist-mcp] \(msg)\n".utf8))
}

// MARK: - Line Reader

/// Reads newline-delimited JSON from the session subprocess stdout
final class LineReader: @unchecked Sendable {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ handle: FileHandle) { self.handle = handle }

    func readLine() -> String? {
        while true {
            if let i = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[buffer.startIndex..<i], encoding: .utf8)
                buffer.removeSubrange(buffer.startIndex...i)
                return line
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}

// MARK: - Binary Discovery

func findCLI() -> String {
    if let p = ProcessInfo.processInfo.environment["BUTTONHEIST_CLI"] { return p }
    if let selfURL = Bundle.main.executableURL {
        let p = selfURL.deletingLastPathComponent().appendingPathComponent("buttonheist").path
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    for p in ["../ButtonHeistCLI/.build/release/buttonheist",
              "../ButtonHeistCLI/.build/debug/buttonheist"] {
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return "buttonheist"
}

// MARK: - Entry Point

@main
struct ButtonHeistMCP {
    static func main() async throws {
        let cli = findCLI()
        log("CLI: \(cli)")

        // Build session args
        var sessionArgs = ["session", "--format", "json"]
        let argv = CommandLine.arguments
        if let i = argv.firstIndex(of: "--device"), i + 1 < argv.count {
            sessionArgs += ["--device", argv[i + 1]]
        } else if let d = ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"] {
            sessionArgs += ["--device", d]
        }

        // Spawn session subprocess
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = sessionArgs
        let inPipe = Pipe(), outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.standardError
        try proc.run()
        log("Session PID \(proc.processIdentifier)")

        let writer = inPipe.fileHandleForWriting
        let reader = LineReader(outPipe.fileHandleForReading)

        proc.terminationHandler = { p in
            log("Session exited (\(p.terminationStatus))")
            Darwin.exit(1)
        }

        // MCP server with single tool
        let server = Server(
            name: "buttonheist",
            version: "2.0.0",
            instructions: """
                iOS app automation. Use the `run` tool with {"command":"<name>", ...params}.

                Commands: get_interface, get_screen, tap, long_press, swipe, drag, pinch, \
                rotate, two_finger_tap, draw_path, draw_bezier, activate, increment, \
                decrement, perform_custom_action, type_text, edit_action, dismiss_keyboard, \
                wait_for_idle, list_devices, status, help

                Target elements by `identifier` or `order` (from get_interface). \
                Touch commands also accept `x`/`y` coordinates.

                Examples:
                  {"command":"get_interface"}
                  {"command":"tap","identifier":"loginButton"}
                  {"command":"tap","order":3}
                  {"command":"swipe","direction":"up"}
                  {"command":"type_text","text":"hello","identifier":"emailField"}
                  {"command":"get_screen"}
                """,
            capabilities: .init(tools: .init(listChanged: false))
        )

        let tool = Tool(
            name: "run",
            description: "Send a command to the connected iOS app.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object([
                        "type": .string("string"),
                        "description": .string("Command name"),
                    ]),
                ]),
                "required": .array([.string("command")]),
                "additionalProperties": .bool(true),
            ])
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [tool])
        }

        let screenFile = NSTemporaryDirectory() + "buttonheist-screen.png"

        await server.withMethodHandler(CallTool.self) { params in
            guard var dict = params.arguments else {
                return CallTool.Result(content: [.text("No arguments")], isError: true)
            }

            // For screenshots, route PNG to a temp file instead of through the pipe
            let isScreenshot = dict["command"]?.stringValue == "get_screen"
            if isScreenshot { dict["output"] = .string(screenFile) }

            // Encode args → JSON line → session stdin
            var data = try JSONEncoder().encode(dict)
            data.append(0x0A)
            writer.write(data)

            // Read one response line from session stdout
            guard let line = await Task.detached(operation: { reader.readLine() }).value else {
                return CallTool.Result(content: [.text("Session closed")], isError: true)
            }

            let isError = line.contains("\"status\":\"error\"")

            // Screenshot: read temp file → inline image
            if isScreenshot, !isError, let pngData = FileManager.default.contents(atPath: screenFile) {
                defer { try? FileManager.default.removeItem(atPath: screenFile) }
                return CallTool.Result(content: [
                    .image(data: pngData.base64EncodedString(), mimeType: "image/png", metadata: nil),
                ])
            }

            // Pass through session's compact JSON as-is
            return CallTool.Result(content: [.text(line)], isError: isError)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        log("MCP server running")
        await server.waitUntilCompleted()
        proc.terminate()
    }
}
