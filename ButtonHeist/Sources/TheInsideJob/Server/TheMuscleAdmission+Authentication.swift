#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import TheScore

let muscleAuthenticationLogger = ButtonHeistLog.logger(.insideJob(.auth))

/// Owns the authentication phases inside TheMuscle admission.
struct MuscleAuthenticationFlow {
    private var clientRegistry = TheMuscleClientRegistry()
    private var messageRateLimiters: [Int: MessageRateLimiter] = [:]
    private var tokenAdmission: SessionAdmission

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.tokenAdmission = SessionAdmission(
            tokenSource: tokenSource,
            maxFailedAttempts: maxFailedAttempts,
            lockoutDuration: lockoutDuration
        )
    }

    mutating func registerClientAddress(_ clientId: Int, address: String) {
        clientRegistry.registerAddress(clientId, address: address)
        messageRateLimiters[clientId] = messageRateLimiters[clientId] ?? MessageRateLimiter()
    }

    mutating func removeAllClients() {
        clientRegistry.removeAll()
        messageRateLimiters.removeAll()
    }

    func contains(_ clientId: Int) -> Bool {
        clientRegistry.contains(clientId)
    }

    mutating func admitClientMessage(
        _ clientId: Int,
        data: Data,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
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
        clientRegistry.authenticate(
            authentication.clientId,
            address: authentication.address
        )

        switch authentication.source {
        case .token:
            return [.log(.clientAuthenticatedWithToken(clientId: authentication.clientId))]
        }
    }

    func rejectForSessionLock(
        _ clientId: Int,
        diagnostic: SessionLease.SessionLockDiagnostic,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> [MuscleAdmissionEffect] {
        let payload = diagnostic.payload()
        return [
            .log(.sessionLockRejected(clientId: clientId, message: payload.message)),
            .sendResponse(.sessionLocked(payload), requestId: nil, respond: respond),
            .delayedDisconnect(clientId: clientId),
        ]
    }

    mutating func removeClient(_ clientId: Int) -> [MuscleAdmissionEffect] {
        messageRateLimiters.removeValue(forKey: clientId)
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
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        at now: Date
    ) -> [MuscleAdmissionEffect]? {
        var limiter = messageRateLimiters[clientId] ?? MessageRateLimiter()
        guard limiter.recordMessage(at: now) else {
            messageRateLimiters[clientId] = limiter
            return nil
        }

        let shouldNotify = limiter.markNotifiedIfNeeded()
        messageRateLimiters[clientId] = limiter
        guard shouldNotify else { return [.log(.rateLimited(clientId: clientId))] }

        let message = "Rate limited: max \(MessageRateLimiter.defaultMaxMessagesPerSecond) messages per second"
        return [
            .log(.rateLimited(clientId: clientId)),
            .sendResponse(.error(ServerError(kind: .general, message: message)), requestId: nil, respond: respond),
        ]
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
