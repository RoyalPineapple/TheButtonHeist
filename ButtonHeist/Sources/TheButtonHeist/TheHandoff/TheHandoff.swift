import Foundation
import ButtonHeistSupport
import TheScore

/// Client-side coordinator for device discovery, connection, admission, keepalive, and auto-reconnect.
///
/// TheFence owns a TheHandoff and delegates connection management here.
@ButtonHeistActor
final class TheHandoff {

    // MARK: - State

    let connectionLifecycle = HandoffConnectionLifecycle()
    let discoveryLifecycle = HandoffDiscoveryLifecycle()
    var serverMessages = HandoffServerMessageRouter()
    let keepalive = HandoffKeepalive()

    // MARK: - Derived State

    var connectionPhase: HandoffConnectionPhase { connectionLifecycle.phase }

    var isConnected: Bool {
        connectionLifecycle.isConnected
    }

    var connectionDiagnosticFailure: HandoffConnectionError? {
        connectionLifecycle.diagnosticFailure
    }

    var connectedDevice: DiscoveredDevice? {
        connectionLifecycle.connectedDevice
    }

    var serverInfo: ServerInfo? {
        connectionLifecycle.serverInfo
    }

    /// Test seam: how many pings have been sent on the live connection
    /// without a corresponding `.pong` reply. Resets to zero when a pong
    /// arrives, and is automatically discarded when the connection phase
    /// leaves `.connected`. Returns zero in any non-connected phase.
    var missedPongCount: Int {
        connectionLifecycle.missedPongCount
    }

    var discoveredDevices: [DiscoveredDevice] {
        discoveryLifecycle.discoveredDevices
    }

    var isDiscovering: Bool {
        discoveryLifecycle.isDiscovering
    }

    // MARK: - Discovery Callbacks

    // All callbacks below fire on `@ButtonHeistActor`.

    /// A device matching the filter appeared on the network.
    var onDeviceFound: (@ButtonHeistActor (DiscoveredDevice) -> Void)?
    /// A previously-known device is no longer advertising.
    var onDeviceLost: (@ButtonHeistActor (DiscoveredDevice) -> Void)?

    // MARK: - Connection Callbacks

    /// Emits after each connection phase transition. Consumers derive lifecycle
    /// side effects from this state stream instead of one-off lifecycle hooks.
    var onConnectionStateChanged: (@ButtonHeistActor (HandoffConnectionPhase) -> Void)?
    /// Non-lifecycle server messages delivered to TheFence for request-tracker
    /// resolution. TheHandoff forwards these without retaining semantic state.
    var onServerMessage: (@ButtonHeistActor (ServerMessage, RequestID?) -> Void)?
    /// Transport send failures reported after Network.framework processes an enqueued write.
    var onSendFailure: (@ButtonHeistActor (DeviceSendFailure, RequestID?) -> Void)?
    // MARK: - Configuration

    var authToken: SessionAuthToken? {
        get { serverMessages.authToken }
        set { serverMessages.authToken = newValue }
    }
    /// Explicit driver ID override (e.g. from BUTTONHEIST_DRIVER_ID env var).
    /// When nil, a persistent auto-generated ID is used instead.
    var driverID: DriverID? {
        get { serverMessages.driverId }
        set { serverMessages.driverId = newValue }
    }

    // MARK: - Internal Reconnect Settings

    /// Interval between auto-reconnect attempts. Default is 1 second.
    var reconnectInterval: TimeInterval = 1.0
    /// Max attempts before reconnect becomes terminal. Internal so tests can
    /// drive bounded retries without waiting on the production limit.
    var reconnectMaxAttempts = 60
    /// Per-attempt connection timeout used by the reconnect runner.
    var reconnectAttemptTimeout: TimeInterval = 10
    var autoReconnectRecoveryPolicy: AutoReconnectRecoveryPolicy {
        AutoReconnectRecoveryPolicy(maxAttempts: reconnectMaxAttempts, baseInterval: reconnectInterval)
    }
    var reconnectSleeper: (TimeInterval) async -> Bool = { sleepDuration in
        await Task.cancellableSleep(for: .seconds(sleepDuration))
    }

    // MARK: - Injectable Closures

    var makeDiscovery: () -> any DeviceDiscovering = { DeviceDiscovery() }
    var makeConnection: ((DiscoveredDevice) -> any DeviceConnecting)?

    var hasActiveDiscoverySession: Bool {
        discoveryLifecycle.hasDiscoverySession
    }

    // MARK: - Init

    init() {
        connectionLifecycle.onPhaseChanged = { [weak self] phase in
            self?.onConnectionStateChanged?(phase)
        }
    }

    // MARK: - Session Management (discovery → connect → reconnect)

    /// Status callback for session management progress messages.
    var onStatus: (@ButtonHeistActor (String) -> Void)?
}
