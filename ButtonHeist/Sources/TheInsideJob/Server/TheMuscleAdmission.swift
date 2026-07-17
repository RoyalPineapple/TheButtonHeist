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
    case sendResponse(ServerMessage, requestId: RequestID?, respond: TheMuscleAdmission.ResponseHandler)
    case sendClient(ServerMessage, requestId: RequestID?, clientId: Int)
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
    case versionMismatch(
        clientId: Int,
        serverVersion: ButtonHeistVersion,
        clientVersion: ButtonHeistVersion
    )
    case missingRegisteredAddress(clientId: Int)
    case lockedOut(clientId: Int, address: String)
    case invalidToken(clientId: Int, attempts: Int)
    case lockoutStarted(address: String, attempts: Int)
}

struct MuscleAuthentication {
    let clientId: Int
    let address: String
    let owner: SessionOwner
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

    private var clientRegistry = TheMuscleClientRegistry()
    private var tokenAdmission: TokenAdmission

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.tokenAdmission = TokenAdmission(
            tokenSource: tokenSource,
            maxFailedAttempts: maxFailedAttempts,
            lockoutDuration: lockoutDuration
        )
    }

    mutating func registerClientAddress(_ clientId: Int, address: String) {
        clientRegistry.registerAddress(clientId, address: address)
    }

    mutating func removeAllClients() {
        clientRegistry.removeAll()
    }

    func contains(_ clientId: Int) -> Bool {
        clientRegistry.contains(clientId)
    }

    mutating func admitClientMessage(
        _ clientId: Int,
        data: Data,
        respond: @escaping ResponseHandler,
        at now: Date = Date()
    ) -> MuscleAdmissionDecision {
        if let rateLimitEffect = rateLimitEffect(clientId, respond: respond, at: now) {
            return .handled(rateLimitEffect)
        }

        guard let envelope = MuscleAuthenticationRequestDecoder.decode(data) else {
            let effect = clientRegistry.phase(for: clientId)?.isAuthenticated == true
                ? MuscleAuthenticationRejection.undecodableAuthenticatedMessage(clientId, respond: respond)
                : MuscleAuthenticationRejection.undecodableUnauthenticatedMessage(clientId, respond: respond)
            return .handled(effect)
        }

        guard clientRegistry.phase(for: clientId)?.isAuthenticated != true else {
            return MuscleAuthenticatedCommandPhase.admit(clientId, envelope: envelope, respond: respond)
        }

        return MuscleHandshakePhase.handle(
            clientId,
            envelope: envelope,
            respond: respond,
            clientRegistry: &clientRegistry,
            tokenAdmission: &tokenAdmission
        )
    }

    mutating func completeAuthentication(_ authentication: MuscleAuthentication) -> [MuscleAdmissionEffect] {
        switch clientRegistry.completeAuthentication(authentication.clientId) {
        case .advanced(_, effect: .authenticated):
            break
        case .advanced(_, effect: .helloValidated):
            preconditionFailure("Authentication completion cannot emit hello validation.")
        case .missingClient:
            return [
                .log(.missingRegisteredAddress(clientId: authentication.clientId)),
                .sendResponse(
                    .error(ServerError(kind: .authFailure, message: "Connection rejected.")),
                    requestId: nil,
                    respond: authentication.respond
                ),
                .delayedDisconnect(clientId: authentication.clientId),
            ]
        case .rejected:
            return MuscleAuthenticationRejection.unauthenticatedMessage(
                authentication.clientId,
                message: "Authentication requires clientHello first.",
                requestId: nil,
                respond: authentication.respond
            )
        }

        switch authentication.source {
        case .token:
            return [.log(.clientAuthenticatedWithToken(clientId: authentication.clientId))]
        }
    }

    func rejectForSessionLock(
        _ clientId: Int,
        diagnostic: SessionLease.SessionLockDiagnostic,
        respond: @escaping ResponseHandler
    ) -> [MuscleAdmissionEffect] {
        let payload = diagnostic.payload()
        return [
            .log(.sessionLockRejected(clientId: clientId, message: payload.message)),
            .sendResponse(.sessionLocked(payload), requestId: nil, respond: respond),
            .delayedDisconnect(clientId: clientId),
        ]
    }

    mutating func removeClient(_ clientId: Int) -> [MuscleAdmissionEffect] {
        _ = clientRegistry.remove(clientId)
        return []
    }

    func authenticationDeadline(_ clientId: Int, deadlineSeconds: UInt64) -> [MuscleAdmissionEffect] {
        MuscleAuthenticationDeadlinePhase.effect(
            clientId: clientId,
            phase: clientRegistry.phase(for: clientId),
            deadlineSeconds: deadlineSeconds
        )
    }

    private mutating func rateLimitEffect(
        _ clientId: Int,
        respond: @escaping ResponseHandler,
        at now: Date
    ) -> [MuscleAdmissionEffect]? {
        switch clientRegistry.recordMessage(clientId, at: now) {
        case .accepted:
            return nil
        case .rateLimited(shouldNotify: false):
            return [.log(.rateLimited(clientId: clientId))]
        case .rateLimited(shouldNotify: true):
            let message: ServerErrorMessage
            do {
                message = try ServerErrorMessage(
                    validating: "Rate limited: max \(MessageRateLimiter.defaultMaxMessagesPerSecond) messages per second"
                )
            } catch {
                return [.log(.rateLimited(clientId: clientId))]
            }
            return [
                .log(.rateLimited(clientId: clientId)),
                .sendResponse(
                    .error(ServerError(kind: .general, message: message)),
                    requestId: nil,
                    respond: respond
                ),
            ]
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
