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

        if command != .getSessionState && command != .listDevices &&
            (!isStarted || client.connectionState != .connected) {
            try await start()
        }

        let response = try await dispatch(command: command, args: request)

        // Every action gets implicit delivery validation; higher tiers are additive
        if let actionResult = response.actionResult {
            let delivery = ActionExpectation.validateDelivery(actionResult)
            if !delivery.met {
                return .action(result: actionResult, expectation: delivery)
            }
            if let expectation = try parseExpectation(request) {
                let validation = expectation.validate(against: actionResult)
                return .action(result: actionResult, expectation: validation)
            }
        }

        return response
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
            return .devices(await client.discoverReachableDevices())
        case .getInterface:
            return try await handleGetInterface(args)
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
        case .setPasteboard:
            return try await handleSetPasteboard(args)
        case .getPasteboard:
            return try await handleGetPasteboard()
        case .dismissKeyboard:
            return try await sendAction(.resignFirstResponder)
        case .startRecording:
            return try await handleStartRecording(args)
        case .stopRecording:
            return try await handleStopRecording(args)
        case .runBatch:
            return try await handleRunBatch(args)
        case .getSessionState:
            return .sessionState(payload: currentSessionState())
        case .help, .quit, .exit:
            return .error("Unexpected command in dispatch: \(command.rawValue)")
        }
    }

    // MARK: - Send Action (shared)

    func sendAction(_ message: ClientMessage) async throws -> FenceResponse {
        let result: ActionResult = try await sendAndAwait(message) { requestId in
            try await client.waitForActionResult(requestId: requestId, timeout: Timeouts.actionSeconds)
        }
        lastActionResult = result
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

    func boolArg(_ dictionary: [String: Any], _ key: String) -> Bool? {
        if let value = dictionary[key] as? Bool { return value }
        if let value = dictionary[key] as? Int { return value != 0 }
        if let value = dictionary[key] as? String { return value == "true" || value == "1" }
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
        let heistId = stringArg(dictionary, "heistId")
        let order = intArg(dictionary, "order")
        guard identifier != nil || heistId != nil || order != nil else { return nil }
        return ActionTarget(identifier: identifier, heistId: heistId, order: order)
    }

    // MARK: - Expectation Parsing

    func parseExpectation(_ dictionary: [String: Any]) throws -> ActionExpectation? {
        guard let expect = dictionary["expect"] else { return nil }
        if let str = expect as? String {
            switch str {
            case "screenChanged", "screen_changed":
                return .screenChanged
            case "elementsChanged", "elements_changed",
                 "layoutChanged", "layout_changed":
                return .elementsChanged
            default:
                throw FenceError.invalidRequest(
                    "Unknown expectation tier: \"\(str)\". " +
                    "Valid: screen_changed, elements_changed, or {\"elementUpdated\": {…}}"
                )
            }
        }
        if let dict = expect as? [String: Any] {
            // Accept both new "elementUpdated" and legacy "valueChanged" key
            if let eu = dict["elementUpdated"] as? [String: Any] ?? dict["valueChanged"] as? [String: Any] {
                let property: ElementProperty?
                if let propStr = eu["property"] as? String {
                    guard let p = ElementProperty(rawValue: propStr) else {
                        throw FenceError.invalidRequest(
                            "Unknown element property: \"\(propStr)\". " +
                            "Valid: \(ElementProperty.allCases.map(\.rawValue).joined(separator: ", "))"
                        )
                    }
                    property = p
                } else {
                    property = nil
                }
                return .elementUpdated(
                    heistId: eu["heistId"] as? String,
                    property: property,
                    oldValue: eu["oldValue"] as? String,
                    newValue: eu["newValue"] as? String
                )
            }
            if dict.keys.contains("elementUpdated") || dict.keys.contains("valueChanged") {
                return .elementUpdated()
            }
            throw FenceError.invalidRequest(
                "Invalid expectation object: expected {\"elementUpdated\": {…}}, " +
                "got keys: \(dict.keys.sorted())"
            )
        }
        throw FenceError.invalidRequest(
            "Invalid expectation type: expected string or {\"elementUpdated\": {…}} object"
        )
    }

    // MARK: - Last Action Tracking

    var lastActionResult: ActionResult?

    // MARK: - Batch Execution

    enum BatchPolicy: String, CaseIterable {
        case stopOnError = "stop_on_error"
        case continueOnError = "continue_on_error"
    }

    private func handleRunBatch(_ args: [String: Any]) async throws -> FenceResponse {
        guard let steps = args["steps"] as? [[String: Any]], !steps.isEmpty else {
            throw FenceError.invalidRequest("run_batch requires a non-empty 'steps' array")
        }
        let policyString = (args["policy"] as? String) ?? BatchPolicy.stopOnError.rawValue
        guard let policy = BatchPolicy(rawValue: policyString) else {
            throw FenceError.invalidRequest(
                "Unknown batch policy: \"\(policyString)\". " +
                "Valid: \(BatchPolicy.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        var results: [[String: Any]] = []
        var stepSummaries: [BatchStepSummary] = []
        var stepDeltas: [InterfaceDelta] = []
        var failedIndex: Int?
        var expectationsMet = 0
        var expectationsChecked = 0
        let batchStart = CFAbsoluteTimeGetCurrent()

        for (index, step) in steps.enumerated() {
            let commandName = step["command"] as? String ?? "?"
            do {
                let response = try await execute(request: step)
                results.append(response.jsonDict() ?? ["status": "ok"])

                // Count explicit tier expectations only — delivery failures have
                // expectation.expectation == nil and should not inflate the count
                var stepExpectationMet: Bool?
                if case .action(_, let expectation) = response,
                   let result = expectation,
                   result.expectation != nil {
                    expectationsChecked += 1
                    if result.met { expectationsMet += 1 }
                    stepExpectationMet = result.met
                }

                // Collect delta for net diff computation
                if case .action(let actionResult, _) = response,
                   let delta = actionResult.interfaceDelta {
                    stepDeltas.append(delta)
                }

                // Build step summary from the typed response
                stepSummaries.append(buildStepSummary(
                    command: commandName, response: response, expectationMet: stepExpectationMet
                ))

                // Check for failure using the typed response, not serialized strings
                let isFailed: Bool
                if case .action(_, let expectation) = response, let result = expectation {
                    isFailed = !result.met
                } else if case .error = response {
                    isFailed = true
                } else {
                    isFailed = false
                }
                if isFailed && policy == .stopOnError {
                    failedIndex = index
                    break
                }
            } catch {
                let errorDict: [String: Any] = [
                    "status": "error",
                    "message": error.localizedDescription,
                ]
                results.append(errorDict)
                stepSummaries.append(BatchStepSummary(
                    command: commandName, deltaKind: nil, screenName: nil,
                    expectationMet: nil, elementCount: nil, error: error.localizedDescription
                ))
                if policy == .stopOnError {
                    failedIndex = index
                    break
                }
            }
        }

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - batchStart) * 1000)
        let netDelta = NetDeltaAccumulator.merge(deltas: stepDeltas)
        return .batch(
            results: results,
            completedSteps: results.count,
            failedIndex: failedIndex,
            totalTimingMs: totalMs,
            expectationsChecked: expectationsChecked,
            expectationsMet: expectationsMet,
            stepSummaries: stepSummaries,
            netDelta: netDelta
        )
    }

    // MARK: - Batch Step Summary

    private func buildStepSummary(
        command: String, response: FenceResponse, expectationMet: Bool?
    ) -> BatchStepSummary {
        switch response {
        case .action(let result, _):
            return BatchStepSummary(
                command: command,
                deltaKind: result.interfaceDelta?.kind.rawValue,
                screenName: result.screenName,
                expectationMet: expectationMet,
                elementCount: nil,
                error: result.success ? nil : result.message
            )
        case .interface(let iface, _, _):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil,
                expectationMet: nil, elementCount: iface.elements.count, error: nil
            )
        case .error(let msg):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil,
                expectationMet: nil, elementCount: nil, error: msg
            )
        default:
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil,
                expectationMet: nil, elementCount: nil, error: nil
            )
        }
    }

    // MARK: - Session State

    func currentSessionState() -> [String: Any] {
        let connected = client.connectionState == .connected
        var payload: [String: Any] = [
            "status": "ok",
            "connected": connected,
        ]
        if let device = client.connectedDevice {
            payload["deviceName"] = client.displayName(for: device)
            payload["appName"] = device.appName
            payload["connectionType"] = device.connectionType.rawValue
            if let shortId = device.shortId { payload["shortId"] = shortId }
        }
        payload["isRecording"] = client.isRecording
        payload["actionTimeoutSeconds"] = Timeouts.actionSeconds
        payload["longActionTimeoutSeconds"] = Timeouts.longActionSeconds

        if let last = lastActionResult {
            payload["lastAction"] = [
                "method": last.method.rawValue,
                "success": last.success,
                "message": last.message as Any,
            ]
        }
        return payload
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
