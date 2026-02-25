import Foundation
import Darwin
import Network
import ButtonHeist
import TheGoods

// MARK: - Session Errors

enum SessionError: Error {
    case notConnected
    case actionTimeout
}

// MARK: - Session Runner

@MainActor
final class SessionRunner {
    private let deviceFilter: String?
    private let directHost: String?
    private let directPort: UInt16?
    private let connectionTimeout: Double
    private let format: OutputFormat
    private let client = HeistClient()
    private var isRunning = true
    private var shouldExit = false

    init(deviceFilter: String?, host: String? = nil, port: UInt16? = nil,
         connectionTimeout: Double, format: OutputFormat, force: Bool = false) {
        self.directHost = host ?? ProcessInfo.processInfo.environment["BUTTONHEIST_HOST"]
        self.directPort = port ?? ProcessInfo.processInfo.environment["BUTTONHEIST_PORT"].flatMap { UInt16($0) }
        self.deviceFilter = deviceFilter ?? ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
        self.connectionTimeout = connectionTimeout
        self.format = format
        self.client.token = ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"]
        self.client.forceSession = force
        self.client.driverId = ProcessInfo.processInfo.environment["BUTTONHEIST_DRIVER_ID"]
        self.client.autoSubscribe = false
    }

    func run() async throws {
        // Connect
        try await connect()

        // Auto-reconnect when app restarts (new shortId after relaunch)
        setupAutoReconnect()

        let isTTY = isatty(STDIN_FILENO) != 0
        if isTTY {
            let name = client.connectedDevice.map { client.displayName(for: $0) } ?? "device"
            logStatus("Session started with \(name). Send JSON commands or {\"command\":\"quit\"} to exit.")
        }

        signal(SIGINT) { _ in Darwin.exit(0) }

        while isRunning {
            if isTTY {
                fputs("> ", stderr)
                fflush(stderr)
            }

            // Read a line without blocking MainActor
            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break // EOF
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)

            if shouldExit { break }
        }

