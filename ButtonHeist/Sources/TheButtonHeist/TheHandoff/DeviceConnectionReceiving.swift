import Foundation
import Network
import TheScore

enum DeviceReceiveFraming {
    static let maxBufferSize = WireFrameLimits.serverToClientMaxBufferedBytes

    static func nextFrame(from buffer: inout Data) -> Data? {
        guard let newlineIndex = buffer.firstIndex(of: WireFrameLimits.newlineDelimiterByte) else { return nil }
        let messageData = buffer.prefix(upTo: newlineIndex)
        buffer = Data(buffer.suffix(from: buffer.index(after: newlineIndex)))
        return Data(messageData)
    }
}

enum DeviceReceiveEvent: Sendable {
    case failed(NWError)
    case content(Data)
    case contentThenCompleted(Data)
    case completed
    case awaitingContent

    nonisolated init(content: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            self = .failed(error)
        } else if let content, isComplete {
            self = .contentThenCompleted(content)
        } else if let content {
            self = .content(content)
        } else if isComplete {
            self = .completed
        } else {
            self = .awaitingContent
        }
    }
}

extension DeviceConnection {
    func startReceiving() {
        guard case .connected(let active) = connectionState else { return }
        receiveNext(connection: active.connection)
    }

    func receiveNext(connection: NWConnection) {
        let continuation = eventContinuation
        connection.receive(minimumIncompleteLength: 1, maximumLength: WireFrameLimits.receiveChunkBytes) { content, _, isComplete, error in
            guard let continuation else { return }
            DeviceConnectionEventStream.yield(
                .received(DeviceReceiveEvent(content: content, isComplete: isComplete, error: error), connection: connection),
                to: continuation
            ) { [weak self, weak connection] in
                guard let connection else { return }
                Task { @ButtonHeistActor [weak self] in
                    self?.handleEventStreamOverflow(connection: connection)
                }
            }
        }
    }

    // Internal for testing stale-callback handling.
    func handleReceive(_ event: DeviceReceiveEvent, connection: NWConnection) {
        guard case .connected(var active) = connectionState,
              active.connection === connection else {
            return
        }

        switch event {
        case .failed(let error):
            deviceConnectionLogger.error("Receive error: \(error)")
            connectionState = .disconnected
            onEvent?(.disconnected(.networkError(error)))
        case .content(let content):
            guard appendAndProcess(content, into: &active, connection: connection) else { return }
            receiveNext(connection: connection)
        case .contentThenCompleted(let content):
            guard appendAndProcess(content, into: &active, connection: connection) else { return }
            closeForCompletedReceive()
        case .completed:
            closeForCompletedReceive()
        case .awaitingContent:
            receiveNext(connection: connection)
        }
    }

    private func appendAndProcess(
        _ content: Data,
        into active: inout ActiveConnection,
        connection: NWConnection
    ) -> Bool {
        active.receiveBuffer.append(content)

        if active.receiveBuffer.count > DeviceReceiveFraming.maxBufferSize {
            deviceConnectionLogger.error("Server exceeded max buffer size, disconnecting")
            disconnect()
            onEvent?(.disconnected(.bufferOverflow))
            return false
        }

        connectionState = .connected(active)
        processBuffer()
        guard case .connected(let latest) = connectionState,
              latest.connection === connection else {
            return false
        }
        return true
    }

    private func closeForCompletedReceive() {
        if case .connected = connectionState {
            deviceConnectionLogger.info("Connection closed by server")
            connectionState = .disconnected
            onEvent?(.disconnected(.serverClosed))
        }
    }

    private func processBuffer() {
        while true {
            guard case .connected(var active) = connectionState else { return }
            guard let messageData = DeviceReceiveFraming.nextFrame(from: &active.receiveBuffer) else { return }
            connectionState = .connected(active)
            if !messageData.isEmpty {
                handleMessage(messageData)
            }
        }
    }
}
