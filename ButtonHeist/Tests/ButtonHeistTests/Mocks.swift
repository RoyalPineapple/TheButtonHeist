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

    var serverInfo: ServerInfo?

    func connect() {
        isConnected = true
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
        if let requestId, let handler = autoResponse {
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

    func start() {
        onEvent?(.stateChanged(isReady: true))
        for device in discoveredDevices {
            onEvent?(.found(device))
        }
    }

    func stop() {}
}
