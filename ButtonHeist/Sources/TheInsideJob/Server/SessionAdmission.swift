import Foundation

import TheScore

/// Owns token policy and per-address auth admission state for `TheMuscle`.
struct SessionAdmission {
    private enum AddressAuthPhase {
        case failing(attempts: Int)
        case lockedOut(until: Date, attempts: Int)
    }

    enum TokenDecision: Equatable, Sendable {
        case accepted(driverIdentity: String)
        case rejected(TokenRejection)
        case lockedOut(ServerError)
    }

    enum TokenRejection: Equatable, Sendable {
        case invalidToken(message: String, attempts: Int)
        case lockoutStarted(message: String, attempts: Int)
    }

    private let tokenSource: SessionTokenSource
    private let maxFailedAttempts: Int
    private let lockoutDuration: TimeInterval
    private var addressAuthStates: [String: AddressAuthPhase] = [:]

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.tokenSource = tokenSource
        self.maxFailedAttempts = maxFailedAttempts
        self.lockoutDuration = lockoutDuration
    }

    func emptyTokenError() -> ServerError {
        ServerError(
            kind: .authFailure,
            message: "Token is required. Retry with the configured token."
        )
    }

    mutating func decideToken(_ token: String, driverId: String?, address: String, now: Date = Date()) -> TokenDecision {
        if let lockout = lockoutError(address: address, now: now) {
            return .lockedOut(lockout)
        }

        guard constantTimeEqual(token, tokenSource.token) else {
            let attempts = recordFailedAttempt(address: address, now: now)
            let message = tokenSource.invalidTokenMessage
            if attempts >= maxFailedAttempts {
                return .rejected(.lockoutStarted(message: message, attempts: attempts))
            }
            return .rejected(.invalidToken(message: message, attempts: attempts))
        }

        clearFailedAttempts(address: address)
        return .accepted(driverIdentity: tokenSource.effectiveDriverId(driverId: driverId))
    }

    private mutating func lockoutError(address: String, now: Date) -> ServerError? {
        guard case .lockedOut(let expiry, _) = addressAuthStates[address] else { return nil }
        if now < expiry {
            return ServerError(kind: .authFailure, message: "Too many failed attempts. Try again later.")
        }
        addressAuthStates.removeValue(forKey: address)
        return nil
    }

    @discardableResult
    private mutating func recordFailedAttempt(address: String, now: Date) -> Int {
        let currentAttempts = switch addressAuthStates[address] {
        case .failing(let count): count
        case .lockedOut(_, let count): count
        case nil: 0
        }
        let newAttempts = currentAttempts + 1
        if newAttempts >= maxFailedAttempts {
            addressAuthStates[address] = .lockedOut(
                until: now.addingTimeInterval(lockoutDuration),
                attempts: newAttempts
            )
        } else {
            addressAuthStates[address] = .failing(attempts: newAttempts)
        }
        return newAttempts
    }

    private mutating func clearFailedAttempts(address: String) {
        addressAuthStates.removeValue(forKey: address)
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (lhs, rhs) in zip(aBytes, bBytes) {
            result |= lhs ^ rhs
        }
        return result == 0
    }
}
