import Foundation

import TheScore

struct SessionConnectionSnapshot {
    let connected: Bool
    let phase: SessionConnectionPhase
    let device: SessionDevicePayload?
    let lastFailure: SessionFailurePayload?
}

/// Named timeout constants for TheFence operations.
enum Timeouts {
    /// Standard action timeout (15 seconds)
    static let actionSeconds: TimeInterval = 15
    /// Short health/read-control timeout (3 seconds)
    static let healthSeconds: TimeInterval = 3
    /// Long action timeout (30 seconds)
    static let longActionSeconds: TimeInterval = 30
    /// Explore timeout (60 seconds) — scrolls entire screen, needs headroom
    static let exploreSeconds: TimeInterval = 60
}

/// Centralized command dispatch layer. Both the CLI and MCP server are thin wrappers over TheFence.
@ButtonHeistActor
public final class TheFence {
    /// Connection and session configuration for TheFence.
    public struct Configuration {
        /// Substring filter for Bonjour device names. `nil` matches any device.
        var deviceFilter: String?
        /// Seconds to wait for initial connection before failing `start()`.
        var connectionTimeout: TimeInterval
        /// Auth token sent in the `authenticate` message after the server requests
        /// auth. Agents use the task slug; omit to fall back to `BUTTONHEIST_TOKEN`.
        var token: String?
        /// When true, TheHandoff re-establishes the connection on drop.
        var autoReconnect: Bool
        /// Resolved `.buttonheist.json` config (device filter, token, output paths).
        /// Supplied by the CLI/MCP entry points from discovered config files.
        var fileConfig: ButtonHeistFileConfig?
        /// Direct host:port target. Legacy configs may still carry a fingerprint.
        var directDevice: DiscoveredDevice?
        /// Test/config override for screenshot artifact storage root.
        var artifactBaseDirectory: URL?
        /// Extra client-side headroom beyond a server-owned wait timeout.
        var postActionExpectationTimeoutBuffer: TimeInterval

        init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            token: String? = nil,
            autoReconnect: Bool = true,
            fileConfig: ButtonHeistFileConfig? = nil,
            directDevice: DiscoveredDevice? = nil,
            artifactBaseDirectory: URL? = nil,
            postActionExpectationTimeoutBuffer: TimeInterval = 5
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.token = token
            self.autoReconnect = autoReconnect
            self.fileConfig = fileConfig
            self.directDevice = directDevice
            self.artifactBaseDirectory = artifactBaseDirectory
            self.postActionExpectationTimeoutBuffer = postActionExpectationTimeoutBuffer
        }
    }

    /// Fires on informational status strings (e.g. `BUTTONHEIST_TOKEN=<value>`
    /// on server-generated token, connection events).
    public var onStatus: (@ButtonHeistActor (String) -> Void)? {
        didSet { handoff.onStatus = onStatus }
    }

    // Dependencies
    var config: Configuration
    let handoff = TheHandoff()
    var sessionConnectionSnapshot: SessionConnectionSnapshot {
        SessionConnectionSnapshot(
            connected: handoff.isConnected,
            phase: sessionConnectionPhase,
            device: sessionDevicePayload,
            lastFailure: sessionFailurePayload
        )
    }
    let screenshotArtifacts: ScreenshotArtifactWriter
    let pendingRequests = PendingRequestTrackers()

    public init(configuration: Configuration) {
        self.config = configuration
        self.screenshotArtifacts = ScreenshotArtifactWriter(baseDirectory: configuration.artifactBaseDirectory)
        let configuredToken = configuration.token ?? EnvironmentKey.buttonheistToken.value
        self.handoff.token = configuredToken
        self.handoff.driverId = EnvironmentKey.buttonheistDriverId.value
        wireUpResponseCallbacks()
    }

    private var sessionConnectionPhase: SessionConnectionPhase {
        switch handoff.connectionPhase {
        case .disconnected:
            return .disconnected
        case .reconnecting, .connecting:
            return .connecting
        case .connected:
            return .connected
        case .failed:
            return .failed
        }
    }

    private var sessionDevicePayload: SessionDevicePayload? {
        handoff.connectedDevice.map { device in
            SessionDevicePayload(
                deviceName: handoff.displayName(for: device),
                appName: device.appName,
                connectionType: device.connectionType,
                shortId: device.shortId
            )
        }
    }

    private var sessionFailurePayload: SessionFailurePayload? {
        handoff.connectionDiagnosticFailure.map { failure in
            SessionFailurePayload(
                errorCode: failure.failureCode,
                phase: failure.phase,
                retryable: failure.retryable,
                message: failure.errorDescription,
                hint: failure.hint
            )
        }
    }

    private func wireUpResponseCallbacks() {
        handoff.onServerMessage = { [weak self] message, requestId in
            self?.handleServerMessage(message, requestId: requestId)
        }

        handoff.onSendFailure = { [weak self] failure, requestId in
            self?.handleSendFailure(failure, requestId: requestId)
        }

        handoff.onConnectionStateChanged = { [weak self] state in
            self?.handleHandoffConnectionStateChanged(state)
        }
    }

    private func handleServerMessage(_ message: ServerMessage, requestId: String?) {
        guard let requestId else { return }
        _ = pendingRequests.resolveTransientResponse(message, requestId: requestId)
    }

    private func handleSendFailure(_ failure: DeviceSendFailure, requestId: String?) {
        guard let requestId else { return }
        pendingRequests.resolveTransientFailure(FenceError(failure), requestId: requestId)
    }

    /// Execute a typed command request.
    public func execute(command: Command, arguments: CommandArgumentEnvelope) async throws -> FenceResponse {
        let parsed: ParsedRequest
        do {
            parsed = try parseRequest(command: command, arguments: arguments)
        } catch let error as SchemaValidationError {
            return .error(error.message)
        } catch let error as MissingElementTarget {
            return missingElementTargetResponse(command: error.command)
        } catch let error as FenceError {
            return .error(error.coreMessage, details: error.failureDetails)
        }
        return try await execute(parsed: parsed)
    }

    // MARK: - Command Dispatch (thin router)

    func dispatch(_ parsed: ParsedRequest) async throws -> FenceResponse {
        try await parsed.handler(self, parsed)
    }

    // Expectation parsing (`parseExpectation` and its helpers) lives in
    // TheFence+ExpectationParsing.swift.

    // Heist execution (`handleRunHeist`, step-summary building,
    // and `currentSessionState`) lives in TheFence+RunHeist.swift.

    // MARK: - Config Target Conversion

    static func configTargetsAsDevices(_ config: ButtonHeistFileConfig) -> [DiscoveredDevice] {
        config.targets.compactMap { name, target in
            guard let device = DiscoveredDevice.fromHostPort(
                target.device,
                id: "config-\(name)",
                name: name
            ) else { return nil }
            return device
        }
    }

}
