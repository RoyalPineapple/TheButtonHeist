#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    /// Install one wait predicate, then watch settled changes until a trace-derived expectation matches.
    func executeWaitForChange(timeout: TimeInterval, expectation: AccessibilityPredicate?) async -> ActionResult {
        startSemanticObservation()
        let start = CFAbsoluteTimeGetCurrent()

        guard let predicate = waitForChangeState.install(
            expectation: expectation,
            timeout: timeout,
            start: start
        ) else {
            var builder = ActionResultBuilder(method: .wait)
            builder.message = "wait already in progress"
            return builder.failure(errorKind: .actionFailed)
        }
        defer { waitForChangeState.finish() }

        let sentBaseline = waitForChangeState.lastDeliveredBaseline

        guard let initialObservation = await interactionObservation.observeSemanticState(
            scope: .visible,
            after: sentBaseline?.settledObservationSequence,
            timeout: min(max(timeout, 0), 1.0)
        ) else {
            return treeUnavailableResult(method: .wait)
        }
        let initial = initialObservation.state

        if let delta = initialObservation.delta {
            if let result = evaluateWaitForChange(
                delta: delta,
                accessibilityTrace: initialObservation.accessibilityTrace,
                afterSnapshot: initial.snapshot,
                expectation: predicate.expectation,
                start: start,
                round: 0,
                message: "already changed (0.0s)"
            ) {
                return result
            }
        }

        let streamResult = await waitForChangeThroughSettledSnapshots(
            after: initialObservation.event.sequence,
            predicate: predicate,
            start: start
        )
        if let result = streamResult.result {
            return result
        }

        // Timeout
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let current = await interactionObservation.observeSemanticState(
            scope: .visible,
            after: streamResult.lastObservation?.event.sequence ?? initialObservation.event.sequence,
            timeout: 0
        ) ?? streamResult.lastObservation ?? initialObservation
        let afterSnapshot = current.state.snapshot
        let delta = current.delta
        var builder = ActionResultBuilder(method: .wait)
        builder.message = waitForChangeTimeoutMessage(
            elapsed: elapsed,
            expectation: predicate.expectation,
            delta: delta,
            elementCount: afterSnapshot.count
        )
        builder.accessibilityTrace = current.accessibilityTrace
        return builder.failure(errorKind: .timeout)
    }

    private func waitForChangeThroughSettledSnapshots(
        after sequence: UInt64,
        predicate: WaitForChangeState.Predicate,
        start: CFAbsoluteTime
    ) async -> (result: ActionResult?, lastObservation: HeistSemanticObservation?) {
        var observedSequence = sequence
        var lastObservation: HeistSemanticObservation?
        var round = 0

        while CFAbsoluteTimeGetCurrent() < predicate.deadline {
            let remaining = predicate.deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }

            guard let observation = await interactionObservation.observeSemanticState(
                scope: .visible,
                after: observedSequence,
                timeout: min(remaining, 1.0)
            ) else { continue }
            round += 1
            observedSequence = observation.event.sequence
            lastObservation = observation

            guard let delta = observation.delta else { continue }
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

            if let result = evaluateWaitForChange(
                delta: delta,
                accessibilityTrace: observation.accessibilityTrace,
                afterSnapshot: observation.state.snapshot,
                expectation: predicate.expectation,
                start: start,
                round: round,
                message: "changed after \(elapsed)s (\(round) rounds)"
            ) {
                return (result, lastObservation)
            }

            insideJobLogger.debug("wait_for_change round \(round): \(Self.deltaKindDescription(delta)), expectation not yet met")
        }

        return (nil, lastObservation)
    }

    private func waitForChangeTimeoutMessage(
        elapsed: String,
        expectation: AccessibilityPredicate?,
        delta: AccessibilityTrace.Delta?,
        elementCount: Int
    ) -> String {
        let expected = expectation?.description ?? "any settled UI change"
        var parts = [
            "timed out after \(elapsed)s",
            "expected: \(expected)",
            "observed: \(delta.map(Self.deltaKindDescription) ?? "noTrace")",
            "known: \(elementCount) elements",
        ]
        if let screenId = stash.lastScreenId {
            parts.append("screen: \(screenId)")
        }
        if expectation == .changed(.screen()) {
            parts.append(
                "Next: retry wait with predicate: {\"type\": \"elements_changed\"} " +
                    "if element-level updates are acceptable, or call get_interface() " +
                    "to inspect the current screen."
            )
        } else {
            parts.append(
                "Next: get_interface() to inspect the current screen, " +
                    "then retry wait with the expected state."
            )
        }
        return parts.joined(separator: "; ")
    }

    private func evaluateWaitForChange(
        delta: AccessibilityTrace.Delta,
        accessibilityTrace: AccessibilityTrace?,
        afterSnapshot: [Screen.ScreenElement],
        expectation: AccessibilityPredicate?,
        start: CFAbsoluteTime,
        round: Int,
        message: String
    ) -> ActionResult? {
        var builder = ActionResultBuilder(method: .wait)
        builder.accessibilityTrace = accessibilityTrace

        guard let expectation else {
            builder.message = message
            return builder.success()
        }

        guard expectation.validate(
            against: builder.success()
        ).met else { return nil }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        builder.message = "expectation met after \(elapsed)s (\(round) rounds)"
        return builder.success()
    }

    private static func deltaKindDescription(_ delta: AccessibilityTrace.Delta) -> String {
        switch delta {
        case .noChange:
            return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged:
            return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged:
            return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
