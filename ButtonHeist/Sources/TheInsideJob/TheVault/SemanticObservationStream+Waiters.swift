#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

internal enum SemanticObservationWaitResult: Sendable, Equatable {
    case observation(Observation.SnapshotEvent)
    case cycleCompleted
    case deadlineReached
    case cancelled
    case unavailable(Observation.LogReadError)
}

internal struct SemanticObservationWaiter: Sendable {
    let moment: Observation.Moment?
    let scope: SemanticObservationScope
    let completesAfterObservationCycle: Bool
    let oneShot: TimedOneShot<SemanticObservationWaitResult>
}

@MainActor
internal final class ObservationReplayRelay {
    private enum Phase {
        case buffering([Observation.Event])
        case live
    }

    private let receiveEvent: (Observation.Event) -> Void
    private let receiveUnavailable: (Observation.EventsSince) -> Void
    private var phase = Phase.buffering([])

    internal init(
        receiveEvent: @escaping (Observation.Event) -> Void,
        receiveUnavailable: @escaping (Observation.EventsSince) -> Void
    ) {
        self.receiveEvent = receiveEvent
        self.receiveUnavailable = receiveUnavailable
    }

    internal func receive(_ event: Observation.Event) {
        switch phase {
        case .buffering(var events):
            events.append(event)
            phase = .buffering(events)
        case .live:
            receiveEvent(event)
        }
    }

    internal func replay(_ history: Observation.EventsSince) {
        let buffered: [Observation.Event]
        switch phase {
        case .buffering(let events):
            buffered = events
        case .live:
            preconditionFailure("Observation history may be replayed only once")
        }
        phase = .live

        let replayedEvents: [Observation.Event]
        switch history {
        case .events(let events):
            replayedEvents = events
            events.forEach(receiveEvent)
        case .expired, .unavailable:
            replayedEvents = []
            receiveUnavailable(history)
        }
        buffered.lazy
            .filter { !replayedEvents.contains($0) }
            .forEach(receiveEvent)
    }
}

@MainActor
extension Observation.Stream {
    internal func events(
        since moment: Observation.Moment,
        scope: SemanticObservationScope
    ) async -> Observation.EventsSince {
        await storeOwner.readLog {
            $0.events(since: moment).projected(for: scope)
        }
    }

    internal func subscribe(
        scope: SemanticObservationScope,
        replayingAfter moment: Observation.Moment,
        receive: @escaping @MainActor (Observation.Event) -> Void,
        historyUnavailable: @escaping @MainActor (Observation.EventsSince) -> Void
    ) async -> SemanticObservationSubscription {
        let relay = ObservationReplayRelay(
            receiveEvent: receive,
            receiveUnavailable: historyUnavailable
        )
        let subscription = subscribe(scope: scope, receive: relay.receive)
        relay.replay(await events(since: moment, scope: scope))
        return subscription
    }

    internal func waitForObservation(
        since moment: Observation.Moment?,
        scope: SemanticObservationScope,
        deadline: SemanticObservationDeadline?,
        completingAfterCurrentCycle: Bool = false
    ) async -> SemanticObservationWaitResult {
        if Task.isCancelled {
            return .cancelled
        }
        if let deadline,
           !deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
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
                    moment: moment,
                    scope: scope,
                    completesAfterObservationCycle: completingAfterCurrentCycle,
                    oneShot: oneShot
                ), id: waiterID)
                Task { @MainActor in
                    await resolveObservationWaiterIfAvailable(waiterID)
                }
                armObservationDeadline(deadline, waiterID: waiterID, oneShot: oneShot)
            },
            onFinished: {
                observationWaiters.remove(id: waiterID)?.oneShot.cancelTimeout()
            }
        )
    }

    internal func latestCommittedObservationMoment(
        scope: SemanticObservationScope
    ) async -> Observation.Moment? {
        await storeOwner.latestMoment(scope: scope)
    }

    internal func settledEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> Observation.SnapshotEvent? {
        let baseline = await storeOwner.settledWaitBaseline(scope: scope, after: sequence)
        let requiredSequence = baseline.requiredSequence
        if timeout == 0 {
            guard isActive else { return nil }
            if scope != .discovery {
                return await admittedObservation(scope: scope, after: requiredSequence)?.event
            }
        }
        let deadline = timeout == 0 ? nil : timeout.map {
            SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeoutSeconds: $0
            )
        }
        var moment = baseline.moment
        while true {
            switch await waitForObservation(
                since: moment,
                scope: scope,
                deadline: deadline,
                completingAfterCurrentCycle: timeout == 0 && scope == .discovery
            ) {
            case .observation(let event):
                moment = event.moment
                if let latest = await admittedObservation(scope: scope, after: requiredSequence)?.event {
                    return latest
                }
            case .cycleCompleted:
                return await admittedObservation(scope: scope, after: requiredSequence)?.event
            case .deadlineReached, .cancelled, .unavailable:
                return nil
            }
        }
    }

    static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else { return SettleSession.defaultTimeoutMs }
        guard timeout > 0 else { return 0 }
        let milliseconds = (timeout * 1_000).rounded(.up)
        return milliseconds >= Double(Int.max) ? Int.max : max(1, Int(milliseconds))
    }

    func completeObservationWaiters(
        completedScope: SemanticObservationScope? = nil
    ) async {
        var candidates: [(UInt64, SemanticObservationWaiter)] = []
        observationWaiters.updateAll { id, waiter in
            candidates.append((id, waiter))
        }
        for (id, waiter) in candidates {
            guard let result = await observationWaitResult(
                for: waiter,
                completedScope: completedScope
            ) else { continue }
            resolveObservationWaiter(id, with: result)
        }
    }

    func cancelObservationWaiters() {
        for waiter in observationWaiters.removeAll() {
            waiter.oneShot.resolve(returning: .cancelled)
        }
    }

    private func resolveObservationWaiterIfAvailable(
        _ waiterID: UInt64,
        completedScope: SemanticObservationScope? = nil
    ) async {
        guard let waiter = observationWaiters[waiterID],
              let result = await observationWaitResult(
            for: waiter,
            completedScope: completedScope
        ) else { return }
        resolveObservationWaiter(waiterID, with: result)
    }

    private func observationWaitResult(
        for waiter: SemanticObservationWaiter,
        completedScope: SemanticObservationScope?
    ) async -> SemanticObservationWaitResult? {
        switch await storeOwner.readSnapshot(since: waiter.moment, scope: waiter.scope) {
        case .event(let event):
            return .observation(event)
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
