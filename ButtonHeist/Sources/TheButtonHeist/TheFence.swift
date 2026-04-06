import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "bookkeeper")

/// Errors thrown by TheFence during command dispatch, connection, and action execution.
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
            return "Not connected to device. Is the app running? Check 'buttonheist list' to see available devices."
        case .actionTimeout:
            return "Action timed out — connection lost, reconnecting..."
        case .actionFailed(let message):
            return "Action failed: \(message)"
        }
    }
}

/// Named timeout constants for TheFence operations.
public enum Timeouts {
    /// Standard action timeout (15 seconds)
    public static let actionSeconds: TimeInterval = 15
    /// Long action timeout (30 seconds)
    public static let longActionSeconds: TimeInterval = 30
    /// Explore timeout (60 seconds) — scrolls entire screen, needs headroom
    public static let exploreSeconds: TimeInterval = 60
}

/// Centralized command dispatch layer. Both the CLI and MCP server are thin wrappers over TheFence.
@ButtonHeistActor
public final class TheFence {
    /// Connection and session configuration for TheFence.
    public struct Configuration {
        public var deviceFilter: String?
        public var connectionTimeout: TimeInterval
        public var token: String?
        public var autoReconnect: Bool
        public var fileConfig: ButtonHeistFileConfig?

        public init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            token: String? = nil,
            autoReconnect: Bool = true,
            fileConfig: ButtonHeistFileConfig? = nil
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.token = token
            self.autoReconnect = autoReconnect
            self.fileConfig = fileConfig
        }
    }

    public static let supportedCommands: [String] = Command.allCases.map(\.rawValue)

    public var onStatus: ((String) -> Void)? {
        didSet { handoff.onStatus = onStatus }
    }
    public var onAuthApproved: ((String?) -> Void)?

    var config: Configuration
    let handoff = TheHandoff()
    let bookKeeper = TheBookKeeper()
    private var isStarted = false

    // MARK: - Pending Request Tracking

    private let actionTracker = PendingRequestTracker<ActionResult>()
    private let interfaceTracker = PendingRequestTracker<Interface>()
    private let screenTracker = PendingRequestTracker<ScreenPayload>()

    public init(configuration: Configuration = .init()) {
        self.config = configuration
        self.handoff.token = configuration.token ?? EnvironmentKey.buttonheistToken.value
        self.handoff.driverId = EnvironmentKey.buttonheistDriverId.value
        self.handoff.autoSubscribe = true
        self.handoff.onAuthApproved = { [weak self] token in
            if let token {
                self?.onStatus?("BUTTONHEIST_TOKEN=\(token)")
            }
            self?.onAuthApproved?(token)
        }
        wireUpResponseCallbacks()
    }

    private func wireUpResponseCallbacks() {
        handoff.onInterface = { [weak self] payload, requestId in
            guard let self, let requestId else { return }
            self.interfaceTracker.resolve(requestId: requestId, result: .success(payload))
        }

        handoff.onActionResult = { [weak self] result, requestId in
            guard let self, let requestId else { return }
            self.actionTracker.resolve(requestId: requestId, result: .success(result))
        }

        handoff.onScreen = { [weak self] payload, requestId in
            guard let self, let requestId else { return }
            self.screenTracker.resolve(requestId: requestId, result: .success(payload))
        }
    }

    /// Connect to a device and optionally enable auto-reconnect.
    public func start() async throws {
        if isStarted, handoff.isConnected {
            return
        }

        try await connect()
        if config.autoReconnect {
            let filter = config.deviceFilter ?? EnvironmentKey.buttonheistDevice.value
            handoff.setupAutoReconnect(filter: filter)
        }
        isStarted = true
    }

    /// Disconnect and cancel all pending requests.
    public func stop() {
        cancelAllPendingRequests()
        handoff.disconnect()
        handoff.stopDiscovery()
        isStarted = false
    }

    /// Execute a command from a dictionary request. Auto-connects if not already connected.
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
            command != .connect && command != .listTargets &&
            command != .getSessionLog && command != .archiveSession &&
            (!isStarted || !handoff.isConnected) {
            try await start()
        }

        let requestId = (request["requestId"] as? String) ?? UUID().uuidString
        do {
            try bookKeeper.logCommand(requestId: requestId, command: command, arguments: request)
        } catch {
            logger.warning("Failed to log command \(command.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        var dispatchArgs = request
        dispatchArgs["_requestId"] = requestId

        let start = CFAbsoluteTimeGetCurrent()
        let response: FenceResponse
        do {
            response = try await dispatch(command: command, args: dispatchArgs)
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            do {
                try bookKeeper.logResponse(
                    requestId: requestId,
                    status: .error,
                    durationMilliseconds: durationMs,
                    error: error.localizedDescription
                )
            } catch let logError {
                logger.warning("Failed to log error response for \(requestId, privacy: .public): \(logError.localizedDescription, privacy: .public)")
            }
            throw error
        }
        lastLatencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        let responseStatus: ResponseStatus
        let artifactPath: String?
        let errorMessage: String?
        switch response {
        case .error(let message):
            responseStatus = .error
            artifactPath = nil
            errorMessage = message
        case .screenshot(let path, _, _):
            responseStatus = .ok
            artifactPath = path
            errorMessage = nil
        case .recording(let path, _):
            responseStatus = .ok
            artifactPath = path
            errorMessage = nil
        case .archiveResult(let path, _):
            responseStatus = .ok
            artifactPath = path
            errorMessage = nil
        case .ok, .help, .status, .devices, .interface, .action,
             .screenshotData, .recordingData, .batch, .sessionState,
             .targets, .sessionLog:
            responseStatus = .ok
            artifactPath = nil
            errorMessage = nil
        }
        do {
            try bookKeeper.logResponse(
                requestId: requestId,
                status: responseStatus,
                durationMilliseconds: lastLatencyMs,
                artifact: artifactPath,
                error: errorMessage
            )
        } catch {
            logger.warning("Failed to log response for \(requestId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

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
        let filter = config.deviceFilter ?? EnvironmentKey.buttonheistDevice.value
        try await handoff.connectWithDiscovery(
            filter: filter,
            timeout: config.connectionTimeout
        )
    }

    // MARK: - Command Dispatch (thin router)

    private func dispatch(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .status:
            return .status(
                connected: handoff.isConnected,
                deviceName: handoff.connectedDevice.map { handoff.displayName(for: $0) }
            )
        case .listDevices:
            return try await handleListDevices()
        case .getInterface:
            return try await handleGetInterface(args)
        case .getScreen:
            return try await handleGetScreen(args)
        case .waitForIdle:
            return try await sendAction(.waitForIdle(WaitForIdleTarget(timeout: doubleArg(args, "timeout"))))
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate, .twoFingerTap,
             .drawPath, .drawBezier:
            return try await handleGesture(command: command, args: args)
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return try await handleScrollAction(command: command, args: args)
        case .waitFor:
            return try await handleWaitFor(args)
        case .activate, .increment, .decrement, .performCustomAction:
            return try await handleAccessibilityAction(command: command, args: args)
        case .typeText:
            return try await handleTypeText(args)
        case .editAction:
            return try await handleEditAction(args)
        case .setPasteboard, .getPasteboard:
            return try await handlePasteboard(command: command, args: args)
        case .dismissKeyboard:
            return try await sendAction(.resignFirstResponder)
        case .startRecording, .stopRecording:
            return command == .startRecording
                ? try await handleStartRecording(args)
                : try await handleStopRecording(args)
        case .runBatch:
            return try await handleRunBatch(args)
        case .getSessionState:
            return .sessionState(payload: currentSessionState())
        case .connect:
            return try await handleConnect(args)
        case .listTargets:
            return handleListTargets()
        case .getSessionLog, .archiveSession:
            return try await handleBookKeeperCommand(command: command, args: args)
        case .help, .quit, .exit:
            return .error("Unexpected command in dispatch: \(command.rawValue)")
        }
    }

    // MARK: - Send Action (shared)

    func sendAction(_ message: ClientMessage) async throws -> FenceResponse {
        let result: ActionResult = try await sendAndAwait(message) { requestId in
            try await self.waitForActionResult(requestId: requestId, timeout: Timeouts.actionSeconds)
        }
        lastActionResult = result
        return .action(result: result)
    }

    func sendAndAwait<T: Sendable>(_ message: ClientMessage, response: (_ requestId: String) async throws -> T) async throws -> T {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        handoff.send(message, requestId: requestId)
        do {
            return try await response(requestId)
        } catch {
            let mapped = mapCaughtError(error)
            if case .actionTimeout = mapped {
                handoff.forceDisconnect()
            }
            throw mapped
        }
    }

    private func mapCaughtError(_ error: Error) -> FenceError {
        if let fenceError = error as? FenceError {
            return fenceError
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

    func unitPointArg(_ dictionary: [String: Any], _ key: String) -> UnitPoint? {
        guard let dict = dictionary[key] as? [String: Any],
              let x = numberArg(dict["x"]),
              let y = numberArg(dict["y"]) else { return nil }
        return UnitPoint(x: x, y: y)
    }

    func elementTarget(_ dictionary: [String: Any]) throws -> ElementTarget? {
        ElementTarget(
            heistId: stringArg(dictionary, "heistId"),
            matcher: try elementMatcher(dictionary),
            ordinal: intArg(dictionary, "ordinal")
        )
    }

    func elementMatcher(_ dictionary: [String: Any]) throws -> ElementMatcher {
        let traits: [HeistTrait]? = try (dictionary["traits"] as? [String])?.map { name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw FenceError.invalidRequest(
                    "Unknown trait '\(name)'. Valid: \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))"
                )
            }
            return trait
        }
        let excludeTraits: [HeistTrait]? = try (dictionary["excludeTraits"] as? [String])?.map { name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw FenceError.invalidRequest(
                    "Unknown excludeTrait '\(name)'. Valid: \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))"
                )
            }
            return trait
        }
        return ElementMatcher(
            label: stringArg(dictionary, "label"),
            identifier: stringArg(dictionary, "identifier"),
            value: stringArg(dictionary, "value"),
            traits: traits,
            excludeTraits: excludeTraits
        )
    }

    // MARK: - Expectation Parsing

    func parseExpectation(_ dictionary: [String: Any]) throws -> ActionExpectation? {
        guard let expect = dictionary["expect"] else { return nil }
        if let str = expect as? String {
            switch str {
            case "screen_changed":
                return .screenChanged
            case "elements_changed":
                return .elementsChanged
            default:
                throw FenceError.invalidRequest(
                    "Unknown expectation tier: \"\(str)\". " +
                    "Valid: screen_changed, elements_changed, or {\"elementUpdated\": {…}}"
                )
            }
        }
        if let dict = expect as? [String: Any] {
            if let eu = dict["elementUpdated"] as? [String: Any] {
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
            if dict.keys.contains("elementUpdated") {
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

    // MARK: - Last Action / Latency Tracking

    var lastActionResult: ActionResult?
    public private(set) var lastLatencyMs: Int = 0

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
                stepSummaries.append(makeStepSummary(
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
                    command: commandName, deltaKind: nil, screenName: nil, screenId: nil,
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

    // MARK: - Config Target Conversion

    static func configTargetsAsDevices(_ config: ButtonHeistFileConfig) -> [DiscoveredDevice] {
        config.targets.compactMap { name, target in
            guard let device = DiscoveredDevice.fromHostPort(target.device, id: "config-\(name)", name: name) else { return nil }
            return device
        }
    }

    // MARK: - Make Step Summary

    private func makeStepSummary(
        command: String, response: FenceResponse, expectationMet: Bool?
    ) -> BatchStepSummary {
        switch response {
        case .action(let result, _):
            return BatchStepSummary(
                command: command,
                deltaKind: result.interfaceDelta?.kind.rawValue,
                screenName: result.screenName,
                screenId: result.screenId,
                expectationMet: expectationMet,
                elementCount: nil,
                error: result.success ? nil : result.message
            )
        case .interface(let iface, _, _, _):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: iface.elements.count, error: nil
            )
        case .error(let message):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: message
            )
        default:
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: nil
            )
        }
    }

    // MARK: - Session State

    func currentSessionState() -> [String: Any] {
        let connected = handoff.isConnected
        var payload: [String: Any] = [
            "status": "ok",
            "connected": connected,
        ]
        if let device = handoff.connectedDevice {
            payload["deviceName"] = handoff.displayName(for: device)
            payload["appName"] = device.appName
            payload["connectionType"] = device.connectionType.rawValue
            if let shortId = device.shortId { payload["shortId"] = shortId }
        }
        payload["isRecording"] = handoff.isRecording
        payload["actionTimeoutSeconds"] = Timeouts.actionSeconds
        payload["longActionTimeoutSeconds"] = Timeouts.longActionSeconds

        if let last = lastActionResult {
            payload["lastAction"] = [
                "method": last.method.rawValue,
                "success": last.success,
                "message": last.message as Any,
                "latency_ms": lastLatencyMs,
            ]
        }
        return payload
    }

    // MARK: - Async Wait Methods

    func waitForActionResult(requestId: String, timeout: TimeInterval) async throws -> ActionResult {
        try await actionTracker.wait(requestId: requestId, timeout: timeout)
    }

    func waitForInterface(requestId: String, timeout: TimeInterval = 10.0) async throws -> Interface {
        try await interfaceTracker.wait(requestId: requestId, timeout: timeout)
    }

    func waitForScreen(requestId: String, timeout: TimeInterval = 30.0) async throws -> ScreenPayload {
        try await screenTracker.wait(requestId: requestId, timeout: timeout)
    }

    // Recording uses a fundamentally different pattern from the request-id-based trackers:
    // it temporarily swaps TheHandoff's onRecording/onRecordingError callbacks and restores
    // them in a defer block. There is no requestId — the server sends exactly one recording
    // response per stop_recording command, and the callback identity (not a dictionary key)
    // is what correlates request to response. A PendingRequestTracker<RecordingPayload> would
    // require either synthesizing a fake requestId or changing the TheHandoff callback
    // signatures, neither of which is warranted for a single call site.
    public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        let previousOnRecording = handoff.onRecording
        let previousOnRecordingError = handoff.onRecordingError
        defer {
            handoff.onRecording = previousOnRecording
            handoff.onRecordingError = previousOnRecordingError
        }

        let recordingTracker = PendingRequestTracker<RecordingPayload>()
        let syntheticId = "recording"
        handoff.onRecording = { payload in
            recordingTracker.resolve(requestId: syntheticId, result: .success(payload))
        }
        handoff.onRecordingError = { message in
            recordingTracker.resolve(requestId: syntheticId, result: .failure(FenceError.actionFailed("Recording failed: \(message)")))
        }
        return try await recordingTracker.wait(requestId: syntheticId, timeout: timeout)
    }

    private func cancelAllPendingRequests() {
        actionTracker.cancelAll(error: FenceError.actionTimeout)
        interfaceTracker.cancelAll(error: FenceError.actionTimeout)
        screenTracker.cancelAll(error: FenceError.actionTimeout)
    }

}
