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
        guard case .connected(let active) = connectionState,
              let sessionID = currentSessionID else { return }
        receiveNext(connection: active.connection, sessionID: sessionID)
    }

    func receiveNext(connection: NWConnection, sessionID: UUID) {
        guard let continuation = connectedSession(matching: sessionID, connection: connection)?.eventContinuation else {
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: WireFrameLimits.receiveChunkBytes) { content, _, isComplete, error in
            DeviceConnectionEventStream.yield(
                .received(
                    DeviceReceiveEvent(content: content, isComplete: isComplete, error: error),
                    sessionID: sessionID,
                    connection: connection
                ),
                to: continuation
            ) { [weak self, weak connection] in
                guard let connection else { return }
                Task { @ButtonHeistActor [weak self] in
                    self?.handleEventStreamOverflow(connection: connection, sessionID: sessionID)
                }
            }
        }
    }

    // Internal for testing stale-callback handling.
    func handleReceive(_ event: DeviceReceiveEvent, connection: NWConnection) {
        handleReceive(event, connection: connection, sessionID: nil)
    }

    func handleReceive(_ event: DeviceReceiveEvent, connection: NWConnection, sessionID: UUID?) {
        guard var session = connectedSession(matching: sessionID, connection: connection) else {
            return
        }

        switch event {
        case .failed(let error):
            deviceConnectionLogger.error("Receive error: \(error)")
            disconnectConnectedSession(session)
            onEvent?(.disconnected(.networkError(error)))
        case .content(let content):
            guard appendAndProcess(content, into: &session) else { return }
            receiveNext(connection: connection, sessionID: session.id)
        case .contentThenCompleted(let content):
            guard appendAndProcess(content, into: &session) else { return }
            closeForCompletedReceive(session)
        case .completed:
            closeForCompletedReceive(session)
        case .awaitingContent:
            receiveNext(connection: connection, sessionID: session.id)
        }
    }

    private func appendAndProcess(
        _ content: Data,
        into session: inout RuntimeSession
    ) -> Bool {
        session.receiveBuffer.append(content)

        if session.receiveBuffer.count > DeviceReceiveFraming.maxBufferSize {
            deviceConnectionLogger.error("Server exceeded max buffer size, disconnecting")
            disconnect()
            onEvent?(.disconnected(.bufferOverflow))
            return false
        }

        updateConnectedSession(session)
        processBuffer(sessionID: session.id)
        guard let latest = connectedSession(matching: session.id, connection: session.connection) else {
            return false
        }
        session = latest
        return true
    }

    private func closeForCompletedReceive(_ session: RuntimeSession) {
        guard connectedSession(matching: session.id, connection: session.connection) != nil else { return }
        deviceConnectionLogger.info("Connection closed by server")
        disconnectConnectedSession(session)
        onEvent?(.disconnected(.serverClosed))
    }

    private func processBuffer(sessionID: UUID) {
        while true {
            guard var session = connectedSession(matching: sessionID) else { return }
            guard let messageData = DeviceReceiveFraming.nextFrame(from: &session.receiveBuffer) else { return }
            updateConnectedSession(session)
            if !messageData.isEmpty {
                handleMessage(messageData)
            }
        }
    }
}
