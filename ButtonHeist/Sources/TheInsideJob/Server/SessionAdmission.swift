import Foundation

import ButtonHeistSupport
import TheScore

/// Owns token policy and per-address auth admission state for `TheMuscle`.
struct SessionAdmission {
    enum TokenDecision: Equatable, Sendable {
        case accepted(driverIdentity: String)
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

    func emptyTokenError() -> ServerError {
        ServerError(
            kind: .authFailure,
            message: tokenSource.emptyTokenMessage,
            recoveryHint: tokenSource.configuredTokenRecoveryHint
        )
    }

    mutating func decideToken(_ token: String, driverId: String?, address: String, now: Date = Date()) -> TokenDecision {
        switch transitionAddress(address, with: .checkLockout(now: now)).singleAddressEffect {
        case .proceed:
            break
        case .lockedOut:
            return .lockedOut(lockoutError())
        case .accepted, .invalidToken, .lockoutStarted:
            preconditionFailure("Lockout check emitted an invalid token decision effect.")
        }

        guard constantTimeEqual(token, tokenSource.token) else {
            let error = ServerError(
                kind: .authFailure,
                message: tokenSource.invalidTokenMessage,
                recoveryHint: tokenSource.configuredTokenRecoveryHint
            )
            switch transitionAddress(address, with: .rejectToken(now: now)).singleAddressEffect {
            case .invalidToken(let attempts):
                return .rejected(.invalidToken(error: error, attempts: attempts))
            case .lockoutStarted(let attempts):
                return .rejected(.lockoutStarted(error: error, attempts: attempts))
            case .lockedOut:
                return .lockedOut(lockoutError())
            case .proceed, .accepted:
                preconditionFailure("Token rejection emitted an invalid address auth effect.")
            }
        }

        switch transitionAddress(address, with: .acceptToken).singleAddressEffect {
        case .accepted:
            break
        case .proceed, .invalidToken, .lockoutStarted, .lockedOut:
            preconditionFailure("Token acceptance emitted an invalid address auth effect.")
        }
        return .accepted(driverIdentity: tokenSource.effectiveDriverId(driverId: driverId))
    }

    private mutating func transitionAddress(
        _ address: String,
        with event: AddressAuthenticationFailureMachine.Event
    ) -> AddressAuthenticationTransition {
        var driver = StateDriver(
            initial: addressAuthState(for: address),
            machine: AddressAuthenticationFailureMachine(
                maxFailedAttempts: maxFailedAttempts,
                lockoutDuration: lockoutDuration
            )
        )
        let change = driver.send(event)
        storeAddressAuthState(driver.state, for: address)
        return AddressAuthenticationTransition(change)
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

private struct AddressAuthenticationFailureMachine: SimpleStateMachine {
    let maxFailedAttempts: Int
    let lockoutDuration: TimeInterval

    enum State: Equatable, Sendable {
        case clean
        case failing(attempts: Int)
        case lockedOut(until: Date, attempts: Int)
    }

    enum Event: Equatable, Sendable {
        case checkLockout(now: Date)
        case rejectToken(now: Date)
        case acceptToken
    }

    enum Effect: Equatable, Sendable {
        case proceed
        case accepted
        case invalidToken(attempts: Int)
        case lockoutStarted(attempts: Int)
        case lockedOut
    }

    enum Rejection: Equatable, Sendable {}

    func advance(_ state: State, with event: Event) -> StateChange<State, Effect, Rejection> {
        switch event {
        case .checkLockout(let now):
            return checkLockout(state, now: now)
        case .rejectToken(let now):
            return rejectToken(state, now: now)
        case .acceptToken:
            return .changed(to: .clean, effects: [.accepted])
        }
    }

    private func checkLockout(_ state: State, now: Date) -> StateChange<State, Effect, Rejection> {
        switch state {
        case .clean, .failing:
            return .changed(to: state, effects: [.proceed])
        case .lockedOut(let expiry, _) where now < expiry:
            return .changed(to: state, effects: [.lockedOut])
        case .lockedOut:
            return .changed(to: .clean, effects: [.proceed])
        }
    }

    private func rejectToken(_ state: State, now: Date) -> StateChange<State, Effect, Rejection> {
        switch state {
        case .clean:
            return failedAttempt(previousAttempts: 0, now: now)
        case .failing(let attempts):
            return failedAttempt(previousAttempts: attempts, now: now)
        case .lockedOut(let expiry, _) where now < expiry:
            return .changed(to: state, effects: [.lockedOut])
        case .lockedOut:
            return failedAttempt(previousAttempts: 0, now: now)
        }
    }

    private func failedAttempt(
        previousAttempts: Int,
        now: Date
    ) -> StateChange<State, Effect, Rejection> {
        let attempts = previousAttempts + 1
        guard attempts >= maxFailedAttempts else {
            return .changed(to: .failing(attempts: attempts), effects: [.invalidToken(attempts: attempts)])
        }
        return .changed(
            to: .lockedOut(until: now.addingTimeInterval(lockoutDuration), attempts: attempts),
            effects: [.lockoutStarted(attempts: attempts)]
        )
    }
}

private struct AddressAuthenticationTransition {
    let state: AddressAuthenticationFailureMachine.State
    let singleAddressEffect: AddressAuthenticationFailureMachine.Effect

    init(_ change: StateChange<
        AddressAuthenticationFailureMachine.State,
        AddressAuthenticationFailureMachine.Effect,
        AddressAuthenticationFailureMachine.Rejection
    >) {
        switch change {
        case .changed(let state, _):
            guard let effect = change.singleEffect else {
                preconditionFailure("AddressAuthenticationFailureMachine must emit exactly one effect.")
            }
            self.state = state
            self.singleAddressEffect = effect
        case .rejected(let rejection, _):
            switch rejection {}
        }
    }
}
