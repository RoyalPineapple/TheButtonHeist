import Foundation
import TheScore
import Wheelman

public enum FenceError: Error, LocalizedError {
    case invalidRequest(String)
    case noDeviceFound
    case noMatchingDevice(filter: String, available: [String])
    case connectionTimeout
    case connectionFailed(String)
    case sessionLocked(String)
    case authFailed(String)
    case notConnected
    case actionTimeout
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return message
        case .noDeviceFound:
            return "No devices found within timeout. Is the app running?"
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            return "No device matching '\(filter)'. Available: \(list)"
        case .connectionTimeout:
            return """
                Connection timed out
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
                """
        case .connectionFailed(let message):
            return """
                Connection failed: \(message)
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
                """
        case .sessionLocked(let message):
            return """
                Session locked: \(message)
                  Another driver is currently connected. Wait for it to finish,
                  or use --force to take over the session.
                """
        case .authFailed(let message):
            return """
                Auth failed: \(message)
                  Retry without --token to request a fresh session.
                """
        case .notConnected:
            return "Not connected to device"
        case .actionTimeout:
            return "Action timed out — connection lost, reconnecting..."
        case .actionFailed(let message):
            return "Action failed: \(message)"
        }
    }
}

public enum FenceResponse {
    case ok(message: String)
    case error(String)
    case help(commands: [String])
    case status(connected: Bool, deviceName: String?)
    case devices([DiscoveredDevice])
    case interface(Interface)
    case action(result: ActionResult)
    case screenshot(path: String, width: Double, height: Double)
    case screenshotData(pngData: String, width: Double, height: Double)
    case recording(path: String, payload: RecordingPayload)
    case recordingData(payload: RecordingPayload)

