import Foundation
import Network
import AccraCore

@MainActor
final class DeviceConnection {

    private var connection: NWConnection?
    private let device: DiscoveredDevice

    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onServerInfo: ((ServerInfo) -> Void)?
    var onHierarchy: ((HierarchyPayload) -> Void)?
    var onError: ((String) -> Void)?

    init(device: DiscoveredDevice) {
        self.device = device
    }

    func connect() {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        connection = NWConnection(to: device.endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleState(state)
            }
        }

        connection?.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        connection?.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onConnected?()
            receiveMessages()
        case .failed(let error):
            onDisconnected?(error)
        case .cancelled:
            onDisconnected?(nil)
        default:
            break
        }
    }

    private func receiveMessages() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                if let data = data {
                    self?.handleMessage(data)
                }
                if error == nil {
                    self?.receiveMessages()
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            return
        }

        switch message {
        case .info(let info):
            onServerInfo?(info)
        case .hierarchy(let payload):
            onHierarchy?(payload)
        case .error(let errorMessage):
            onError?(errorMessage)
        case .pong:
            break
        }
    }
}
