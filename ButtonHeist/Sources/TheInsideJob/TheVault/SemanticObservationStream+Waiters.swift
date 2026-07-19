#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

internal enum SemanticObservationWaitResult: Sendable, Equatable {
    case observation(ObservationEntry)
    case cycleCompleted
    case deadlineReached
    case cancelled
    case unavailable(ObservationHistoryReadError)
}

internal struct SemanticObservationWaiter: Sendable {
    let cursor: ObservationCursor?
    let scope: SemanticObservationScope
    let completesAfterObservationCycle: Bool
    let oneShot: TimedOneShot<SemanticObservationWaitResult>
}

@MainActor
extension SemanticObservationStream {
    internal func waitForObservation(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope,
        deadline: SemanticObservationDeadline?,
        completingAfterCurrentCycle: Bool = false
    ) async -> SemanticObservationWaitResult {
        switch observationStore.read(after: cursor, scope: scope) {
        case .entry(let entry):
            return .observation(entry)
        case .failure(let error):
            return .unavailable(error)
        case .pending:
            break
        }

        if Task.isCancelled {
            return .cancelled
        }
        if let deadline,
           !deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
            return .deadlineReached
        }

        let waiterID = observationWaiters.reserveID()
        let oneShot = TimedOneShot<SemanticObservationWaitResult>()
        let subscription = subscribe(scope: scope)
        defer { subscription.cancel() }

        return await oneShot.wait(
            cancellationValue: .cancelled,
            onRegistered: { oneShot in
                observationWaiters.insert(SemanticObservationWaiter(
                    cursor: cursor,
                    scope: scope,
                    completesAfterObservationCycle: completingAfterCurrentCycle,
                    oneShot: oneShot
                ), id: waiterID)
                resolveObservationWaiterIfAvailable(waiterID)
                armObservationDeadline(deadline, waiterID: waiterID, oneShot: oneShot)
            },
            onFinished: {
                observationWaiters.remove(id: waiterID)?.oneShot.cancelTimeout()
            }
        )
    }

    internal func latestObservationCursor(
        scope: SemanticObservationScope
    ) -> ObservationCursor? {
        observationStore.latestCursor(scope: scope)
    }

    internal func retainedObservationEntries(
        scope: SemanticObservationScope
    ) -> [ObservationEntry] {
        observationStore.retainedEntries(scope: scope)
    }

    internal func settledCapture(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledCapture? {
        observationStore.settledCapture(scope: scope, at: sequence)
    }

    internal func settledEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledObservationEvent? {
        let requiredSequence = baselineSequence(for: scope, after: sequence)
        if timeout == 0 {
            guard isActive else { return nil }
            if scope != .discovery {
                return cleanObservation(scope: scope, after: requiredSequence)?.event
            }
        }
        let requiresFreshDiscoveryCycle = timeout == 0 && scope == .discovery

        if !requiresFreshDiscoveryCycle,
           let latest = cleanObservation(scope: scope, after: requiredSequence)?.event {
            return latest
        }

        let deadline = timeout == 0 ? nil : timeout.map {
            SemanticObservationDeadline(
                start: CFAbsoluteTimeGetCurrent(),
                timeoutSeconds: $0
            )
        }
        var cursor = observationStore.latestCursor(scope: scope)
        while true {
            switch await waitForObservation(
                after: cursor,
                scope: scope,
                deadline: deadline,
                completingAfterCurrentCycle: timeout == 0 && scope == .discovery
            ) {
            case .observation(let entry):
                cursor = entry.cursor
                if let latest = cleanObservation(scope: scope, after: requiredSequence)?.event {
                    return latest
                }
            case .cycleCompleted:
                return cleanObservation(scope: scope, after: requiredSequence)?.event
            case .deadlineReached, .cancelled, .unavailable:
                return nil
            }
        }
    }

    internal func observationWindow(
        from baseline: SettledCapture,
        through currentEvent: SettledObservationEvent
    ) -> ObservationWindow? {
        observationStore.observationWindow(from: baseline, through: currentEvent)
    }

    static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else { return SettleSession.defaultTimeoutMs }
        guard timeout > 0 else { return 0 }
        let milliseconds = (timeout * 1_000).rounded(.up)
        return milliseconds >= Double(Int.max) ? Int.max : max(1, Int(milliseconds))
    }

    func completeObservationWaiters(
        completedScope: SemanticObservationScope? = nil
    ) {
        let waiters = observationWaiters.removeAll {
            observationWaitResult(for: $0, completedScope: completedScope) != nil
        }
        for waiter in waiters {
            guard let result = observationWaitResult(
                for: waiter,
                completedScope: completedScope
            ) else {
                preconditionFailure("removed an unresolved semantic observation waiter")
            }
            waiter.oneShot.resolve(returning: result)
        }
    }

    func cancelObservationWaiters() {
        for waiter in observationWaiters.removeAll() {
            waiter.oneShot.resolve(returning: .cancelled)
        }
    }

    private func baselineSequence(
        for scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledObservationSequence? {
        if let sequence {
            return sequence
        }
        let currentSequence = latestEvent?.sequence
        if scope == .discovery || !isActive {
            return currentSequence
        }
        return nil
    }

    private func resolveObservationWaiterIfAvailable(
        _ waiterID: UInt64,
        completedScope: SemanticObservationScope? = nil
    ) {
        guard let waiter = observationWaiters[waiterID],
              let result = observationWaitResult(
            for: waiter,
            completedScope: completedScope
        ) else { return }
        resolveObservationWaiter(waiterID, with: result)
    }

    private func observationWaitResult(
        for waiter: SemanticObservationWaiter,
        completedScope: SemanticObservationScope?
    ) -> SemanticObservationWaitResult? {
        switch observationStore.read(after: waiter.cursor, scope: waiter.scope) {
        case .entry(let entry):
            return .observation(entry)
        case .failure(let error):
            return .unavailable(error)
        case .pending:
            if waiter.completesAfterObservationCycle,
               let completedScope,
               completedScope.canFulfill(waiter.scope) {
                return .cycleCompleted
            }
            return nil
        }
    }

    private func resolveObservationWaiter(
        _ waiterID: UInt64,
        with result: SemanticObservationWaitResult
    ) {
        guard let waiter = observationWaiters.remove(id: waiterID) else { return }
        waiter.oneShot.resolve(returning: result)
    }

    private func armObservationDeadline(
        _ deadline: SemanticObservationDeadline?,
        waiterID: UInt64,
        oneShot: TimedOneShot<SemanticObservationWaitResult>
    ) {
        guard let deadline else { return }
        let remaining = deadline.remainingSeconds()
        guard remaining > 0 else {
            resolveObservationWaiter(waiterID, with: .deadlineReached)
            return
        }
        oneShot.armTimeout(after: .seconds(remaining)) { [weak self] in
            await self?.resolveObservationWaiter(waiterID, with: .deadlineReached)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
