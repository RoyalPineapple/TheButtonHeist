import Foundation
import ButtonHeistSupport
import os

import TheScore

private let clientStateLogger = ButtonHeistLog.logger(.handoff(.server))

extension SimpleSocketServer {
    func removeClient(_ clientId: Int) {
        guard clientRegistry.removeAndCancel(clientId) else { return }
        callbacks.onClientDisconnected?(clientId)
    }

    func rejectClientWithServerError(_ clientId: Int, kind: ErrorKind, message: ServerErrorMessage) {
        guard clientRegistry.client(clientId) != nil else { return }
        guard let generation = currentListener else {
            removeClient(clientId)
            return
        }
        let envelope = ResponseEnvelope(message: .error(TheScore.ServerError(kind: kind, message: message)))
        let admission = spawnTrackedTask(in: generation) { server in
            await server.sendErrorEnvelope(clientId: clientId, envelope: envelope)
            await server.removeClient(clientId)
        }
        if case .rejected = admission {
            removeClient(clientId)
        }
    }
}
