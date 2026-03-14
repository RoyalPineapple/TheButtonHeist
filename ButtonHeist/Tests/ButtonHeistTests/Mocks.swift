import Network
@testable import ButtonHeist
import TheScore

// MARK: - Mock Implementations for DeviceConnecting / DeviceDiscovering

@ButtonHeistActor
final class MockConnection: DeviceConnecting {
    var isConnected = false
    var observeMode = false
    var onEvent: ((ConnectionEvent) -> Void)?
    var sent: [(ClientMessage, String?)] = []
    var connectCount = 0
    var emitTransportReadyOnConnect = false
    var connectEventsOverride: [ConnectionEvent]?

    var serverInfo: ServerInfo?

    func connect() {
        connectCount += 1
        isConnected = true
        if let connectEventsOverride {
            for event in connectEventsOverride {
                onEvent?(event)
            }
            return
        }
        if emitTransportReadyOnConnect {
            onEvent?(.transportReady)
        }
        onEvent?(.connected)
        if let info = serverInfo {
            onEvent?(.message(.info(info), requestId: nil))
        }
    }

    func disconnect() {
        isConnected = false
    }

    func send(_ message: ClientMessage, requestId: String?) {
        sent.append((message, requestId))
        if let handler = autoResponse {
            let response = handler(message)
            Task { @ButtonHeistActor [self] in
                self.onEvent?(.message(response, requestId: requestId))
            }
        }
    }

    var autoResponse: ((ClientMessage) -> ServerMessage)?
}

@ButtonHeistActor
final class MockDiscovery: DeviceDiscovering {
    var discoveredDevices: [DiscoveredDevice] = []
    var onEvent: ((DiscoveryEvent) -> Void)?
    var startCount = 0
    var stopCount = 0

    func start() {
        startCount += 1
        onEvent?(.stateChanged(isReady: true))
        for device in discoveredDevices {
            onEvent?(.found(device))
        }
    }

    func stop() {
        stopCount += 1
    }
}
