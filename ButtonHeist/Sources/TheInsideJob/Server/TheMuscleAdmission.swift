#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct AdmittedClientMessage: Sendable {
    let clientId: Int
    let envelope: RequestEnvelope
}

enum ClientAdmission: Sendable {
    case admitted(AdmittedClientMessage)
    case handled
}

enum MuscleAdmissionEffect {
    case sendResponse(ServerMessage, requestId: String?, respond: TheMuscleAdmission.ResponseHandler)
    case sendClient(ServerMessage, requestId: String?, clientId: Int)
    case delayedDisconnect(clientId: Int)
    case log(MuscleAdmissionLogEvent)
}

enum MuscleAdmissionLogEvent {
    case clientAuthenticatedWithToken(clientId: Int)
    case sessionLockRejected(clientId: Int, message: String)
    case rateLimited(clientId: Int)
    case undecodableUnauthenticatedMessage(clientId: Int)
    case undecodableAuthenticatedMessage(clientId: Int)
    case authenticatedProtocolMessage(clientId: Int, wireType: ClientWireMessageType)
    case unauthenticatedMessage(clientId: Int, message: String)
    case authenticationDeadline(clientId: Int, deadlineSeconds: UInt64)
    case versionMismatch(clientId: Int, serverVersion: String, clientVersion: String)
    case missingRegisteredAddress(clientId: Int)
    case lockedOut(clientId: Int, address: String)
    case invalidToken(clientId: Int, attempts: Int)
    case lockoutStarted(address: String, attempts: Int)
}

struct MuscleAuthentication {
    let clientId: Int
    let address: String
    let driverIdentity: String
    let respond: TheMuscleAdmission.ResponseHandler
    let source: MuscleAuthenticationSource
}

enum MuscleAuthenticationSource {
    case token
}

enum MuscleAdmissionDecision {
    case admitted(AdmittedClientMessage)
    case handled([MuscleAdmissionEffect])
    case authenticate(MuscleAuthentication)
}

/// Owns the unauthenticated ButtonHeist handshake and client auth phases.
struct TheMuscleAdmission {
    typealias ResponseHandler = SocketResponseHandler

    private var authentication: MuscleAuthenticationFlow

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.authentication = MuscleAuthenticationFlow(
            tokenSource: tokenSource,
            maxFailedAttempts: maxFailedAttempts,
            lockoutDuration: lockoutDuration
        )
    }

    mutating func registerClientAddress(_ clientId: Int, address: String) {
        authentication.registerClientAddress(clientId, address: address)
    }

    mutating func removeAllClients() {
        authentication.removeAllClients()
    }

    func contains(_ clientId: Int) -> Bool {
        authentication.contains(clientId)
    }

    mutating func admitClientMessage(
        _ clientId: Int,
        data: Data,
        respond: @escaping ResponseHandler,
        at now: Date = Date()
    ) -> MuscleAdmissionDecision {
        authentication.admitClientMessage(
            clientId,
            data: data,
            respond: respond,
            at: now
        )
    }

    mutating func completeAuthentication(_ authentication: MuscleAuthentication) -> [MuscleAdmissionEffect] {
        self.authentication.completeAuthentication(authentication)
    }

    func rejectForSessionLock(
        _ clientId: Int,
        diagnostic: SessionLease.SessionLockDiagnostic,
        respond: @escaping ResponseHandler
    ) -> [MuscleAdmissionEffect] {
        authentication.rejectForSessionLock(clientId, diagnostic: diagnostic, respond: respond)
    }

    mutating func removeClient(_ clientId: Int) -> [MuscleAdmissionEffect] {
        authentication.removeClient(clientId)
    }

    func authenticationDeadline(_ clientId: Int, deadlineSeconds: UInt64) -> [MuscleAdmissionEffect] {
        authentication.authenticationDeadline(clientId, deadlineSeconds: deadlineSeconds)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
