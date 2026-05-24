import Foundation
import os

import TheScore

private let clientStateLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")

extension SimpleSocketServer {
    private static let authDeadlineSeconds: UInt64 = 10
    private static let errorFlushGracePeriod: Duration = .milliseconds(100)

    /// Disconnect a client.
    func disconnect(clientId: Int) {
        removeClient(clientId)
    }

    /// Mark a client as authenticated.
    func markAuthenticated(_ clientId: Int) {
        clientRegistry.markAuthenticated(clientId)
    }

    /// Mark a connected client as waiting on the on-device approval prompt.
    func markApprovalPending(_ clientId: Int) {
        guard clientRegistry.markApprovalPending(clientId) else { return }
        clientStateLogger.info("Client \(clientId): approval pending — waiting for user to tap Allow on device")
    }

    /// Check if a client is authenticated.
    func isAuthenticated(_ clientId: Int) -> Bool {
        clientRegistry.isAuthenticated(clientId)
    }

    func makeAuthDeadline(for clientId: Int) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.authDeadlineSeconds))
            } catch {
                return
            }
            guard let self else { return }
            switch await self.authentication(for: clientId) {
            case .awaitingAuthentication:
                clientStateLogger.warning("Client \(clientId) did not authenticate within \(Self.authDeadlineSeconds)s deadline")
                await self.rejectClientWithServerError(
                    clientId,
                    kind: .authFailure,
                    message: "Authentication timed out after \(Self.authDeadlineSeconds) seconds."
                )
            case .awaitingApproval:
                clientStateLogger.warning("Client \(clientId): approval timed out — user did not respond to the approval prompt on the device")
                await self.rejectClientWithServerError(
                    clientId,
                    kind: .authApprovalPending,
                    message: "Approval timed out — user did not respond to the approval prompt on the device."
                )
            case .authenticated, .none:
                return
            }
        }
    }

    func removeClient(_ clientId: Int) {
        clientLifecycle.removeClient(clientId, from: &clientRegistry)
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
        pendingCallbackTasks.spawn { [weak self] in
            guard await Task.cancellableSleep(for: Self.errorFlushGracePeriod) else { return }
            await self?.removeClient(clientId)
        }
    }

    private func authentication(for clientId: Int) -> SocketClientAuthentication? {
        clientRegistry.authentication(for: clientId)
    }
}
