import Foundation

import ButtonHeistSupport
import TheScore

/// Centralized command dispatch layer. Both the CLI and MCP server are thin wrappers over TheFence.
@ButtonHeistActor
public final class TheFence {
    public enum MainThreadWatchdog: Sendable, Equatable {
        case disabled
        case enabled(MainThreadWatchdogSettings)
    }

    public struct MainThreadWatchdogSettings: Sendable, Equatable {
        public let initialDelay: TimeInterval
        public let cadence: TimeInterval
        public let probeResponseTimeout: TimeInterval
        public let responsivenessTimeout: TimeInterval
        public let workTimeout: TimeInterval

        var initialDelayDuration: Duration { .seconds(initialDelay) }
        var cadenceDuration: Duration { .seconds(cadence) }
        var responsivenessTimeoutMilliseconds: Int64 {
            Self.admittedMilliseconds(from: responsivenessTimeout)
        }
        var workTimeoutMilliseconds: Int64 {
            Self.admittedMilliseconds(from: workTimeout)
        }

        public init(
            initialDelay: TimeInterval,
            cadence: TimeInterval,
            probeResponseTimeout: TimeInterval,
            responsivenessTimeout: TimeInterval,
            workTimeout: TimeInterval
        ) throws {
            let durations = [
                ("initialDelay", initialDelay),
                ("cadence", cadence),
                ("probeResponseTimeout", probeResponseTimeout),
                ("responsivenessTimeout", responsivenessTimeout),
                ("workTimeout", workTimeout),
            ]
            if let invalid = durations.first(where: { !$0.1.isFinite || $0.1 <= 0 }) {
                throw FenceError.invalidRequest(
                    "Main-thread watchdog \(invalid.0) must be a positive finite number of seconds."
                )
            }
            guard durations.allSatisfy({ $0.1 < Double(Int64.max) }),
                  Self.milliseconds(from: responsivenessTimeout) != nil,
                  Self.milliseconds(from: workTimeout) != nil
            else {
                throw FenceError.invalidRequest(
                    "Main-thread watchdog durations must fit Swift Duration and positive Int64 milliseconds."
                )
            }
            self.init(
                admittedInitialDelay: initialDelay,
                cadence: cadence,
                probeResponseTimeout: probeResponseTimeout,
                responsivenessTimeout: responsivenessTimeout,
                workTimeout: workTimeout
            )
        }

        public static let standard = MainThreadWatchdogSettings(
            admittedInitialDelay: 2,
            cadence: 2,
            probeResponseTimeout: 2,
            responsivenessTimeout: 1,
            workTimeout: 1
        )

        private init(
            admittedInitialDelay: TimeInterval,
            cadence: TimeInterval,
            probeResponseTimeout: TimeInterval,
            responsivenessTimeout: TimeInterval,
            workTimeout: TimeInterval
        ) {
            self.initialDelay = admittedInitialDelay
            self.cadence = cadence
            self.probeResponseTimeout = probeResponseTimeout
            self.responsivenessTimeout = responsivenessTimeout
            self.workTimeout = workTimeout
        }

        private static func milliseconds(from seconds: TimeInterval) -> Int64? {
            let milliseconds = (seconds * 1_000).rounded(.up)
            guard milliseconds.isFinite,
                  milliseconds > 0,
                  milliseconds < Double(Int64.max)
            else { return nil }
            return Int64(milliseconds)
        }

        private static func admittedMilliseconds(from seconds: TimeInterval) -> Int64 {
            guard let milliseconds = milliseconds(from: seconds) else {
                preconditionFailure("MainThreadWatchdogSettings contains an unadmitted duration")
            }
            return milliseconds
        }
    }

    /// Connection and session configuration for TheFence.
    public struct Configuration {
        /// Substring filter for Bonjour device names. `nil` matches any device.
        var deviceFilter: String?
        /// Seconds to wait for initial connection before failing `start()`.
        var connectionTimeout: TimeInterval
        /// Auth token sent in the `authenticate` message after the server requests
        /// auth. Agents use the task slug.
        var token: SessionAuthToken?
        var driverID: DriverID?
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
        /// Diagnoses a wedged app main thread while a UI request remains pending.
        public var mainThreadWatchdog: MainThreadWatchdog

