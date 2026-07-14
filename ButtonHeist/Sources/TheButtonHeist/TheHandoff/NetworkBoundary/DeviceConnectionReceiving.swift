import Foundation
import ButtonHeistSupport
import Network
import TheScore

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
            onEvent?(.disconnected(.networkError(NetworkTransportFailure(error))))
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
        let (bufferedByteCount, overflowed) = session.receiveFramer.pendingByteCount.addingReportingOverflow(
            content.count
        )
        if overflowed || bufferedByteCount > WireFrameLimits.serverToClientMaxBufferedBytes {
            deviceConnectionLogger.error("Server exceeded max buffer size, disconnecting")
            disconnect()
            onEvent?(.disconnected(.bufferOverflow))
            return false
        }

        let messageFrames = session.receiveFramer.append(content)
        updateConnectedSession(session)
        for messageData in messageFrames {
            guard connectedSession(matching: session.id, connection: session.connection) != nil else {
                return false
            }
            handleMessage(messageData)
        }

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
}
