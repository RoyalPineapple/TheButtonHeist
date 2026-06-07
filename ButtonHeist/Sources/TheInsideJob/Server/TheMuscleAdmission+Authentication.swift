#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import TheScore

let muscleAuthenticationLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

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

    mutating func completeAuthentication(_ authentication: MuscleAuthentication) -> MuscleAdmissionEffect {
        clientRegistry.authenticate(
            authentication.clientId,
            address: authentication.address
        )

        switch authentication.source {
        case .token:
            muscleAuthenticationLogger.info("Client \(authentication.clientId) authenticated with token")
            return .none
        }
    }

    func rejectForSessionLock(
        _ clientId: Int,
        diagnostic: SessionLease.SessionLockDiagnostic,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        let payload = diagnostic.payload()
        muscleAuthenticationLogger.warning("Client \(clientId) rejected - \(payload.message, privacy: .public)")
        return .response(.sessionLocked(payload), respond: respond, disconnect: clientId)
    }

    mutating func removeClient(_ clientId: Int) -> MuscleAdmissionEffect {
        messageRateLimiters.removeValue(forKey: clientId)
        _ = clientRegistry.remove(clientId)
        return .none
    }

    func authenticationDeadline(_ clientId: Int, deadlineSeconds: UInt64) -> MuscleAdmissionEffect {
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
    ) -> MuscleAdmissionEffect? {
        var limiter = messageRateLimiters[clientId] ?? MessageRateLimiter()
        guard limiter.recordMessage(at: now) else {
            messageRateLimiters[clientId] = limiter
            return nil
        }

        let shouldNotify = limiter.markNotifiedIfNeeded()
        messageRateLimiters[clientId] = limiter
        muscleAuthenticationLogger.warning("Client \(clientId) rate limited, handling message")
        guard shouldNotify else { return MuscleAdmissionEffect.none }

        let message = "Rate limited: max \(MessageRateLimiter.defaultMaxMessagesPerSecond) messages per second"
        return .response(.error(ServerError(kind: .general, message: message)), respond: respond)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