        init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            token: SessionAuthToken? = nil,
            driverID: DriverID? = nil,
            autoReconnect: Bool = true,
            fileConfig: ButtonHeistFileConfig? = nil,
            directDevice: DiscoveredDevice? = nil,
            artifactBaseDirectory: URL? = nil,
            postActionExpectationTimeoutBuffer: TimeInterval = 5,
            mainThreadWatchdog: MainThreadWatchdog = .enabled(.standard)
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.token = token
            self.driverID = driverID
            self.autoReconnect = autoReconnect
            self.fileConfig = fileConfig
            self.directDevice = directDevice
            self.artifactBaseDirectory = artifactBaseDirectory
            self.postActionExpectationTimeoutBuffer = postActionExpectationTimeoutBuffer
            self.mainThreadWatchdog = mainThreadWatchdog
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
    let screenshotArtifacts: ScreenshotArtifactWriter
    let pendingRequests = PendingRequestRegistry()
    var sleepForMainThreadWatchdog: @Sendable (Duration) async -> Bool = {
        await Task.cancellableSleep(for: $0)
    }

    public init(configuration: Configuration) {
        self.config = configuration
        self.screenshotArtifacts = ScreenshotArtifactWriter(baseDirectory: configuration.artifactBaseDirectory)
        self.handoff.authToken = configuration.token
        self.handoff.driverID = configuration.driverID
        wireUpResponseCallbacks()
    }

    var sessionConnectionState: SessionConnectionState {
        switch handoff.connectionPhase {
        case .disconnected:
            return .disconnected(lastFailure: handoff.connectionLifecycle.diagnosticFailure.map(sessionFailurePayload(for:)))
        case .reconnecting, .connecting:
            return .connecting(lastFailure: handoff.connectionLifecycle.diagnosticFailure.map(sessionFailurePayload(for:)))
        case .connected(let session):
            return .connected(device: sessionDevicePayload(for: session.device))
        case .failed(let failure):
            return .failed(sessionFailurePayload(for: failure))
        }
    }

    private func sessionDevicePayload(for device: DiscoveredDevice) -> SessionDevicePayload {
        SessionDevicePayload(
            deviceName: handoff.displayName(for: device),
            appName: device.appName,
            connectionType: device.connectionType,
            shortId: device.shortId?.description
        )
    }

    private func sessionFailurePayload(for failure: HandoffConnectionError) -> SessionFailurePayload {
        SessionFailurePayload(
            code: failure.failureCode,
            phase: failure.phase,
            retryable: failure.retryable,
            message: failure.errorDescription,
            hint: failure.hint
        )
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

    private func handleServerMessage(_ message: ServerMessage, requestId: RequestID?) {
        guard let requestId else { return }
        _ = pendingRequests.resolveTransientResponse(message, requestId: requestId)
    }

    private func handleSendFailure(_ failure: DeviceSendFailure, requestId: RequestID?) {
        guard let requestId else { return }
        pendingRequests.resolveTransientFailure(FenceError(failure), requestId: requestId)
    }

    // Expectation parsing (`parseExpectation` and its helpers) lives in
    // TheFence+ExpectationParsing.swift.

    // Heist execution (`handleRunHeist`, step-summary building,
    // and `currentSessionState`) lives in TheFence+RunHeist.swift.

    // MARK: - Config Target Conversion

    static func configTargetsAsDevices(_ config: ButtonHeistFileConfig) -> [DiscoveredDevice] {
        config.targets.compactMap { name, target in
            let deviceID = DiscoveryDeviceID(stringLiteral: "config-\(name.rawValue)")
            guard let device = DiscoveredDevice.fromHostPort(
                target.device,
                id: deviceID,
                name: name.rawValue
            ) else { return nil }
            return device
        }
    }

}
