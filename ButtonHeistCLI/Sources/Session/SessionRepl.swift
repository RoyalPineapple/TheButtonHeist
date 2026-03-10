import Foundation
import Darwin
import ButtonHeist

@ButtonHeistActor
final class ReplSession {
    private let format: OutputFormat
    private let fence: TheFence
    private let sessionTimeout: TimeInterval
    private var isRunning = true
    private var shouldExit = false
    private nonisolated(unsafe) var lastCommandTime = ContinuousClock.now
    private var timeoutTask: Task<Void, Never>?

    init(
        deviceFilter: String?,
        connectionTimeout: Double,
        format: OutputFormat,
        token: String? = nil,
        sessionTimeout: Double = 0
    ) {
        self.format = format
        if sessionTimeout > 0 {
            self.sessionTimeout = sessionTimeout
        } else if let envValue = ProcessInfo.processInfo.environment["BUTTONHEIST_SESSION_TIMEOUT"],
                  let parsed = Double(envValue), parsed > 0 {
            self.sessionTimeout = parsed
        } else {
            self.sessionTimeout = 0
        }
        self.fence = TheFence(
            configuration: .init(
                deviceFilter: deviceFilter,
                connectionTimeout: connectionTimeout,
                token: token,
                autoReconnect: true
            )
        )
        self.fence.onStatus = { message in
            logStatus(message)
        }
    }

    func run() async throws {
        try await fence.start()

        let isTTY = isatty(STDIN_FILENO) != 0
        if isTTY {
            logStatus("Session started. Type 'help' for commands, 'quit' to exit.")
            if sessionTimeout > 0 {
                logStatus("Idle timeout: \(Int(sessionTimeout))s")
            }
        }

        signal(SIGINT) { _ in Darwin.exit(0) }

        lastCommandTime = .now
        if sessionTimeout > 0 {
            startTimeoutMonitor()
        }

        while isRunning {
            if isTTY {
                fputs("> ", stderr)
                fflush(stderr)
            }

            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break
            }

            lastCommandTime = .now

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)

