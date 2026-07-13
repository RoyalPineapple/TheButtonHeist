#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport
import TheScore

@MainActor
final class SemanticObservationSettledWaiters {
    private struct WaiterKey: Hashable, Sendable {
        let id: UInt64
        let scope: SemanticObservationScope
        let afterSequence: SettledObservationSequence?
    }

    private var nextWaiterID: UInt64 = 0
    private var waiters = WaiterStore<WaiterKey, TimedOneShot<SettledSemanticObservationEvent?>>()

    var count: Int {
        waiters.count
    }

    func wait(
        scope: SemanticObservationScope,
        afterSequence: SettledObservationSequence?,
        timeout: Double?,
        onRegistered: @MainActor () -> Void = {},
        currentEvent: @MainActor () -> SettledSemanticObservationEvent?
    ) async -> SettledSemanticObservationEvent? {
        let key = reserveWaiterKey(scope: scope, afterSequence: afterSequence)
        let oneShot = TimedOneShot<SettledSemanticObservationEvent?>()

        return await oneShot.wait(
            cancellationValue: nil,
            onRegistered: { oneShot in
                waiters.insert(oneShot, for: key)
                onRegistered()
                if let event = currentEvent(), canFulfill(key, with: event) {
                    complete(key, returning: event)
                }
                if let timeoutDuration = observationWaitTimeout(timeout) {
                    oneShot.armTimeout(after: timeoutDuration) { [weak self] in
                        await self?.complete(key, returning: nil)
                    }
                }
            },
            onFinished: {
                complete(key, returning: nil)
            }
        )
    }

    func cancelAll() {
        for waiter in waiters.removeAll() {
            waiter.resolve(returning: nil)
        }
    }

    func completeWaiters(with events: [SettledSemanticObservationEvent]) {
        for event in events {
            let completed = waiters.removeAll { key in
                canFulfill(key, with: event)
            }
            for removal in completed {
                removal.waiter.resolve(returning: event)
            }
        }
    }

    private func complete(_ key: WaiterKey, returning event: SettledSemanticObservationEvent?) {
        waiters.resolve(key, returning: event)
    }

    private func canFulfill(_ key: WaiterKey, with event: SettledSemanticObservationEvent) -> Bool {
        event.scope == key.scope && event.sequence > (key.afterSequence ?? 0)
    }

    private func reserveWaiterKey(
        scope: SemanticObservationScope,
        afterSequence: SettledObservationSequence?
    ) -> WaiterKey {
        defer { nextWaiterID &+= 1 }
        return WaiterKey(id: nextWaiterID, scope: scope, afterSequence: afterSequence)
    }

    private func observationWaitTimeout(_ timeout: Double?) -> Duration? {
        guard let timeout else { return nil }
        guard timeout > 0 else { return nil }
        let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
        return .nanoseconds(nanoseconds)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
