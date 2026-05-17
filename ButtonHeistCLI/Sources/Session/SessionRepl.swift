import Foundation
import Darwin
import ButtonHeist

@ButtonHeistActor
final class ReplSession {

    // MARK: - Nested Types

    private enum State {
        case running(IdleMonitor?)
        case exiting
        case stopped
    }

    // MARK: - Properties

    private let format: OutputFormat
    private let fence: TheFence
    private let sessionTimeout: TimeInterval
    private var state: State = .stopped

    // MARK: - Init

    init(config: EnvironmentConfig, format: OutputFormat) {
        self.format = format
        self.sessionTimeout = config.sessionTimeout
        self.fence = TheFence(configuration: config.fenceConfiguration)
        self.fence.onStatus = { message in
            logStatus(message)
        }
    }

    // MARK: - REPL Loop

    func run() async throws {
        try await fence.start()

        let isTTY = isatty(STDIN_FILENO) != 0
        if isTTY {
            logStatus("Session started. Type 'help' for commands, 'quit' to exit.")
            if sessionTimeout > 0 {
                logStatus("Idle timeout: \(Int(sessionTimeout))s")
            }
        }

        // SIGINT closes stdin to unstick the blocking readLine; the loop sees
        // a nil line and breaks, then runs the same structured teardown the
        // idle-timeout path uses (idleMonitor.stop, state = .stopped,
        // fence.stop). close() is async-signal-safe; we deliberately do NOT
        // touch Swift state from here.
        signal(SIGINT) { _ in close(STDIN_FILENO) }

        let monitor = sessionTimeout > 0 ? makeTimeoutMonitor() : nil
        state = .running(monitor)

        loop: while case .running(let idleMonitor) = state {
            if isTTY {
                fputs("> ", stderr)
                fflush(stderr)
            }

            // Swift.readLine() is a blocking syscall; detaching from MainActor keeps the REPL responsive.
            // swiftlint:disable:next agent_no_task_detached
            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break
            }

            idleMonitor?.resetTimer()

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)

            if case .exiting = state { break loop }
        }

        if case .running(let idleMonitor) = state {
            idleMonitor?.stop()
        }
        state = .stopped
        fence.stop()
    }

    private func makeTimeoutMonitor() -> IdleMonitor {
        let monitor = IdleMonitor(timeout: sessionTimeout) { [weak self] in
            guard let self else { return }
            logStatus("Session idle timeout (\(Int(self.sessionTimeout))s) — exiting.")
            self.state = .exiting
            close(STDIN_FILENO)
        }
        monitor.resetTimer()
        return monitor
    }

    private func processLine(_ line: String) async -> (FenceResponse, Any?) {
        let request: [String: Any]

        if line.hasPrefix("{") {
            // JSON mode — machine interface
            do {
                let data = Data(line.utf8)
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      parsed["command"] is String else {
                    return (.error("Invalid JSON or missing 'command' field"), nil)
                }
                request = parsed
            } catch {
                return (.error("Invalid JSON: \(error.localizedDescription)"), nil)
            }
        } else {
            // Human-friendly mode
            request = Self.parseHumanInput(line)
        }

        guard let command = request["command"] as? String else {
            return (.error("Unknown command. Type 'help' for available commands."), nil)
        }

        let requestId = request["id"]
        let parsedCommand = TheFence.Command(rawValue: command)

        // Enhanced help for human mode
        if parsedCommand == .help && format == .human && !line.hasPrefix("{") {
            return (.ok(message: Self.humanHelp), nil)
        }

        do {
            let response = try await fence.execute(request: request)
            if parsedCommand == .quit || parsedCommand == .exit {
                if case .running(let idleMonitor) = state {
                    idleMonitor?.stop()
                }
                state = .exiting
            }
            return (response, requestId)
        } catch {
            return (.failure(error), requestId)
        }
    }

    // MARK: - Output

    private func outputResponse(_ response: FenceResponse, id: Any?) {
        switch format {
        case .human:
            writeOutput(response.humanFormatted())
        case .compact:
            writeOutput(response.compactFormatted())
        case .json:
            if var dictionary = response.jsonDict() {
                if let id {
                    dictionary["id"] = id
                }
                do {
                    let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
                    if let json = String(data: data, encoding: .utf8) {
                        writeOutput(json)
                    } else {
                        logStatus("Failed to encode JSON data as UTF-8")
                    }
                } catch {
                    logStatus("Failed to serialize response as JSON: \(error.localizedDescription)")
                }
            } else {
                logStatus("Failed to serialize response as JSON")
            }
        }
    }
}

