import Foundation
import ButtonHeistSupport
import os

import TheScore

private let clientStateLogger = ButtonHeistLog.logger(.handoff(.server))

extension SimpleSocketServer {
    private static let errorFlushGracePeriod: Duration = .milliseconds(100)

    func removeClient(_ clientId: Int) {
        guard clientRegistry.removeAndCancel(clientId) else { return }
        callbacks.onClientDisconnected?(clientId)
    }

    func rejectClientWithServerError(_ clientId: Int, kind: ErrorKind, message: String) {
        guard let state = clientRegistry.client(clientId) else { return }
        sendErrorEnvelope(
            clientId: clientId,
            envelope: ResponseEnvelope(message: .error(TheScore.ServerError(kind: kind, message: message))),
            state: state
        )
        scheduleErrorFlushDisconnect(clientId)
    }

    private func scheduleErrorFlushDisconnect(_ clientId: Int) {
        guard clientRegistry.client(clientId) != nil,
              let generation = currentListener
        else { return }
        spawnTrackedTask(in: generation) { server in
            guard await Task.cancellableSleep(for: Self.errorFlushGracePeriod) else { return }
            await server.removeClient(clientId)
        }
    }
}
