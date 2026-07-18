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

private enum TokenFailureState: Equatable, Sendable {
    case clean
    case failing(attempts: Int)
    case lockedOut(until: Date, attempts: Int)
}

private enum TokenFailureEffect: Equatable, Sendable {
    case proceed
    case invalidToken(attempts: Int)
    case lockoutStarted(attempts: Int)
    case lockedOut
}

struct TokenAuthentication {
    private let tokenSource: SessionTokenSource
    private let maxFailedAttempts: Int
    private let lockoutDuration: TimeInterval
    private var addressAuthStates: [String: TokenFailureState] = [:]

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.tokenSource = tokenSource
        self.maxFailedAttempts = maxFailedAttempts
        self.lockoutDuration = lockoutDuration
    }

    var sessionToken: SessionAuthToken { tokenSource.token }

    mutating func admit(
        _ token: SessionAuthToken,
        driverId: DriverID?,
        address: String,
        now: Date = Date()
    ) -> TokenAuthenticationDecision {
        switch checkLockout(for: address, now: now) {
        case .proceed:
            break
        case .lockedOut:
            return .lockedOut(lockoutError())
        case .invalidToken, .lockoutStarted:
            preconditionFailure("Lockout check emitted a token rejection.")
        }

        guard constantTimeEqual(token, tokenSource.token) else {
            let error = ServerError(
                kind: .authFailure,
                message: tokenSource.invalidTokenMessage,
                recoveryHint: tokenSource.configuredTokenRecoveryHint
            )
            switch rejectToken(for: address, now: now) {
            case .invalidToken(let attempts):
                return .rejected(.invalidToken(error: error, attempts: attempts))
            case .lockoutStarted(let attempts):
                return .rejected(.lockoutStarted(error: error, attempts: attempts))
            case .lockedOut:
                return .lockedOut(lockoutError())
            case .proceed:
                preconditionFailure("Token rejection emitted an acceptance effect.")
            }
        }

        acceptToken(for: address)
        return .accepted(owner: tokenSource.owner(driverId: driverId))
    }

    mutating func admit(
        _ clientId: Int,
        address: String,
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
            return .authenticate(ClientAdmission.Authentication.Proof(
                clientId: clientId,
                address: address,
                owner: owner,
                respond: respond,
                source: .token
            ))
        }
    }

    private mutating func checkLockout(for address: String, now: Date) -> TokenFailureEffect {
        switch addressAuthState(for: address) {
        case .clean, .failing:
            return .proceed
        case .lockedOut(let expiry, _) where now < expiry:
            return .lockedOut
        case .lockedOut:
            storeAddressAuthState(.clean, for: address)
            return .proceed
        }
    }

    private mutating func rejectToken(for address: String, now: Date) -> TokenFailureEffect {
        switch addressAuthState(for: address) {
        case .clean:
            return recordFailedAttempt(previousAttempts: 0, for: address, now: now)
        case .failing(let attempts):
            return recordFailedAttempt(previousAttempts: attempts, for: address, now: now)
        case .lockedOut(let expiry, _) where now < expiry:
            return .lockedOut
        case .lockedOut:
            return recordFailedAttempt(previousAttempts: 0, for: address, now: now)
        }
    }

    private mutating func acceptToken(for address: String) {
        storeAddressAuthState(.clean, for: address)
    }

    private mutating func recordFailedAttempt(
        previousAttempts: Int,
        for address: String,
        now: Date
    ) -> TokenFailureEffect {
        let attempts = previousAttempts + 1
        guard attempts >= maxFailedAttempts else {
            storeAddressAuthState(.failing(attempts: attempts), for: address)
            return .invalidToken(attempts: attempts)
        }
        storeAddressAuthState(
            .lockedOut(until: now.addingTimeInterval(lockoutDuration), attempts: attempts),
            for: address
        )
        return .lockoutStarted(attempts: attempts)
    }

    private func addressAuthState(for address: String) -> TokenFailureState {
        addressAuthStates[address] ?? .clean
    }

    private mutating func storeAddressAuthState(
        _ state: TokenFailureState,
        for address: String
    ) {
        switch state {
        case .clean:
            addressAuthStates.removeValue(forKey: address)
        case .failing, .lockedOut:
            addressAuthStates[address] = state
        }
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
