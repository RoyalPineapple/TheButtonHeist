import Foundation
import Network
import AccessibilityBridgeProtocol

@MainActor
@Observable
final class WebSocketClient {

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(ServerInfo)
        case error(String)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected): return true
            case (.connecting, .connecting): return true
            case let (.connected(a), .connected(b)): return a.appName == b.appName
            case let (.error(a), .error(b)): return a == b
            default: return false
            }
        }
    }

    private(set) var state: ConnectionState = .disconnected
    private(set) var elements: [AccessibilityElementData] = []
    private(set) var lastUpdateTime: Date?

    private var connection: NWConnection?
    private var isSubscribed = false

    func connect(to endpoint: NWEndpoint) {
        disconnect()
        state = .connecting

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                self?.handleConnectionState(newState)
            }
        }

        connection?.start(queue: .main)
        print("[WebSocketClient] Connecting to \(endpoint)")
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .disconnected
        elements = []
        isSubscribed = false
    }

    func requestHierarchy() {
        send(.requestHierarchy)
    }

    func subscribe() {
        guard !isSubscribed else { return }
        send(.subscribe)
        isSubscribed = true
    }

    func unsubscribe() {
        guard isSubscribed else { return }
        send(.unsubscribe)
        isSubscribed = false
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            print("[WebSocketClient] Connected")
            receiveMessages()
        case .failed(let error):
            print("[WebSocketClient] Failed: \(error)")
            state = .error(error.localizedDescription)
        case .cancelled:
            print("[WebSocketClient] Cancelled")
            state = .disconnected
        default:
            break
        }
    }

    private func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])

        connection?.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func receiveMessages() {
        connection?.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                if let data = data {
                    self?.handleReceivedData(data)
                }

                if error == nil {
                    self?.receiveMessages()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        guard let message = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            print("[WebSocketClient] Failed to decode message")
            return
        }

        switch message {
        case .info(let info):
            print("[WebSocketClient] Received server info: \(info.appName)")
            state = .connected(info)
            // Auto-subscribe and request initial hierarchy
            subscribe()
            requestHierarchy()

        case .hierarchy(let payload):
            print("[WebSocketClient] Received hierarchy with \(payload.elements.count) elements")
            elements = payload.elements
            lastUpdateTime = payload.timestamp

        case .pong:
            break

        case .error(let errorMessage):
            print("[WebSocketClient] Server error: \(errorMessage)")
        }
    }
}