        client.disconnect()
        client.stopDiscovery()
    }

    // MARK: - Connection

    private func connect() async throws {
        let device: DiscoveredDevice
        let isDirect: Bool

        warnIfPartialDirectConfig(host: directHost, port: directPort, quiet: false)

        if let host = directHost, let port = directPort {
            // Direct connection — skip Bonjour
            isDirect = true
            logStatus("Connecting to \(host):\(port)...")
            device = DiscoveredDevice(host: host, port: port)
        } else {
            // Bonjour discovery
            isDirect = false
            logStatus("Searching for iOS devices...")
            client.startDiscovery()

            let discoveryNs = UInt64(max(connectionTimeout, 5) * 1_000_000_000)
            let discoveryStart = DispatchTime.now().uptimeNanoseconds
            while client.discoveredDevices.first(matching: deviceFilter) == nil {
                if DispatchTime.now().uptimeNanoseconds - discoveryStart > discoveryNs {
                    if let filter = deviceFilter {
                        throw CLIError.noMatchingDevice(filter: filter,
                            available: client.discoveredDevices.map { $0.name })
                    }
                    throw CLIError.noDeviceFound
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            guard let found = client.discoveredDevices.first(matching: deviceFilter) else {
                throw CLIError.noDeviceFound
            }

            logStatus("Found: \(client.displayName(for: found))")
            device = found
        }

        logStatus("Connecting...")

        var connected = false
        var connectionError: Error?
        client.onConnected = { _ in connected = true }
        client.onDisconnected = { error in connectionError = error }
        client.connect(to: device)

        let connStart = DispatchTime.now().uptimeNanoseconds
        let connNs = UInt64(10 * 1_000_000_000)
        while !connected && connectionError == nil {
            if DispatchTime.now().uptimeNanoseconds - connStart > connNs {
                if isDirect { await discoverAndReport(client: client) }
                throw CLIError.connectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if let error = connectionError {
            if isDirect { await discoverAndReport(client: client) }
            throw CLIError.connectionFailed(error.localizedDescription)
        }

        logStatus("Connected to \(client.displayName(for: device))")
    }

    // MARK: - Auto-Reconnect

    private func setupAutoReconnect() {
        client.onDisconnected = { [weak self] _ in
            guard let self else { return }
            logStatus("Device disconnected — watching for reconnection...")
            Task { @MainActor [weak self] in
                guard let self else { return }
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if let device = self.client.discoveredDevices.first(matching: self.deviceFilter) {
                        logStatus("Reconnecting to \(device.name)...")
                        self.client.connect(to: device)
                        let deadline = Date().addingTimeInterval(10)
                        while self.client.connectionState != .connected {
                            if Date() > deadline { break }
                            if case .failed = self.client.connectionState { break }
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                        if self.client.connectionState == .connected {
                            logStatus("Reconnected to \(device.name)")
                            return
                        }
                    }
                }
                logStatus("Auto-reconnect gave up after 60 attempts")
            }
        }
    }

    // MARK: - Input Processing

    private func processLine(_ line: String) async -> (SessionResponse, Any?) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = obj["command"] as? String else {
            return (.error("Invalid JSON or missing 'command' field"), nil)
        }

        let requestId = obj["id"]

        do {
            let response = try await dispatch(command: command, args: obj)
            return (response, requestId)
        } catch SessionError.notConnected {
            return (.error("Not connected to device"), requestId)
        } catch SessionError.actionTimeout {
            return (.error("Action timed out — connection lost, reconnecting..."), requestId)
        } catch {
            return (.error("Internal error: \(error.localizedDescription)"), requestId)
        }
    }

    // MARK: - Command Dispatch

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func dispatch(command: String, args: [String: Any]) async throws -> SessionResponse {
        switch command {

        // MARK: Session-local

        case "help":
            let commands = [
                "help", "status", "quit", "exit",
                "list_devices",
                "get_interface", "get_screen", "wait_for_idle",
                "tap", "long_press", "swipe", "drag", "pinch", "rotate",
                "two_finger_tap", "draw_path", "draw_bezier",
                "activate", "increment", "decrement", "perform_custom_action",
                "type_text", "edit_action", "dismiss_keyboard",
                "start_recording", "stop_recording",
            ]
            return .help(commands: commands)

        case "status":
            let connected = client.connectionState == .connected
            let name = client.connectedDevice.map { client.displayName(for: $0) }
            return .status(connected: connected, deviceName: name)

        case "quit", "exit":
            shouldExit = true
            isRunning = false
            return .ok(message: "bye")

        case "list_devices":
            return .devices(client.discoveredDevices)

        // MARK: Read

        case "get_interface":
            let iface = try await requestInterface()
            return .interface(iface)

        case "get_screen":
            guard client.connectionState == .connected else {
                throw SessionError.notConnected
            }
            client.send(.requestScreen)
            do {
                let screen = try await client.waitForScreen(timeout: 30)
                if let outputPath = stringArg(args, "output") {
                    guard let pngData = Data(base64Encoded: screen.pngData) else {
                        return .error("Failed to decode screenshot data")
                    }
                    try pngData.write(to: URL(fileURLWithPath: outputPath))
                    return .screenshot(path: outputPath, width: screen.width, height: screen.height)
                } else {
                    return .screenshotData(pngData: screen.pngData, width: screen.width, height: screen.height)
                }
            } catch {
                client.forceDisconnect()
                throw SessionError.actionTimeout
            }

        case "wait_for_idle":
            return try await sendAction(.waitForIdle(WaitForIdleTarget(timeout: doubleArg(args, "timeout"))))

        // MARK: Touch Gestures

        case "tap":
            let target = elementTarget(args)
            let x = doubleArg(args, "x"), y = doubleArg(args, "y")
            let message: ClientMessage
            if let target {
                message = .touchTap(TouchTapTarget(elementTarget: target))
            } else if let x, let y {
                message = .touchTap(TouchTapTarget(pointX: x, pointY: y))
            } else {
                return .error("Must specify element (identifier or order) or coordinates (x, y)")
            }
            return try await sendAction(message)

        case "long_press":
            let target = elementTarget(args)
            let x = doubleArg(args, "x"), y = doubleArg(args, "y")
            let duration = doubleArg(args, "duration") ?? 0.5
            let message: ClientMessage
            if let target {
                message = .touchLongPress(LongPressTarget(elementTarget: target, duration: duration))
            } else if let x, let y {
                message = .touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration))
            } else {
                return .error("Must specify element (identifier or order) or coordinates (x, y)")
            }
            return try await sendAction(message)

        case "swipe":
            let target = elementTarget(args)
            let startX = doubleArg(args, "startX"), startY = doubleArg(args, "startY")
            let endX = doubleArg(args, "endX"), endY = doubleArg(args, "endY")
            let dirStr = stringArg(args, "direction")
            var direction: SwipeDirection?
            if let dirStr {
                direction = SwipeDirection(rawValue: dirStr.lowercased())
                if direction == nil {
                    return .error("Invalid direction '\(dirStr)'. Valid: up, down, left, right")
                }
            }
            return try await sendAction(.touchSwipe(SwipeTarget(
                elementTarget: target,
                startX: startX, startY: startY,
                endX: endX, endY: endY,
                direction: direction,
                distance: doubleArg(args, "distance"),
                duration: doubleArg(args, "duration")
            )))

        case "drag":
            guard let endX = doubleArg(args, "endX"), let endY = doubleArg(args, "endY") else {
                return .error("endX and endY are required for drag")
            }
            return try await sendAction(.touchDrag(DragTarget(
                elementTarget: elementTarget(args),
                startX: doubleArg(args, "startX"), startY: doubleArg(args, "startY"),
                endX: endX, endY: endY,
                duration: doubleArg(args, "duration")
            )))

        case "pinch":
            guard let scale = doubleArg(args, "scale") else {
                return .error("scale is required for pinch")
            }
            return try await sendAction(.touchPinch(PinchTarget(
                elementTarget: elementTarget(args),
                centerX: doubleArg(args, "centerX"), centerY: doubleArg(args, "centerY"),
                scale: scale,
                spread: doubleArg(args, "spread"),
                duration: doubleArg(args, "duration")
            )))

        case "rotate":
            guard let angle = doubleArg(args, "angle") else {
                return .error("angle is required for rotate")
            }
            return try await sendAction(.touchRotate(RotateTarget(
                elementTarget: elementTarget(args),
                centerX: doubleArg(args, "centerX"), centerY: doubleArg(args, "centerY"),
                angle: angle,
                radius: doubleArg(args, "radius"),
                duration: doubleArg(args, "duration")
            )))

        case "two_finger_tap":
            return try await sendAction(.touchTwoFingerTap(TwoFingerTapTarget(
                elementTarget: elementTarget(args),
                centerX: doubleArg(args, "centerX"), centerY: doubleArg(args, "centerY"),
                spread: doubleArg(args, "spread")
            )))

        case "draw_path":
            guard let pointsArray = args["points"] as? [[String: Any]] else {
                return .error("points must be an array of {x, y} objects")
            }
            var pathPoints: [PathPoint] = []
            for pt in pointsArray {
                guard let x = (pt["x"] as? Double) ?? (pt["x"] as? Int).map(Double.init),
                      let y = (pt["y"] as? Double) ?? (pt["y"] as? Int).map(Double.init) else {
                    return .error("Each point must have numeric x and y fields")
                }
                pathPoints.append(PathPoint(x: x, y: y))
            }
            guard pathPoints.count >= 2 else {
                return .error("Path requires at least 2 points")
            }
            return try await sendAction(.touchDrawPath(DrawPathTarget(
                points: pathPoints,
                duration: doubleArg(args, "duration"),
                velocity: doubleArg(args, "velocity")
            )))

        case "draw_bezier":
            guard let startX = doubleArg(args, "startX"), let startY = doubleArg(args, "startY") else {
                return .error("startX and startY are required")
            }
            guard let segmentsArray = args["segments"] as? [[String: Any]] else {
                return .error("segments array is required")
            }
            var segments: [BezierSegment] = []
            for seg in segmentsArray {
                guard let cp1X = (seg["cp1X"] as? Double) ?? (seg["cp1X"] as? Int).map(Double.init),
                      let cp1Y = (seg["cp1Y"] as? Double) ?? (seg["cp1Y"] as? Int).map(Double.init),
                      let cp2X = (seg["cp2X"] as? Double) ?? (seg["cp2X"] as? Int).map(Double.init),
                      let cp2Y = (seg["cp2Y"] as? Double) ?? (seg["cp2Y"] as? Int).map(Double.init),
                      let endX = (seg["endX"] as? Double) ?? (seg["endX"] as? Int).map(Double.init),
                      let endY = (seg["endY"] as? Double) ?? (seg["endY"] as? Int).map(Double.init) else {
                    return .error("Each segment needs cp1X, cp1Y, cp2X, cp2Y, endX, endY")
                }
                segments.append(BezierSegment(
                    cp1X: cp1X, cp1Y: cp1Y, cp2X: cp2X, cp2Y: cp2Y, endX: endX, endY: endY
                ))
            }
            guard !segments.isEmpty else {
                return .error("At least 1 bezier segment is required")
            }
            return try await sendAction(.touchDrawBezier(DrawBezierTarget(
                startX: startX, startY: startY,
                segments: segments,
                samplesPerSegment: intArg(args, "samplesPerSegment"),
                duration: doubleArg(args, "duration"),
                velocity: doubleArg(args, "velocity")
            )))

        // MARK: Accessibility Actions

        case "activate":
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            return try await sendAction(.activate(target))

        case "increment":
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            return try await sendAction(.increment(target))

        case "decrement":
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            return try await sendAction(.decrement(target))

        case "perform_custom_action":
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            guard let actionName = stringArg(args, "actionName") else {
                return .error("actionName is required")
            }
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: actionName)
            ))

        // MARK: Text / Keyboard

        case "type_text":
            let text = stringArg(args, "text")
            let deleteCount = intArg(args, "deleteCount")
            guard text != nil || deleteCount != nil else {
                return .error("Must specify text, deleteCount, or both")
            }
            guard client.connectionState == .connected else {
                throw SessionError.notConnected
            }
            client.send(.typeText(TypeTextTarget(
                text: text,
                deleteCount: deleteCount,
                elementTarget: elementTarget(args)
            )))
            do {
                let result = try await client.waitForActionResult(timeout: 30)
                return .action(result: result)
            } catch {
                client.forceDisconnect()
                throw SessionError.actionTimeout
            }

        case "edit_action":
            guard let action = stringArg(args, "action") else {
                return .error("action is required (copy, paste, cut, select, selectAll)")
            }
            return try await sendAction(.editAction(EditActionTarget(action: action)))

        case "dismiss_keyboard":
            return try await sendAction(.resignFirstResponder)

        // MARK: Recording

        case "start_recording":
            guard client.connectionState == .connected else {
                throw SessionError.notConnected
            }
            let config = RecordingConfig(
                fps: intArg(args, "fps"),
                scale: doubleArg(args, "scale"),
                inactivityTimeout: doubleArg(args, "inactivity_timeout"),
                maxDuration: doubleArg(args, "max_duration")
            )
            client.send(.startRecording(config))
            return .ok(message: "Recording started")

        case "stop_recording":
            guard client.connectionState == .connected else {
                throw SessionError.notConnected
            }
            client.send(.stopRecording)
            do {
                let recording = try await client.waitForRecording(timeout: 30)
                if let outputPath = stringArg(args, "output") {
                    guard let videoData = Data(base64Encoded: recording.videoData) else {
                        return .error("Failed to decode video data")
                    }
                    try videoData.write(to: URL(fileURLWithPath: outputPath))
                    return .recording(path: outputPath, payload: recording)
                } else {
                    return .recordingData(payload: recording)
                }
            } catch {
                client.forceDisconnect()
                throw SessionError.actionTimeout
            }

        default:
            return .error("Unknown command: \(command). Send {\"command\":\"help\"} for available commands.")
        }
    }

    // MARK: - Action Helpers

    private func sendAction(_ message: ClientMessage) async throws -> SessionResponse {
        guard client.connectionState == .connected else {
            throw SessionError.notConnected
        }
        client.send(message)
        do {
            let result = try await client.waitForActionResult(timeout: 15)
            return .action(result: result)
        } catch {
            client.forceDisconnect()
            throw SessionError.actionTimeout
        }
    }

    private func requestInterface() async throws -> Interface {
        guard client.connectionState == .connected else {
            throw SessionError.notConnected
        }
        client.send(.requestInterface)
        do {
            return try await withCheckedThrowingContinuation { continuation in
                var didResume = false
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    if !didResume {
                        didResume = true
                        continuation.resume(throwing: HeistClient.ActionError.timeout)
                    }
                }
                client.onInterfaceUpdate = { payload in
                    if !didResume {
                        didResume = true
                        timeoutTask.cancel()
                        continuation.resume(returning: payload)
                    }
                }
            }
        } catch {
            client.forceDisconnect()
            throw SessionError.actionTimeout
        }
    }

    // MARK: - Arg Extraction Helpers

    private func stringArg(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    private func intArg(_ dict: [String: Any], _ key: String) -> Int? {
        if let i = dict[key] as? Int { return i }
        if let d = dict[key] as? Double { return Int(d) }
        return nil
    }

    private func doubleArg(_ dict: [String: Any], _ key: String) -> Double? {
        if let d = dict[key] as? Double { return d }
        if let i = dict[key] as? Int { return Double(i) }
        return nil
    }

    private func elementTarget(_ dict: [String: Any]) -> ActionTarget? {
        let id = stringArg(dict, "identifier")
        let order = intArg(dict, "order")
        guard id != nil || order != nil else { return nil }
        return ActionTarget(identifier: id, order: order)
    }

    // MARK: - Output

    private func outputResponse(_ response: SessionResponse, id: Any?) {
        switch format {
        case .human:
            writeOutput(response.humanFormatted())
        case .json:
            if var dict = response.jsonDict() {
                if let id { dict["id"] = id }
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    writeOutput(json)
                }
            }
        }
    }
}
