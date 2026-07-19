import Foundation

import TheScore

/// Owns token policy and per-address auth admission state for `TheMuscle`.
extension ClientAdmission {
enum TokenAuthenticationDecision: Equatable, Sendable {
    case accepted(owner: SessionOwner)
    case rejected(TokenAuthenticationRejection)
    case lockedOut(ServerError)
}

enum TokenAuthenticationRejection: Equatable, Sendable {
    case invalidToken(error: ServerError, attempts: Int)
    case lockoutStarted(error: ServerError, attempts: Int)
}

private struct TokenFailureState: Equatable, Sendable {
    let attempts: Int
    let lastFailureAt: Date
    let lockedOutUntil: Date?
}

struct TokenAuthentication {
    private let sessionToken: SessionAuthToken
    private let policy: InsideJobAuthenticationPolicy
    private var addressAuthStates: [ClientNetworkAddress: TokenFailureState] = [:]

    init(sessionToken: SessionAuthToken, policy: InsideJobAuthenticationPolicy) {
        self.sessionToken = sessionToken
        self.policy = policy
    }

    mutating func admit(
        _ token: SessionAuthToken,
        driverId: DriverID?,
        address: ClientNetworkAddress,
        now: Date = Date()
    ) -> TokenAuthenticationDecision {
        pruneExpiredStates(at: now)
        if addressAuthStates[address]?.lockedOutUntil != nil {
            return .lockedOut(lockoutError())
        }

        guard !constantTimeEqual(token, sessionToken) else {
            addressAuthStates.removeValue(forKey: address)
            return .accepted(owner: driverId.map(SessionOwner.driver) ?? .token(sessionToken))
        }

        let error = ServerError(
            kind: .authFailure,
            message: "Invalid token. Retry with the session token.",
            recoveryHint: "Retry with the session token."
        )
        return .rejected(rejectToken(for: address, now: now, error: error))
    }

    mutating func admit(
        _ clientId: Int,
        address: ClientNetworkAddress,
        payload: AuthenticatePayload,
        respond: @escaping ClientAdmission.ResponseHandler
    ) -> ClientAdmission.Decision {
        switch admit(payload.token, driverId: payload.driverId, address: address) {
        case .lockedOut(let error):
            return .handled([
                .log(.lockedOut(clientId: clientId, address: address)),
                .sendResponse(.error(error), requestId: nil, respond: respond),
                .delayedDisconnect(clientId: clientId),
            ])
        case .rejected(let rejection):
            switch rejection {
            case .invalidToken(let error, let attempts):
                return .handled([
                    .log(.invalidToken(clientId: clientId, attempts: attempts)),
                    .sendResponse(.error(error), requestId: nil, respond: respond),
                    .delayedDisconnect(clientId: clientId),
                ])
            case .lockoutStarted(let error, let attempts):
                return .handled([
                    .log(.lockoutStarted(address: address, attempts: attempts)),
                    .log(.invalidToken(clientId: clientId, attempts: attempts)),
                    .sendResponse(.error(error), requestId: nil, respond: respond),
                    .delayedDisconnect(clientId: clientId),
                ])
            }
        case .accepted(let owner):
            return .sessionAdmission(ClientAdmission.SessionAdmission(
                clientId: clientId,
                owner: owner,
                respond: respond
            ))
        }
    }

    private mutating func rejectToken(
        for address: ClientNetworkAddress,
        now: Date,
        error: ServerError
    ) -> TokenAuthenticationRejection {
        let attempts = (addressAuthStates[address]?.attempts ?? 0) + 1
        let startsLockout = attempts >= policy.maximumFailedAttempts
        let state = TokenFailureState(
            attempts: attempts,
            lastFailureAt: now,
            lockedOutUntil: startsLockout ? now.addingTimeInterval(policy.lockoutDuration) : nil
        )
        guard retain(state, for: address), startsLockout else {
            return .invalidToken(error: error, attempts: attempts)
        }
        return .lockoutStarted(error: error, attempts: attempts)
    }

    private mutating func retain(
        _ state: TokenFailureState,
        for address: ClientNetworkAddress
    ) -> Bool {
        if addressAuthStates[address] == nil,
           addressAuthStates.count >= policy.maximumTrackedFailedAddresses,
           !evictOldestFailingAddress() {
            return false
        }
        addressAuthStates[address] = state
        return true
    }

    private mutating func pruneExpiredStates(at now: Date) {
        addressAuthStates = addressAuthStates.filter { _, state in
            if let lockedOutUntil = state.lockedOutUntil { return now < lockedOutUntil }
            return now < state.lastFailureAt.addingTimeInterval(policy.failedAddressRetentionDuration)
        }
    }

    private mutating func evictOldestFailingAddress() -> Bool {
        let oldest = addressAuthStates.compactMap { address, state -> (ClientNetworkAddress, Date)? in
            guard state.lockedOutUntil == nil else { return nil }
            return (address, state.lastFailureAt)
        }.min { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.description < rhs.0.description : lhs.1 < rhs.1
        }
        guard let oldest else { return false }
        addressAuthStates.removeValue(forKey: oldest.0)
        return true
    }

    private func lockoutError() -> ServerError {
        ServerError(kind: .authFailure, message: "Too many failed attempts. Try again later.")
    }

    private func constantTimeEqual(_ a: SessionAuthToken, _ b: SessionAuthToken) -> Bool {
        let aBytes = Array(a.description.utf8)
        let bBytes = Array(b.description.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (lhs, rhs) in zip(aBytes, bBytes) {
            result |= lhs ^ rhs
        }
        return result == 0
    }

}
}