    public func humanFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message):
            return "Error: \(message)"
        case .help(let commands):
            return "Commands:\n" + commands.map { "  \($0)" }.joined(separator: "\n")
        case .status(let connected, let deviceName):
            if connected, let name = deviceName {
                return "Connected to \(name)"
            }
            return "Not connected"
        case .devices(let devices):
            if devices.isEmpty { return "No devices found" }
            var output = "\(devices.count) device(s):\n"
            for (index, device) in devices.enumerated() {
                let id = device.shortId ?? "----"
                output += "  [\(index)] \(id)  \(device.appName)  (\(device.deviceName))\n"
            }
            return output.trimmingCharacters(in: .newlines)
        case .interface(let interface):
            return formatInterface(interface)
        case .action(let result):
            return formatActionResult(result)
        case .screenshot(let path, let width, let height):
            return "✓ Screenshot saved: \(path)  (\(Int(width)) × \(Int(height)))"
        case .screenshotData(let pngData, let width, let height):
            return "✓ Screenshot captured (\(Int(width)) × \(Int(height))) — base64 PNG follows\n\(pngData)"
        case .recording(let path, let payload):
            let duration = String(format: "%.1f", payload.duration)
            var text = "✓ Recording saved: \(path)  (\(payload.width)×\(payload.height), \(duration)s, \(payload.frameCount) frames, \(payload.stopReason.rawValue))"
            if let log = payload.interactionLog {
                text += "\n  Interactions: \(log.count)"
            }
            return text
        case .recordingData(let payload):
            let sizeKB = payload.videoData.count * 3 / 4 / 1024
            let duration = String(format: "%.1f", payload.duration)
            var text = "✓ Recording captured (\(payload.width)×\(payload.height), \(duration)s, \(payload.frameCount) frames, ~\(sizeKB)KB, \(payload.stopReason.rawValue))"
            if let log = payload.interactionLog {
                text += "\n  Interactions: \(log.count)"
            }
            return text
        }
    }

    public func jsonDict() -> [String: Any]? {
        switch self {
        case .ok(let message):
            return ["status": "ok", "message": message]
        case .error(let message):
            return ["status": "error", "message": message]
        case .help(let commands):
            return ["status": "ok", "commands": commands]
        case .status(let connected, let deviceName):
            var payload: [String: Any] = ["status": "ok", "connected": connected]
            if let deviceName { payload["device"] = deviceName }
            return payload
        case .devices(let devices):
            let info = devices.map { device -> [String: Any] in
                var payload: [String: Any] = [
                    "name": device.name,
                    "appName": device.appName,
                    "deviceName": device.deviceName,
                ]
                if let shortId = device.shortId { payload["shortId"] = shortId }
                if let simulatorUDID = device.simulatorUDID { payload["simulatorUDID"] = simulatorUDID }
                return payload
            }
            return ["status": "ok", "devices": info]
        case .interface(let interface):
            return ["status": "ok", "interface": interfaceDictionary(interface)]
        case .action(let result):
            var payload: [String: Any] = [
                "status": result.success ? "ok" : "error",
                "method": result.method.rawValue,
            ]
            if let message = result.message { payload["message"] = message }
            if let value = result.value { payload["value"] = value }
            if result.animating == true { payload["animating"] = true }
            if let delta = result.interfaceDelta {
                payload["delta"] = deltaDictionary(delta)
            }
            return payload
        case .screenshot(let path, let width, let height):
            return ["status": "ok", "path": path, "width": width, "height": height]
        case .screenshotData(let pngData, let width, let height):
            return ["status": "ok", "pngData": pngData, "width": width, "height": height]
        case .recording(let path, let payload):
            var dict: [String: Any] = [
                "status": "ok",
                "path": path,
                "width": payload.width,
                "height": payload.height,
                "duration": payload.duration,
                "frameCount": payload.frameCount,
                "fps": payload.fps,
                "stopReason": payload.stopReason.rawValue,
                "interactionCount": payload.interactionLog?.count ?? 0,
            ]
            if let logDicts = encodeInteractionLog(payload.interactionLog) {
                dict["interactionLog"] = logDicts
            }
            return dict
        case .recordingData(let payload):
            var dict: [String: Any] = [
                "status": "ok",
                "videoData": payload.videoData,
                "width": payload.width,
                "height": payload.height,
                "duration": payload.duration,
                "frameCount": payload.frameCount,
                "fps": payload.fps,
                "stopReason": payload.stopReason.rawValue,
                "interactionCount": payload.interactionLog?.count ?? 0,
            ]
            if let logDicts = encodeInteractionLog(payload.interactionLog) {
                dict["interactionLog"] = logDicts
            }
            return dict
        }
    }

    private func encodeInteractionLog(_ events: [InteractionEvent]?) -> [[String: Any]]? {
        guard let events, !events.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array
    }

    private func formatInterface(_ interface: Interface) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = "\(interface.elements.count) elements (\(formatter.string(from: interface.timestamp)))\n"
        output += String(repeating: "-", count: 60) + "\n"

        if interface.elements.isEmpty {
            output += "  (no elements)\n"
        } else {
            for element in interface.elements {
                output += formatElement(element)
            }
        }
        output += String(repeating: "-", count: 60)
        return output
    }

    private func formatElement(_ element: HeistElement) -> String {
        var output = ""
        let index = String(format: "  [%2d]", element.order)
        let label = element.label ?? element.description
        output += "\(index) \(label)\n"

        if let value = element.value, !value.isEmpty {
            output += "       Value: \(value)\n"
        }
        if let identifier = element.identifier, !identifier.isEmpty {
            output += "       ID: \(identifier)\n"
        }
        if !element.actions.isEmpty {
            output += "       Actions: \(element.actions.map(\.description).joined(separator: ", "))\n"
        }
        output += "       Frame: (\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))\n"
        return output
    }

    private func formatActionResult(_ result: ActionResult) -> String {
        if result.success {
            var output = "✓ \(result.method.rawValue)"
            if let value = result.value {
                output += "  value: \"\(value)\""
            }
            if let delta = result.interfaceDelta {
                output += "  \(formatDelta(delta))"
            }
            if result.animating == true {
                output += "  (still animating)"
            }
            return output
        }
        return "Error: \(result.message ?? result.method.rawValue)"
    }

    private func formatDelta(_ delta: InterfaceDelta) -> String {
        switch delta.kind {
        case .noChange:
            return "[\(delta.elementCount) elements, no change]"
        case .valuesChanged:
            let count = delta.valueChanges?.count ?? 0
            return "[\(delta.elementCount) elements, \(count) value\(count == 1 ? "" : "s") changed]"
        case .elementsChanged:
            let added = delta.added?.count ?? 0
            let removed = delta.removedOrders?.count ?? 0
            var parts: [String] = ["\(delta.elementCount) elements"]
            if added > 0 { parts.append("+\(added) added") }
            if removed > 0 { parts.append("-\(removed) removed") }
            return "[" + parts.joined(separator: ", ") + "]"
        case .screenChanged:
            return "[\(delta.elementCount) elements, screen changed]"
        }
    }

    private func interfaceDictionary(_ interface: Interface) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "timestamp": formatter.string(from: interface.timestamp),
            "elements": interface.elements.map(elementDictionary)
        ]
        if let tree = interface.tree {
            payload["tree"] = tree.map(elementNodeDictionary)
        }
        return payload
    }

    private func elementDictionary(_ element: HeistElement) -> [String: Any] {
        var payload: [String: Any] = [
            "order": element.order,
            "description": element.description,
            "traits": element.traits,
            "frameX": element.frameX,
            "frameY": element.frameY,
            "frameWidth": element.frameWidth,
            "frameHeight": element.frameHeight,
            "activationPointX": element.activationPointX,
            "activationPointY": element.activationPointY,
            "respondsToUserInteraction": element.respondsToUserInteraction,
            "actions": element.actions.map(\.description),
        ]
        if let label = element.label { payload["label"] = label }
        if let value = element.value { payload["value"] = value }
        if let identifier = element.identifier { payload["identifier"] = identifier }
        if let hint = element.hint { payload["hint"] = hint }
        if let customContent = element.customContent {
            payload["customContent"] = customContent.map {
                [
                    "label": $0.label,
                    "value": $0.value,
                    "isImportant": $0.isImportant
                ]
            }
        }
        return payload
    }

    private func elementNodeDictionary(_ node: ElementNode) -> [String: Any] {
        switch node {
        case .element(let order):
            return ["element": ["order": order]]
        case .container(let group, let children):
            return [
                "container": [
                    "_0": groupDictionary(group),
                    "children": children.map(elementNodeDictionary)
                ]
            ]
        }
    }

    private func groupDictionary(_ group: Group) -> [String: Any] {
        var payload: [String: Any] = [
            "type": group.type,
            "frameX": group.frameX,
            "frameY": group.frameY,
            "frameWidth": group.frameWidth,
            "frameHeight": group.frameHeight
        ]
        if let label = group.label { payload["label"] = label }
        if let value = group.value { payload["value"] = value }
        if let identifier = group.identifier { payload["identifier"] = identifier }
        return payload
    }

    private func deltaDictionary(_ delta: InterfaceDelta) -> [String: Any] {
        var payload: [String: Any] = [
            "kind": delta.kind.rawValue,
            "elementCount": delta.elementCount
        ]
        if let added = delta.added {
            payload["added"] = added.map(elementDictionary)
        }
        if let removedOrders = delta.removedOrders {
            payload["removedOrders"] = removedOrders
        }
        if let valueChanges = delta.valueChanges {
            payload["valueChanges"] = valueChanges.map { change in
                var valuePayload: [String: Any] = ["order": change.order]
                if let identifier = change.identifier { valuePayload["identifier"] = identifier }
                if let oldValue = change.oldValue { valuePayload["oldValue"] = oldValue }
                if let newValue = change.newValue { valuePayload["newValue"] = newValue }
                return valuePayload
            }
        }
        if let newInterface = delta.newInterface {
            payload["newInterface"] = interfaceDictionary(newInterface)
        }
        return payload
    }
}