            if shouldExit { break }
        }

        timeoutTask?.cancel()
        fence.stop()
    }

    private func startTimeoutMonitor() {
        timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SessionDefaults.timeoutCheckInterval))
                guard !Task.isCancelled, let self else { return }
                let elapsed = ContinuousClock.now - self.lastCommandTime
                if elapsed > .seconds(self.sessionTimeout) {
                    logStatus("Session idle timeout (\(Int(self.sessionTimeout))s) — exiting.")
                    self.isRunning = false
                    close(STDIN_FILENO)
                    return
                }
            }
        }
    }

    private func processLine(_ line: String) async -> (FenceResponse, Any?) {
        let request: [String: Any]

        if line.hasPrefix("{") {
            // JSON mode — machine interface
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["command"] is String
            else {
                return (.error("Invalid JSON or missing 'command' field"), nil)
            }
            request = object
        } else {
            // Human-friendly mode
            request = Self.parseHumanInput(line)
        }

        guard let command = request["command"] as? String else {
            return (.error("Unknown command. Type 'help' for available commands."), nil)
        }

        let requestId = request["id"]

        // Enhanced help for human mode
        if command == TheFence.Command.help.rawValue && format == .human && !line.hasPrefix("{") {
            return (.ok(message: Self.humanHelp), nil)
        }

        do {
            let response = try await fence.execute(request: request)
            if command == TheFence.Command.quit.rawValue || command == TheFence.Command.exit.rawValue {
                shouldExit = true
                isRunning = false
            }
            return (response, requestId)
        } catch {
            if let fenceError = error as? FenceError, let message = fenceError.errorDescription {
                return (.error(message), requestId)
            }
            return (.error("Internal error: \(error.localizedDescription)"), requestId)
        }
    }

    // MARK: - Human-Friendly Input Parser

    nonisolated static let humanHelp = """
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
          idle                        Wait for animations to settle
          idle timeout=5              Wait with custom timeout

        Gestures:
          tap <identifier>            Tap element by accessibility ID
          tap #3                      Tap element by order number
          tap 100 200                 Tap at coordinates
          press <id>                  Long press (duration=N for seconds)
          swipe up <id>               Swipe direction on element
          drag endX=200 endY=300      Drag gesture
          pinch <id> scale=2.0        Pinch (>1 zoom in, <1 zoom out)
          rotate <id> angle=1.57      Rotate (radians)
          two_finger_tap <id>         Two-finger tap
          draw_path points=[...]      Draw path through waypoints (JSON)
          draw_bezier curves=[...]    Draw bezier curves (JSON)

        Scrolling:
          scroll down <id>            Scroll direction on element
          scroll_to_visible <id>      Scroll until element visible
          scroll_to_edge top <id>     Scroll to edge

        Actions:
          activate <id>               Activate element
          increment <id>              Increment (e.g. slider)
          decrement <id>              Decrement
          perform_custom_action <id>  Perform named custom action
          type "hello world"          Type text
          copy / paste / cut          Edit actions
          select / select_all         Selection actions
          dismiss_keyboard            Dismiss keyboard

        Recording:
          record                      Start recording
          stop_recording              Stop and retrieve recording

        Target elements by accessibility identifier, or #N for order number.
        Key=value pairs work for any parameter: tap identifier=btn x=100 y=200
        JSON input still works: {"command":"one_finger_tap","identifier":"btn"}
        """

    private nonisolated static let commandAliases: [String: String] = [
        "tap": TheFence.Command.oneFingerTap.rawValue,
        "press": TheFence.Command.longPress.rawValue,
        "ui": TheFence.Command.getInterface.rawValue,
        "screen": TheFence.Command.getScreen.rawValue,
        "screenshot": TheFence.Command.getScreen.rawValue,
        "idle": TheFence.Command.waitForIdle.rawValue,
        "devices": TheFence.Command.listDevices.rawValue,
        "list": TheFence.Command.listDevices.rawValue,
        "type": TheFence.Command.typeText.rawValue,
        "record": TheFence.Command.startRecording.rawValue,
    ]

    /// Aliases that expand to a command + default parameter (e.g. "copy" → edit_action with action=copy).
    private nonisolated static let compoundAliases: [String: (command: String, params: [String: String])] = [
        "copy": (TheFence.Command.editAction.rawValue, ["action": "copy"]),
        "paste": (TheFence.Command.editAction.rawValue, ["action": "paste"]),
        "cut": (TheFence.Command.editAction.rawValue, ["action": "cut"]),
        "select": (TheFence.Command.editAction.rawValue, ["action": "select"]),
        "select_all": (TheFence.Command.editAction.rawValue, ["action": "selectAll"]),
    ]

    private nonisolated static let directionWords: Set<String> = [
        "up", "down", "left", "right", "next", "previous"
    ]

    private nonisolated static let edgeWords: Set<String> = [
        "top", "bottom", "left", "right"
    ]

    private nonisolated static let directionCommands: Set<String> = [
        TheFence.Command.swipe.rawValue, TheFence.Command.scroll.rawValue,
    ]

    nonisolated static func parseHumanInput(_ line: String) -> [String: Any] {
        let tokens = tokenize(line)
        guard let first = tokens.first else { return [:] }

        let rawCommand = first.lowercased()
        let command: String
        var result: [String: Any]
        let args = Array(tokens.dropFirst())

        if let compound = compoundAliases[rawCommand] {
            command = compound.command
            result = ["command": command]
            for (key, value) in compound.params { result[key] = value }
        } else {
            command = commandAliases[rawCommand] ?? rawCommand
            result = ["command": command]
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

        return result
    }

    private nonisolated static func interpretPositionalArgs(command: String, positional: [String], into result: inout [String: Any]) {
        guard !positional.isEmpty else { return }

        switch command {
        case TheFence.Command.typeText.rawValue:
            // Everything after "type" is the text to type
            if result["text"] == nil {
                result["text"] = positional.joined(separator: " ")
            }

        case TheFence.Command.editAction.rawValue:
            if result["action"] == nil, let action = positional.first {
                result["action"] = action
            }

        case TheFence.Command.scrollToEdge.rawValue:
            // First positional: edge or identifier; second: identifier
            var remaining = positional
            if let first = remaining.first, edgeWords.contains(first.lowercased()) {
                result["edge"] = first.lowercased()
                remaining.removeFirst()
            }
            applyElementTarget(remaining, into: &result)

        case TheFence.Command.performCustomAction.rawValue:
            // First positional: identifier, rest: actionName
            if let first = positional.first {
                applyElementTarget([first], into: &result)
                if positional.count > 1 {
                    result["actionName"] = positional.dropFirst().joined(separator: " ")
                }
            }

        default:
            // Generic positional handling
            var remaining = positional

            // For direction commands, consume a direction word first
            if directionCommands.contains(command),
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

    private nonisolated static func applyElementTarget(_ tokens: [String], into result: inout [String: Any]) {
        guard let first = tokens.first else { return }
        if first.hasPrefix("#"), let order = Int(first.dropFirst()) {
            result["order"] = order
        } else {
            result["identifier"] = first
        }
    }

    private nonisolated static func tokenize(_ line: String) -> [String] {
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

    private func outputResponse(_ response: FenceResponse, id: Any?) {
        switch format {
        case .human:
            writeOutput(response.humanFormatted())
        case .json:
            if var dictionary = response.jsonDict() {
                if let id {
                    dictionary["id"] = id
                }
                if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    writeOutput(json)
                }
            }
        }
    }
}
