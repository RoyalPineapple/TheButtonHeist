#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

internal enum SemanticObservationWaitResult: Sendable, Equatable {
    case observation(ObservationEntry)
    case deadlineReached
    case cancelled
    case unavailable(ObservationLogReadError)
}

internal struct SemanticObservationWaiter: Sendable {
    let cursor: ObservationCursor?
    let scope: SemanticObservationScope
    let oneShot: TimedOneShot<SemanticObservationWaitResult>
}

@MainActor
extension SemanticObservationStream {
    internal func waitForObservation(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope,
        deadline: SemanticObservationDeadline?
    ) async -> SemanticObservationWaitResult {
        switch observationLog.read(after: cursor, scope: scope) {
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

        let waiterID = reserveObservationWaiterID()
        let oneShot = TimedOneShot<SemanticObservationWaitResult>()
        let subscription = subscribe(scope: scope)
        defer { _ = subscription }

        return await oneShot.wait(
            cancellationValue: .cancelled,
            onRegistered: { oneShot in
                observationWaiters[waiterID] = SemanticObservationWaiter(
                    cursor: cursor,
                    scope: scope,
                    oneShot: oneShot
                )
                resolveObservationWaiterIfAvailable(waiterID)
                armObservationDeadline(deadline, waiterID: waiterID, oneShot: oneShot)
            },
            onFinished: {
                observationWaiters.removeValue(forKey: waiterID)?.oneShot.cancelTimeout()
            }
        )
    }

    internal func latestObservationCursor(
        scope: SemanticObservationScope
    ) -> ObservationCursor? {
        observationLog.latestCursor(scope: scope)
    }

    internal func retainedObservationEntries(
        scope: SemanticObservationScope
    ) -> [ObservationEntry] {
        observationLog.retainedEntries(scope: scope)
    }

    internal func settledCapture(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledCapture? {
        observationLog.settledCapture(scope: scope, at: sequence)
    }

    internal func observationEvent(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledSemanticObservationEvent? {
        observationLog.event(scope: scope, sequence: sequence)
    }

    internal func settledEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        invalidateSettledObservationIfScreenChangedSinceCommit()
        let requiredSequence = baselineSequence(for: scope, after: sequence)
        if timeout == 0 {
            guard isActive else { return nil }
            if scope != .discovery {
                return observationLog.cleanEvent(scope: scope, after: requiredSequence)
            }
        }
        let requiresFreshVisibleObservation = sequence == nil && scope == .visible && isActive

        if !requiresFreshVisibleObservation,
           let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        let deadline = timeout == 0 ? nil : timeout.map {
            SemanticObservationDeadline(
                start: CFAbsoluteTimeGetCurrent(),
                timeoutSeconds: $0
            )
        }
        var cursor = observationLog.latestCursor(scope: scope)
        while true {
            switch await waitForObservation(
                after: cursor,
                scope: scope,
                deadline: deadline
            ) {
            case .observation(let entry):
                cursor = entry.cursor
                if let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
                    return latest
                }
            case .deadlineReached, .cancelled, .unavailable:
                return nil
            }
        }
    }

    internal func observationWindow(
        from baseline: SettledCapture,
        through currentEvent: SettledSemanticObservationEvent
    ) -> ObservationWindow? {
        observationLog.observationWindow(from: baseline, through: currentEvent)
    }

    static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else { return SettleSession.defaultTimeoutMs }
        guard timeout > 0 else { return 0 }
        let milliseconds = (timeout * 1_000).rounded(.up)
        return milliseconds >= Double(Int.max) ? Int.max : max(1, Int(milliseconds))
    }

    func completeObservationWaiters() {
        for waiterID in observationWaiters.keys.sorted() {
            resolveObservationWaiterIfAvailable(waiterID)
        }
    }

    func cancelObservationWaiters() {
        for waiterID in observationWaiters.keys.sorted() {
            resolveObservationWaiter(waiterID, with: .cancelled)
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

    private func reserveObservationWaiterID() -> UInt64 {
        defer { nextObservationWaiterID &+= 1 }
        return nextObservationWaiterID
    }

    private func resolveObservationWaiterIfAvailable(_ waiterID: UInt64) {
        guard let waiter = observationWaiters[waiterID] else { return }
        switch observationLog.read(after: waiter.cursor, scope: waiter.scope) {
        case .entry(let entry):
            resolveObservationWaiter(waiterID, with: .observation(entry))
        case .failure(let error):
            resolveObservationWaiter(waiterID, with: .unavailable(error))
        case .pending:
            break
        }
    }

    private func resolveObservationWaiter(
        _ waiterID: UInt64,
        with result: SemanticObservationWaitResult
    ) {
        guard let waiter = observationWaiters.removeValue(forKey: waiterID) else { return }
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