/// Named timeout constants for TheFence operations.
/// Action timeout (15s) covers most single-gesture/tap operations.
/// Long action timeout (30s) covers text entry, screenshots, and recordings which may involve
/// larger payloads or slower responses.
/// Interface request timeout (10s) is shorter because it only needs to retrieve the current
/// element tree, which should already be cached on the server side.
public enum Timeouts {
    /// Standard action timeout (15 seconds) - for tap, swipe, gesture, accessibility actions
    static let action: UInt64 = 15_000_000_000
    /// Same as `action` but expressed in seconds for APIs that take TimeInterval
    static let actionSeconds: TimeInterval = 15

    /// Long action timeout (30 seconds) - for type_text, screenshots, recordings
    static let longAction: UInt64 = 30_000_000_000
    /// Same as `longAction` but expressed in seconds for APIs that take TimeInterval
    static let longActionSeconds: TimeInterval = 30

    /// Interface request timeout (10 seconds) - for get_interface
    static let interfaceRequest: UInt64 = 10_000_000_000
}

@MainActor
public final class TheFence {
    public struct Configuration {
        public var deviceFilter: String?
        public var connectionTimeout: TimeInterval
        public var forceSession: Bool
        public var token: String?
        public var autoReconnect: Bool

        public init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            forceSession: Bool = false,
            token: String? = nil,
            autoReconnect: Bool = true
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.forceSession = forceSession
            self.token = token
            self.autoReconnect = autoReconnect
        }
    }

    public static let supportedCommands = CommandCatalog.all

    public var onStatus: ((String) -> Void)? {
        didSet { client.wheelman.onStatus = onStatus }
    }
    public var onTokenReceived: ((String) -> Void)?

    private let config: Configuration
    private let client = TheMastermind()
    private var isStarted = false

    public init(configuration: Configuration = .init()) {
        self.config = configuration
        self.client.token = configuration.token ?? ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"]
        self.client.forceSession = configuration.forceSession
        self.client.driverId = ProcessInfo.processInfo.environment["BUTTONHEIST_DRIVER_ID"]
        self.client.autoSubscribe = false
        self.client.onTokenReceived = { [weak self] token in
            self?.onStatus?("BUTTONHEIST_TOKEN=\(token)")
            self?.onTokenReceived?(token)
        }
    }

    public func start() async throws {
        if isStarted, client.connectionState == .connected {
            return
        }

        try await connect()
        if config.autoReconnect {
            let filter = config.deviceFilter ?? ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
            client.wheelman.setupAutoReconnect(filter: filter)
        }
        isStarted = true
    }

    public func stop() {
        client.disconnect()
        client.stopDiscovery()
        isStarted = false
    }

    public func execute(request: [String: Any]) async throws -> FenceResponse {
        guard let command = request["command"] as? String else {
            throw FenceError.invalidRequest("Invalid JSON or missing 'command' field")
        }

        if command == "help" {
            return .help(commands: Self.supportedCommands)
        }

        if command == "quit" || command == "exit" {
            stop()
            return .ok(message: "bye")
        }

        if !isStarted || client.connectionState != .connected {
            try await start()
        }

        return try await dispatch(command: command, args: request)
    }

    private func connect() async throws {
        let filter = config.deviceFilter ?? ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
        do {
            try await client.wheelman.connectWithDiscovery(
                filter: filter,
                timeout: config.connectionTimeout
            )
        } catch let error as TheWheelman.ConnectionError {
            throw error.asFenceError()
        }
    }

    // MARK: - Command Dispatch (thin router)

    private func dispatch(command: String, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case "status":
            return .status(
                connected: client.connectionState == .connected,
                deviceName: client.connectedDevice.map { client.displayName(for: $0) }
            )
        case "list_devices":
            return .devices(client.discoveredDevices)
        case "get_interface":
            return .interface(try await handleGetInterface())
        case "get_screen":
            return try await handleGetScreen(args)
        case "wait_for_idle":
            return try await sendAction(.waitForIdle(WaitForIdleTarget(timeout: doubleArg(args, "timeout"))))
        case "one_finger_tap", "long_press", "swipe", "drag", "pinch", "rotate", "two_finger_tap",
             "draw_path", "draw_bezier":
            return try await handleGesture(command: command, args: args)
        case "scroll", "scroll_to_visible", "scroll_to_edge":
            return try await handleScrollAction(command: command, args: args)
        case "activate", "increment", "decrement", "perform_custom_action":
            return try await handleAccessibilityAction(command: command, args: args)
        case "type_text":
            return try await handleTypeText(args)
        case "edit_action":
            return try await handleEditAction(args)
        case "dismiss_keyboard":
            return try await sendAction(.resignFirstResponder)
        case "start_recording":
            return try await handleStartRecording(args)
        case "stop_recording":
            return try await handleStopRecording(args)
        default:
            return .error("Unknown command: \(command). Use 'help' for available commands.")
        }
    }

    // MARK: - Handler: Interface

    private func handleGetInterface() async throws -> Interface {
        try await sendAndAwait(.requestInterface) {
            try await client.waitForInterface(timeout: Timeouts.actionSeconds)
        }
    }

    // MARK: - Handler: Screen

    private func handleGetScreen(_ args: [String: Any]) async throws -> FenceResponse {
        let screen: ScreenPayload = try await sendAndAwait(.requestScreen) {
            try await client.waitForScreen(timeout: 30)
        }
        if let outputPath = stringArg(args, "output") {
            guard let pngData = Data(base64Encoded: screen.pngData) else {
                return .error("Failed to decode screenshot data")
            }
            try pngData.write(to: URL(fileURLWithPath: outputPath))
            return .screenshot(path: outputPath, width: screen.width, height: screen.height)
        }
        return .screenshotData(pngData: screen.pngData, width: screen.width, height: screen.height)
    }

    // MARK: - Handler: Gestures

    private func handleGesture(command: String, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case "one_finger_tap":
            let target = elementTarget(args)
            let x = doubleArg(args, "x")
            let y = doubleArg(args, "y")
            if let target {
                return try await sendAction(.touchTap(TouchTapTarget(elementTarget: target)))
            } else if let x, let y {
                return try await sendAction(.touchTap(TouchTapTarget(pointX: x, pointY: y)))
            }
            return .error("Must specify element (identifier or order) or coordinates (x, y)")

        case "long_press":
            let target = elementTarget(args)
            let x = doubleArg(args, "x")
            let y = doubleArg(args, "y")
            let duration = doubleArg(args, "duration") ?? 0.5
            if let target {
                return try await sendAction(.touchLongPress(LongPressTarget(elementTarget: target, duration: duration)))
            } else if let x, let y {
                return try await sendAction(.touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration)))
            }
            return .error("Must specify element (identifier or order) or coordinates (x, y)")

        case "swipe":
            let directionValue = stringArg(args, "direction")
            var direction: SwipeDirection?
            if let directionValue {
                direction = SwipeDirection(rawValue: directionValue.lowercased())
                if direction == nil {
                    return .error("Invalid direction '\(directionValue)'. Valid: up, down, left, right")
                }
            }
            return try await sendAction(
                .touchSwipe(SwipeTarget(
                    elementTarget: elementTarget(args),
                    startX: doubleArg(args, "startX"), startY: doubleArg(args, "startY"),
                    endX: doubleArg(args, "endX"), endY: doubleArg(args, "endY"),
                    direction: direction, distance: doubleArg(args, "distance"),
                    duration: doubleArg(args, "duration")
                ))
            )

        case "drag":
            guard let endX = doubleArg(args, "endX"), let endY = doubleArg(args, "endY") else {
                return .error("endX and endY are required for drag")
            }
            return try await sendAction(
                .touchDrag(DragTarget(
                    elementTarget: elementTarget(args),
                    startX: doubleArg(args, "startX"), startY: doubleArg(args, "startY"),
                    endX: endX, endY: endY, duration: doubleArg(args, "duration")
                ))
            )

        case "pinch":
            guard let scale = doubleArg(args, "scale") else {
                return .error("scale is required for pinch")
            }
            return try await sendAction(
                .touchPinch(PinchTarget(
                    elementTarget: elementTarget(args),
                    centerX: doubleArg(args, "centerX"), centerY: doubleArg(args, "centerY"),
                    scale: scale, spread: doubleArg(args, "spread"),
                    duration: doubleArg(args, "duration")
                ))
            )

        case "rotate":
            guard let angle = doubleArg(args, "angle") else {
                return .error("angle is required for rotate")
            }
            return try await sendAction(
                .touchRotate(RotateTarget(
                    elementTarget: elementTarget(args),
                    centerX: doubleArg(args, "centerX"), centerY: doubleArg(args, "centerY"),
                    angle: angle, radius: doubleArg(args, "radius"),
                    duration: doubleArg(args, "duration")
                ))
            )

        case "two_finger_tap":
            return try await sendAction(
                .touchTwoFingerTap(TwoFingerTapTarget(
                    elementTarget: elementTarget(args),
                    centerX: doubleArg(args, "centerX"), centerY: doubleArg(args, "centerY"),
                    spread: doubleArg(args, "spread")
                ))
            )

        case "draw_path":
            return try await handleDrawPath(args)

        case "draw_bezier":
            return try await handleDrawBezier(args)

        default:
            return .error("Unknown gesture: \(command)")
        }
    }

    private func handleDrawPath(_ args: [String: Any]) async throws -> FenceResponse {
        guard let pointsArray = args["points"] as? [[String: Any]] else {
            return .error("points must be an array of {x, y} objects")
        }
        var pathPoints: [PathPoint] = []
        for point in pointsArray {
            guard let x = numberArg(point["x"]), let y = numberArg(point["y"]) else {
                return .error("Each point must have numeric x and y fields")
            }
            pathPoints.append(PathPoint(x: x, y: y))
        }
        guard pathPoints.count >= 2 else {
            return .error("Path requires at least 2 points")
        }
        return try await sendAction(
            .touchDrawPath(DrawPathTarget(
                points: pathPoints,
                duration: doubleArg(args, "duration"),
                velocity: doubleArg(args, "velocity")
            ))
        )
    }

    private func handleDrawBezier(_ args: [String: Any]) async throws -> FenceResponse {
        guard let startX = doubleArg(args, "startX"), let startY = doubleArg(args, "startY") else {
            return .error("startX and startY are required")
        }
        guard let segmentsArray = args["segments"] as? [[String: Any]] else {
            return .error("segments array is required")
        }
        var segments: [BezierSegment] = []
        for segment in segmentsArray {
            guard
                let cp1X = numberArg(segment["cp1X"]), let cp1Y = numberArg(segment["cp1Y"]),
                let cp2X = numberArg(segment["cp2X"]), let cp2Y = numberArg(segment["cp2Y"]),
                let endX = numberArg(segment["endX"]), let endY = numberArg(segment["endY"])
            else {
                return .error("Each segment needs cp1X, cp1Y, cp2X, cp2Y, endX, endY")
            }
            segments.append(BezierSegment(cp1X: cp1X, cp1Y: cp1Y, cp2X: cp2X, cp2Y: cp2Y, endX: endX, endY: endY))
        }
        guard !segments.isEmpty else {
            return .error("At least 1 bezier segment is required")
        }
        return try await sendAction(
            .touchDrawBezier(DrawBezierTarget(
                startX: startX, startY: startY, segments: segments,
                samplesPerSegment: intArg(args, "samplesPerSegment"),
                duration: doubleArg(args, "duration"), velocity: doubleArg(args, "velocity")
            ))
        )
    }

    // MARK: - Handler: Scroll Actions

    private func handleScrollAction(command: String, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case "scroll":
            guard let directionValue = stringArg(args, "direction") else {
                return .error("direction is required for scroll. Valid: up, down, left, right, next, previous")
            }
            guard let direction = ScrollDirection(rawValue: directionValue.lowercased()) else {
                return .error("Invalid direction '\(directionValue)'. Valid: up, down, left, right, next, previous")
            }
            guard elementTarget(args) != nil else {
                return .error("Must specify element (identifier or order) for scroll")
            }
            return try await sendAction(
                .scroll(ScrollTarget(elementTarget: elementTarget(args), direction: direction))
            )
        case "scroll_to_visible":
            guard let target = elementTarget(args) else {
                return .error("Must specify element (identifier or order) for scroll_to_visible")
            }
            return try await sendAction(.scrollToVisible(target))
        case "scroll_to_edge":
            guard let edgeValue = stringArg(args, "edge") else {
                return .error("edge is required for scroll_to_edge. Valid: top, bottom, left, right")
            }
            guard let edge = ScrollEdge(rawValue: edgeValue.lowercased()) else {
                return .error("Invalid edge '\(edgeValue)'. Valid: top, bottom, left, right")
            }
            guard let target = elementTarget(args) else {
                return .error("Must specify element (identifier or order) for scroll_to_edge")
            }
            return try await sendAction(.scrollToEdge(ScrollToEdgeTarget(elementTarget: target, edge: edge)))
        default:
            return .error("Unknown scroll action: \(command)")
        }
    }

    // MARK: - Handler: Accessibility Actions

    private func handleAccessibilityAction(command: String, args: [String: Any]) async throws -> FenceResponse {
        switch command {
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
            return try await sendAction(.performCustomAction(CustomActionTarget(elementTarget: target, actionName: actionName)))
        default:
            return .error("Unknown accessibility action: \(command)")
        }
    }

    // MARK: - Handler: Text Input

    private func handleTypeText(_ args: [String: Any]) async throws -> FenceResponse {
        let text = stringArg(args, "text")
        let deleteCount = intArg(args, "deleteCount")
        guard text != nil || deleteCount != nil else {
            return .error("Must specify text, deleteCount, or both")
        }
        let result: ActionResult = try await sendAndAwait(.typeText(TypeTextTarget(
            text: text, deleteCount: deleteCount, elementTarget: elementTarget(args)
        ))) {
            try await client.waitForActionResult(timeout: Timeouts.longActionSeconds)
        }
        return .action(result: result)
    }

    private func handleEditAction(_ args: [String: Any]) async throws -> FenceResponse {
        guard let action = stringArg(args, "action") else {
            return .error("action is required (copy, paste, cut, select, selectAll)")
        }
        return try await sendAction(.editAction(EditActionTarget(action: action)))
    }

    // MARK: - Handler: Recording

    private func handleStartRecording(_ args: [String: Any]) async throws -> FenceResponse {
        guard client.connectionState == .connected else { throw FenceError.notConnected }
        let config = RecordingConfig(
            fps: intArg(args, "fps"),
            scale: doubleArg(args, "scale"),
            inactivityTimeout: doubleArg(args, "inactivity_timeout"),
            maxDuration: doubleArg(args, "max_duration")
        )
        client.send(.startRecording(config))
        return .ok(message: "Recording start requested — use stop_recording to retrieve the video")
    }

    private func handleStopRecording(_ args: [String: Any]) async throws -> FenceResponse {
        let recording: RecordingPayload = try await sendAndAwait(.stopRecording) {
            try await client.waitForRecording(timeout: Timeouts.longActionSeconds)
        }
        if let outputPath = stringArg(args, "output") {
            guard let videoData = Data(base64Encoded: recording.videoData) else {
                return .error("Failed to decode video data")
            }
            try videoData.write(to: URL(fileURLWithPath: outputPath))
            return .recording(path: outputPath, payload: recording)
        }
        return .recordingData(payload: recording)
    }

    // MARK: - Send Action (shared)

    private func sendAction(_ message: ClientMessage) async throws -> FenceResponse {
        let result: ActionResult = try await sendAndAwait(message) {
            try await client.waitForActionResult(timeout: Timeouts.actionSeconds)
        }
        return .action(result: result)
    }

    private func sendAndAwait<T>(_ message: ClientMessage, response: () async throws -> T) async throws -> T {
        guard client.connectionState == .connected else { throw FenceError.notConnected }
        client.send(message)
        do {
            return try await response()
        } catch {
            client.forceDisconnect()
            throw mapCaughtError(error)
        }
    }

    /// Map a caught error to an appropriate FenceError, preserving detail.
    private func mapCaughtError(_ error: Error) -> FenceError {
        if error is TheMastermind.ActionError {
            return .actionTimeout
        }
        if let recordingError = error as? TheMastermind.RecordingError {
            switch recordingError {
            case .serverError(let message):
                return .actionFailed(message)
            }
        }
        return .actionFailed(error.localizedDescription)
    }

    private func stringArg(_ dictionary: [String: Any], _ key: String) -> String? {
        dictionary[key] as? String
    }

    private func intArg(_ dictionary: [String: Any], _ key: String) -> Int? {
        if let value = dictionary[key] as? Int { return value }
        if let value = dictionary[key] as? Double { return Int(value) }
        if let value = dictionary[key] as? String { return Int(value) }
        return nil
    }

    private func doubleArg(_ dictionary: [String: Any], _ key: String) -> Double? {
        numberArg(dictionary[key])
    }

    private func numberArg(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func elementTarget(_ dictionary: [String: Any]) -> ActionTarget? {
        let identifier = stringArg(dictionary, "identifier")
        let order = intArg(dictionary, "order")
        guard identifier != nil || order != nil else { return nil }
        return ActionTarget(identifier: identifier, order: order)
    }
}

// MARK: - ConnectionError → FenceError Bridge

extension TheWheelman.ConnectionError {
    func asFenceError() -> FenceError {
        switch self {
        case .noDeviceFound:
            return .noDeviceFound
        case .noMatchingDevice(let filter, let available):
            return .noMatchingDevice(filter: filter, available: available)
        case .connectionTimeout:
            return .connectionTimeout
        case .connectionFailed(let message):
            return .connectionFailed(message)
        case .sessionLocked(let message):
            return .sessionLocked(message)
        case .authFailed(let message):
            return .authFailed(message)
        }
    }
}
