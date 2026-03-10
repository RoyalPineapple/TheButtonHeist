import Foundation

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
                  Another driver is currently connected. Wait for it to disconnect
                  or for the session to time out.
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

@ButtonHeistActor
public final class TheFence {
    public struct Configuration {
        public var deviceFilter: String?
        public var connectionTimeout: TimeInterval
        public var token: String?
        public var autoReconnect: Bool

        public init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            token: String? = nil,
            autoReconnect: Bool = true
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.token = token
            self.autoReconnect = autoReconnect
        }
    }

    public static let supportedCommands: [String] = Command.allCases.map(\.rawValue)

    public var onStatus: ((String) -> Void)? {
        didSet { client.handoff.onStatus = onStatus }
    }
    public var onAuthApproved: ((String?) -> Void)?

    let config: Configuration
    let client = TheMastermind()
    private var isStarted = false

    public init(configuration: Configuration = .init()) {
        self.config = configuration
        self.client.token = configuration.token ?? ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"]
        self.client.driverId = ProcessInfo.processInfo.environment["BUTTONHEIST_DRIVER_ID"]
        self.client.autoSubscribe = true
        self.client.onAuthApproved = { [weak self] token in
            if let token {
                self?.onStatus?("BUTTONHEIST_TOKEN=\(token)")
            }
            self?.onAuthApproved?(token)
        }
    }

    public func start() async throws {
        if isStarted, client.connectionState == .connected {
            return
        }

        try await connect()
        if config.autoReconnect {
            let filter = config.deviceFilter ?? ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
            client.handoff.setupAutoReconnect(filter: filter)
        }
        isStarted = true
    }

    public func stop() {
        client.disconnect()
        client.stopDiscovery()
        isStarted = false
    }

    public func execute(request: [String: Any]) async throws -> FenceResponse {
        guard let commandString = request["command"] as? String else {
            throw FenceError.invalidRequest("Invalid JSON or missing 'command' field")
        }
        guard let command = Command(rawValue: commandString) else {
            return .error("Unknown command: \(commandString). Use 'help' for available commands.")
        }

        if command == .help {
            return .help(commands: Self.supportedCommands)
        }

        if command == .quit || command == .exit {
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
            try await client.handoff.connectWithDiscovery(
                filter: filter,
                timeout: config.connectionTimeout
            )
        } catch let error as TheHandoff.ConnectionError {
            throw error.asFenceError()
        }
    }

    // MARK: - Command Dispatch (thin router)

    private func dispatch(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .status:
            return .status(
                connected: client.connectionState == .connected,
                deviceName: client.connectedDevice.map { client.displayName(for: $0) }
            )
        case .listDevices:
            return .devices(client.discoveredDevices)
        case .getInterface:
            return .interface(try await handleGetInterface())
        case .getScreen:
            return try await handleGetScreen(args)
        case .waitForIdle:
            return try await sendAction(.waitForIdle(WaitForIdleTarget(timeout: doubleArg(args, "timeout"))))
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate, .twoFingerTap,
             .drawPath, .drawBezier:
            return try await handleGesture(command: command, args: args)
        case .scroll, .scrollToVisible, .scrollToEdge:
            return try await handleScrollAction(command: command, args: args)
        case .activate, .increment, .decrement, .performCustomAction:
            return try await handleAccessibilityAction(command: command, args: args)
        case .typeText:
            return try await handleTypeText(args)
        case .editAction:
            return try await handleEditAction(args)
        case .dismissKeyboard:
            return try await sendAction(.resignFirstResponder)
        case .startRecording:
            return try await handleStartRecording(args)
        case .stopRecording:
            return try await handleStopRecording(args)
        case .help, .quit, .exit:
            return .error("Unexpected command in dispatch: \(command.rawValue)")
        }
    }

    // MARK: - Send Action (shared)

    func sendAction(_ message: ClientMessage) async throws -> FenceResponse {
        let result: ActionResult = try await sendAndAwait(message) { requestId in
            try await client.waitForActionResult(requestId: requestId, timeout: Timeouts.actionSeconds)
        }
        return .action(result: result)
    }

    func sendAndAwait<T>(_ message: ClientMessage, response: (_ requestId: String) async throws -> T) async throws -> T {
        guard client.connectionState == .connected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        client.send(message, requestId: requestId)
        do {
            return try await response(requestId)
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

    func stringArg(_ dictionary: [String: Any], _ key: String) -> String? {
        dictionary[key] as? String
    }

    func intArg(_ dictionary: [String: Any], _ key: String) -> Int? {
        if let value = dictionary[key] as? Int { return value }
        if let value = dictionary[key] as? Double { return Int(value) }
        if let value = dictionary[key] as? String { return Int(value) }
        return nil
    }

    func doubleArg(_ dictionary: [String: Any], _ key: String) -> Double? {
        numberArg(dictionary[key])
    }

    func numberArg(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    func elementTarget(_ dictionary: [String: Any]) -> ActionTarget? {
        let identifier = stringArg(dictionary, "identifier")
        let order = intArg(dictionary, "order")
        guard identifier != nil || order != nil else { return nil }
        return ActionTarget(identifier: identifier, order: order)
    }
}

// MARK: - ConnectionError → FenceError Bridge

extension TheHandoff.ConnectionError {
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