// MARK: - Human-Friendly Input Parser

nonisolated extension ReplSession {

    static let humanHelp = """
        Commands (type a command, or use JSON for full control):

        Quick reference:
          help                        Show this help
          status                      Connection status
          quit / exit                 End session
          devices                     List available devices

        Inspect:
          ui                          Get accessibility interface
          screen                      Capture screenshot
          screen output=photo.png     Save screenshot to file
          change                      Wait for any UI change
          change expect=screen_changed  Wait for specific change
          change timeout=10           Wait with custom timeout
          wait label="Loading" absent=true  Wait for element to disappear

        Gestures:
          tap <heistId>               Tap by current heistId handle
          tap 100 200                 Tap at coordinates
          press <id>                  Long press (duration=N for seconds)
          swipe up <id>               Swipe direction on element
          drag endX=200 endY=300      Drag gesture
          pinch <id> scale=2.0        Pinch (>1 zoom in, <1 zoom out)
          rotate <id> angle=1.57      Rotate (radians)
          two_finger_tap <id>         Two-finger tap
          draw_path points=[...]      Draw path through waypoints (JSON)
          draw_bezier segments=[...]  Draw bezier curves (JSON)

        Scrolling:
          scroll down <id>            Scroll direction on element
          scroll_to_visible <id>      Bring known element into view
          element_search -l "text"    Search scroll content for element
          scroll_to_edge top <id>     Scroll to edge

        Actions:
          activate <id>               Activate element
          increment <id>              Increment (e.g. slider)
          decrement <id>              Decrement
          perform_custom_action <id>  Perform named custom action
          rotor <id> rotor=Errors     Move to next rotor result
          rotor previous <id>         Move to previous rotor result
          type "hello world"          Type text
          copy / paste / cut / delete Edit actions
          select / select_all         Selection actions
          dismiss_keyboard            Dismiss keyboard

        Pasteboard:
          set_pasteboard text="hello"  Write text to pasteboard
          get_pasteboard               Read text from pasteboard

        Recording:
          record                      Start recording
          stop_recording              Stop and retrieve recording

        Bare words are looked up as current heistId handles (from get_interface).
        Key=value pairs work for any parameter: tap identifier=btn x=100 y=200
        JSON input still works: {"command":"activate","heistId":"button_save"}
        """

    private static let commandAliases: [String: TheFence.Command] = [
        "tap": .oneFingerTap,
        "press": .longPress,
        "ui": .getInterface,
        "screen": .getScreen,
        "screenshot": .getScreen,
        "idle": .waitForChange,
        "change": .waitForChange,
        "wait": .waitFor,
        "devices": .listDevices,
        "list": .listDevices,
        "type": .typeText,
        "record": .startRecording,
    ]

    /// Aliases that expand to a command + default parameter (e.g. "copy" → edit_action with action=copy).
    private static let compoundAliases: [String: (command: TheFence.Command, params: [String: String])] = [
        "copy": (.editAction, ["action": EditAction.copy.rawValue]),
        "paste": (.editAction, ["action": EditAction.paste.rawValue]),
        "cut": (.editAction, ["action": EditAction.cut.rawValue]),
        "delete": (.editAction, ["action": EditAction.delete.rawValue]),
        "select": (.editAction, ["action": EditAction.select.rawValue]),
        "select_all": (.editAction, ["action": EditAction.selectAll.rawValue]),
    ]

    private static let directionWords: Set<String> = [
        "up", "down", "left", "right", "next", "previous"
    ]

    private static let edgeWords: Set<String> = [
        "top", "bottom", "left", "right"
    ]

    private static let directionCommands: Set<TheFence.Command> = [
        .swipe, .scroll, .rotor,
    ]

    static func parseHumanInput(_ line: String) -> [String: Any] {
        let tokens = tokenize(line)
        guard let first = tokens.first else { return [:] }

        let rawCommand = first.lowercased()
        let command: TheFence.Command?
        var result: [String: Any]
        let args = Array(tokens.dropFirst())

        if let compound = compoundAliases[rawCommand] {
            command = compound.command
            result = compound.command.cliRequest()
            for (key, value) in compound.params { result[key] = value }
        } else {
            command = commandAliases[rawCommand] ?? TheFence.Command(rawValue: rawCommand)
            result = command?.cliRequest() ?? ["command": rawCommand]
        }

        // Separate key=value pairs from positional tokens
        var positional: [String] = []
        for arg in args {
            if let eqIndex = arg.firstIndex(of: "="), eqIndex != arg.startIndex {
                let key = String(arg[arg.startIndex..<eqIndex])
                let value = String(arg[arg.index(after: eqIndex)...])
                // Auto-convert numeric values
                if let intVal = Int(value) {
                    result[key] = intVal
                } else if let dblVal = Double(value) {
                    result[key] = dblVal
                } else {
                    result[key] = value
                }
            } else {
                positional.append(arg)
            }
        }

        // Interpret positional arguments based on command context
        interpretPositionalArgs(command: command, positional: positional, into: &result)
        normalizeExpectationArgument(in: &result)

        return result
    }

    private static func normalizeExpectationArgument(in result: inout [String: Any]) {
        guard let rawExpectation = result["expect"] as? String,
              let expectation = try? ExpectationArgumentParser.parse(rawExpectation) else {
            return
        }
        result["expect"] = expectation
    }

    private static func interpretPositionalArgs(
        command: TheFence.Command?,
        positional: [String],
        into result: inout [String: Any]
    ) {
        guard !positional.isEmpty else { return }

        switch command {
        case .some(.typeText):
            // Everything after "type" is the text to type
            if result["text"] == nil {
                result["text"] = positional.joined(separator: " ")
            }

        case .some(.editAction):
            if result["action"] == nil, let action = positional.first {
                result["action"] = action
            }

        case .some(.scrollToEdge):
            // First positional: edge or identifier; second: identifier
            var remaining = positional
            if let first = remaining.first, edgeWords.contains(first.lowercased()) {
                result["edge"] = first.lowercased()
                remaining.removeFirst()
            }
            applyElementTarget(remaining, into: &result)

        case .some(.performCustomAction):
            // First positional: identifier, rest: actionName
            if let first = positional.first {
                applyElementTarget([first], into: &result)
                if positional.count > 1 {
                    result["action"] = positional.dropFirst().joined(separator: " ")
                }
            }

        default:
            // Generic positional handling
            var remaining = positional

            // For direction commands, consume a direction word first
            if let command, directionCommands.contains(command),
               let first = remaining.first, directionWords.contains(first.lowercased()) {
                result["direction"] = first.lowercased()
                remaining.removeFirst()
            }

            // Two bare numbers → x, y coordinates
            if remaining.count >= 2,
               let x = Double(remaining[0]),
               let y = Double(remaining[1]) {
                result["x"] = x
                result["y"] = y
                remaining.removeFirst(2)
            } else {
                // Otherwise treat as element target
                applyElementTarget(remaining, into: &result)
                remaining = []
            }
        }
    }

    private static func applyElementTarget(_ tokens: [String], into result: inout [String: Any]) {
        guard let first = tokens.first else { return }
        result["heistId"] = first
    }

    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character?
        var iterator = line.makeIterator()

        while let ch = iterator.next() {
            if let quote = inQuote {
                if ch == quote {
                    inQuote = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch == " " || ch == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
