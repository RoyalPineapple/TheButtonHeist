import Foundation

import TheScore

/// Owns token policy and per-address auth admission state for `TheMuscle`.
struct TokenAdmission {
    enum TokenDecision: Equatable, Sendable {
        case accepted(owner: SessionOwner)
        case rejected(TokenRejection)
        case lockedOut(ServerError)
    }

    enum TokenRejection: Equatable, Sendable {
        case invalidToken(error: ServerError, attempts: Int)
        case lockoutStarted(error: ServerError, attempts: Int)
    }

    private let tokenSource: SessionTokenSource
    private let maxFailedAttempts: Int
    private let lockoutDuration: TimeInterval
    private var addressAuthStates: [String: AddressAuthenticationFailureMachine.State] = [:]

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.tokenSource = tokenSource
        self.maxFailedAttempts = maxFailedAttempts
        self.lockoutDuration = lockoutDuration
    }

    mutating func decideToken(
        _ token: SessionAuthToken,
        driverId: DriverID?,
        address: String,
        now: Date = Date()
    ) -> TokenDecision {
        switch checkLockout(for: address, now: now) {
        case .proceed:
            break
        case .lockedOut:
            return .lockedOut(lockoutError())
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
            }
        }

        acceptToken(for: address)
        return .accepted(owner: tokenSource.owner(driverId: driverId))
    }

    private var addressAuthenticationMachine: AddressAuthenticationFailureMachine {
        AddressAuthenticationFailureMachine(
            maxFailedAttempts: maxFailedAttempts,
            lockoutDuration: lockoutDuration
        )
    }

    private mutating func checkLockout(
        for address: String,
        now: Date
    ) -> AddressAuthenticationFailureMachine.LockoutEffect {
        let transition = addressAuthenticationMachine.checkLockout(addressAuthState(for: address), now: now)
        storeAddressAuthState(transition.state, for: address)
        return transition.effect
    }

    private mutating func rejectToken(
        for address: String,
        now: Date
    ) -> AddressAuthenticationFailureMachine.RejectionEffect {
        let transition = addressAuthenticationMachine.rejectToken(addressAuthState(for: address), now: now)
        storeAddressAuthState(transition.state, for: address)
        return transition.effect
    }

    private mutating func acceptToken(for address: String) {
        let state = addressAuthenticationMachine.acceptToken(addressAuthState(for: address))
        storeAddressAuthState(state, for: address)
    }

    private func addressAuthState(for address: String) -> AddressAuthenticationFailureMachine.State {
        addressAuthStates[address] ?? .clean
    }

    private mutating func storeAddressAuthState(
        _ state: AddressAuthenticationFailureMachine.State,
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

private struct AddressAuthenticationFailureMachine {
    let maxFailedAttempts: Int
    let lockoutDuration: TimeInterval

    enum State: Equatable, Sendable {
        case clean
        case failing(attempts: Int)
        case lockedOut(until: Date, attempts: Int)
    }

    enum LockoutEffect: Equatable, Sendable {
        case proceed
        case lockedOut
    }

    enum RejectionEffect: Equatable, Sendable {
        case invalidToken(attempts: Int)
        case lockoutStarted(attempts: Int)
        case lockedOut
    }

    struct LockoutTransition: Equatable, Sendable {
        let state: State
        let effect: LockoutEffect
    }

    struct RejectionTransition: Equatable, Sendable {
        let state: State
        let effect: RejectionEffect
    }

    func checkLockout(_ state: State, now: Date) -> LockoutTransition {
        switch state {
        case .clean, .failing:
            return LockoutTransition(state: state, effect: .proceed)
        case .lockedOut(let expiry, _) where now < expiry:
            return LockoutTransition(state: state, effect: .lockedOut)
        case .lockedOut:
            return LockoutTransition(state: .clean, effect: .proceed)
        }
    }

    func rejectToken(_ state: State, now: Date) -> RejectionTransition {
        switch state {
        case .clean:
            return failedAttempt(previousAttempts: 0, now: now)
        case .failing(let attempts):
            return failedAttempt(previousAttempts: attempts, now: now)
        case .lockedOut(let expiry, _) where now < expiry:
            return RejectionTransition(state: state, effect: .lockedOut)
        case .lockedOut:
            return failedAttempt(previousAttempts: 0, now: now)
        }
    }

    func acceptToken(_: State) -> State {
        .clean
    }

    private func failedAttempt(
        previousAttempts: Int,
        now: Date
    ) -> RejectionTransition {
        let attempts = previousAttempts + 1
        guard attempts >= maxFailedAttempts else {
            return RejectionTransition(
                state: .failing(attempts: attempts),
                effect: .invalidToken(attempts: attempts)
            )
        }
        return RejectionTransition(
            state: .lockedOut(until: now.addingTimeInterval(lockoutDuration), attempts: attempts),
            effect: .lockoutStarted(attempts: attempts)
        )
    }
}
