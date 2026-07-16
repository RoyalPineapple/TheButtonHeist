#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

@MainActor
extension SemanticObservationStream {
    internal func observationEntries(
        after cursor: ObservationCursor,
        scope: SemanticObservationScope
    ) -> ObservationEntrySequence {
        observationLog.entries(after: cursor, scope: scope)
    }

    internal func observationEntries(
        scope: SemanticObservationScope
    ) -> ObservationEntrySequence {
        observationLog.entries(scope: scope)
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
        let subscription = subscribe(scope: scope)
        defer { _ = subscription }

        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if timeout == 0 {
            guard isActive else { return nil }
            if scope == .discovery {
                let fulfillment = await cycles.waitForNextCycle(
                    scope: scope,
                    after: cycles.cursor()
                )
                guard let fulfillment else { return nil }
                if let event = fulfilledEvent(
                    fulfillment,
                    scope: scope,
                    after: requiredSequence
                ) {
                    return event
                }
            }
            return observationLog.cleanEvent(scope: scope, after: requiredSequence)
        }

        let requiresFreshVisibleObservation = sequence == nil && scope == .visible && isActive
        if !requiresFreshVisibleObservation,
           let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        if isActive {
            let fulfillment = await cycles.waitForNextCycle(
                scope: scope,
                after: cycles.cursor()
            )
            guard let fulfillment else { return nil }
            if let event = fulfilledEvent(
                fulfillment,
                scope: scope,
                after: requiredSequence
            ) {
                return event
            }
            if let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
                return latest
            }
        }

        return await waitForNextSettledEvent(scope: scope, after: requiredSequence, timeout: timeout)
    }

    internal func observationWindow(
        from baseline: SettledCapture,
        through currentEvent: SettledSemanticObservationEvent
    ) -> ObservationWindow? {
        let projectedCurrentEvent = observationLog.event(
            scope: baseline.cursor.scope,
            sequence: currentEvent.sequence
        ) ?? currentEvent
        guard let currentCursor = projectedCurrentEvent.cursor,
              let current = observationLog.event(at: currentCursor)?.settledCapture else { return nil }
        guard baseline.cursor.scope == current.cursor.scope else {
            return ObservationWindow.incomplete(
                baseline: baseline,
                current: current,
                retainedEntries: [],
                gap: ObservationGap(
                    reason: .scopeChanged,
                    baseline: baseline.cursor,
                    current: current.cursor
                )
            )
        }
        guard current.cursor.sequence > baseline.cursor.sequence else {
            return ObservationWindow.incomplete(
                baseline: baseline,
                current: current,
                retainedEntries: [],
                gap: ObservationGap(
                    reason: .noObservationAfterBaseline,
                    baseline: baseline.cursor,
                    current: current.cursor
                )
            )
        }

        let scopeEntries = observationLog.retainedEntries(scope: current.cursor.scope)
        let retainedEntries = scopeEntries.filter {
            $0.cursor.sequence > baseline.cursor.sequence
                && $0.cursor.sequence <= current.cursor.sequence
        }
        let baselineIsRetained = scopeEntries.contains { $0.cursor == baseline.cursor }
        let currentIsRetained = retainedEntries.last?.cursor == current.cursor
        let retainedLineageStartsAtBaseline = retainedEntries.first?.transition.previousCursor == baseline.cursor
        if currentIsRetained,
           baselineIsRetained || retainedLineageStartsAtBaseline {
            do {
                return try ObservationWindow(
                    baseline: baseline,
                    retainedEntries: retainedEntries
                )
            } catch {
                preconditionFailure("Observation log admitted discontinuous retained lineage: \(error)")
            }
        }

        let reason: ObservationGap.Reason = if let first = scopeEntries.first,
                                              baseline.cursor.sequence < first.cursor.sequence {
            .historyEvicted
        } else {
            .historyUnavailable
        }
        return ObservationWindow.incomplete(
            baseline: baseline,
            current: current,
            retainedEntries: retainedEntries,
            gap: ObservationGap(
                reason: reason,
                baseline: baseline.cursor,
                current: current.cursor
            )
        )
    }

    private func waitForNextSettledEvent(
        scope: SemanticObservationScope = .visible,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        let deadline = timeout.map {
            SemanticObservationDeadline(
                start: CFAbsoluteTimeGetCurrent(),
                timeoutSeconds: $0
            )
        }
        var cursor = observationLog.latestCursor(scope: scope)
        while true {
            let now = CFAbsoluteTimeGetCurrent()
            guard deadline?.hasTimeRemaining(at: now) != false else { return nil }
            guard let entry = await nextObservationEntry(
                scope: scope,
                after: cursor,
                timeout: deadline?.remainingSeconds(at: now)
            ) else { return nil }
            if let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
                return latest
            }
            cursor = entry.cursor
        }
    }

    private func nextObservationEntry(
        scope: SemanticObservationScope,
        after cursor: ObservationCursor?,
        timeout: Double?
    ) async -> ObservationEntry? {
        let sequence = if let cursor {
            observationLog.entries(after: cursor, scope: scope)
        } else {
            observationLog.entries(scope: scope)
        }
        return await withTaskGroup(of: ObservationEntry?.self) { group in
            group.addTask {
                var iterator = sequence.makeAsyncIterator()
                return try? await iterator.next()
            }
            if let timeoutDuration = Self.observationWaitTimeout(timeout) {
                group.addTask {
                    guard await Task.cancellableSleep(for: timeoutDuration) else { return nil }
                    return nil
                }
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func observationWaitTimeout(_ timeout: Double?) -> Duration? {
        guard let timeout else { return nil }
        guard timeout > 0 else { return .zero }
        let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
        return .nanoseconds(nanoseconds)
    }

    static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else { return SettleSession.defaultTimeoutMs }
        guard timeout > 0 else { return 0 }
        return max(1, Int((timeout * 1_000).rounded(.up)))
    }

    private func baselineSequence(
        for scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledObservationSequence? {
        if let sequence {
            return sequence
        }
        let currentSequence = latestEvent?.sequence
        if scope == .discovery {
            return currentSequence
        }
        if !isActive {
            return currentSequence
        }
        return nil
    }

    private func fulfilledEvent(
        _ fulfillment: SemanticObservationCycles.CycleFulfillment,
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        guard let settledSequence = fulfillment.settledSequence,
              settledSequence > (sequence ?? 0) else { return nil }
        return observationLog.event(scope: scope, sequence: settledSequence)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
