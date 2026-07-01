struct ElementInflationReducer: Sendable, Equatable {
    let maxAttempts: Int

    func reduce(
        _ state: ElementInflationState,
        event: ElementInflationEvent
    ) -> ElementInflationState {
        switch (state, event) {
        case (.retrying(let failedAttempt, let reason), .retryReady):
            let nextAttempt = failedAttempt + 1
            guard nextAttempt < maxAttempts else {
                return .retryExhausted(reason)
            }
            return .resolving(.afterRetry(attempt: nextAttempt, reason: reason))

        case (.resolving(let pass), .retryRequested(let reason)):
            return .retrying(failedAttempt: pass.attempt, reason: reason)

        case (.resolving, .retryReady),
             (.retrying, .retryRequested),
             (.retryExhausted, _):
            return state
        }
    }
}

enum ElementInflationState: Sendable, Equatable {
    case resolving(ElementInflationResolutionPass)
    case retrying(failedAttempt: Int, reason: ElementInflationRetryReason)
    case retryExhausted(ElementInflationRetryReason)
}

enum ElementInflationEvent: Sendable, Equatable {
    case retryRequested(ElementInflationRetryReason)
    case retryReady
}

enum ElementInflationResolutionPass: Sendable, Equatable {
    case initial
    case afterRetry(attempt: Int, reason: ElementInflationRetryReason)

    var attempt: Int {
        switch self {
        case .initial:
            return 0
        case .afterRetry(let attempt, _):
            return attempt
        }
    }

    var allowsKnownFallback: Bool {
        switch self {
        case .initial, .afterRetry(_, .objectDeallocated):
            return true
        case .afterRetry(_, .staleTarget), .afterRetry(_, .activationPointOffscreen):
            return false
        }
    }
}

enum ElementInflationRetryReason: String, CustomStringConvertible, Sendable, Equatable {
    case objectDeallocated
    case staleTarget
    case activationPointOffscreen

    var description: String {
        rawValue
    }

    var failureDescription: String {
        switch self {
        case .objectDeallocated:
            return "the live object was deallocated"
        case .staleTarget:
            return "the live target no longer matched"
        case .activationPointOffscreen:
            return "the activation point stayed off-screen"
        }
    }
}
