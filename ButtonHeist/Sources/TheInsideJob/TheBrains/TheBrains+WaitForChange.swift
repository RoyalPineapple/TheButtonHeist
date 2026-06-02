#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    /// Install one wait predicate, then watch settled changes until a trace-derived expectation matches.
    func executeWaitForChange(timeout: TimeInterval, expectation: AccessibilityPredicate?) async -> ActionResult {
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

        guard let initial = await refreshSemanticSnapshot(baseline: sentBaseline) else {
            return treeUnavailableResult(method: .wait)
        }

        let baseline = sentBaseline ?? initial

        // Fast path: semantic state already changed since the last response.
        if let sentBaseline {
            let classification = ScreenClassifier.classify(
                before: sentBaseline.screenSnapshot,
                after: initial.screenSnapshot
            )
            if PostActionObservation.shouldRecordAccessibilityTrace(
                baseline: sentBaseline,
                current: initial,
                classification: classification
            ) {
                let accessibilityTrace = postActionObservation.makeClassifiedAccessibilityTrace(after: initial, parent: baseline)
                if let delta = accessibilityTrace.endpointDeltaProjection {
                    if let result = evaluateWaitForChange(
                        delta: delta,
                        accessibilityTrace: accessibilityTrace,
                        afterSnapshot: initial.snapshot,
                        expectation: predicate.expectation,
                        start: start,
                        round: 0,
                        message: "already changed (0.0s)"
                    ) {
                        return result
                    }
                }
            }
        }

        if let result = await waitForChangeThroughSettledSnapshots(
            baseline: baseline,
            initial: initial,
            predicate: predicate,
            start: start
        ) {
            return result
        }

        // Timeout
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let current = await refreshSemanticSnapshot(baseline: baseline)
        let afterSnapshot = current?.snapshot ?? []
        let timeoutAccessibilityTrace = current.map {
            postActionObservation.makeClassifiedAccessibilityTrace(after: $0, parent: baseline)
        }
        let delta = timeoutAccessibilityTrace?.endpointDeltaProjection
        var builder = ActionResultBuilder(method: .wait)
        builder.message = waitForChangeTimeoutMessage(
            elapsed: elapsed,
            expectation: predicate.expectation,
            delta: delta,
            elementCount: afterSnapshot.count
        )
        builder.accessibilityTrace = timeoutAccessibilityTrace
        return builder.failure(errorKind: .timeout)
    }

    private func waitForChangeThroughSettledSnapshots(
        baseline: PostActionObservation.BeforeState,
        initial: PostActionObservation.BeforeState,
        predicate: WaitForChangeState.Predicate,
        start: CFAbsoluteTime
    ) async -> ActionResult? {
        // Wait for stable AX-tree observations until a change lands or we time
        // out. Tripwire signals reset the settle baseline inside
        // `SettleSession`; the parsed AX captures below still decide whether
        // anything changed.
        var settleBaseline = initial
        var round = 0

        while CFAbsoluteTimeGetCurrent() < predicate.deadline {
            let remaining = predicate.deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }

            guard let current = await waitForSettledSemanticSnapshot(
                baseline: settleBaseline,
                timeout: min(remaining, 1.0)
            ) else { continue }
            round += 1

            let classification = ScreenClassifier.classify(
                before: settleBaseline.screenSnapshot,
                after: current.screenSnapshot
            )
            guard PostActionObservation.shouldRecordAccessibilityTrace(
                baseline: settleBaseline,
                current: current,
                classification: classification
            ) else {
                settleBaseline = current
                continue
            }

            let accessibilityTrace = postActionObservation.makeClassifiedAccessibilityTrace(after: current, parent: baseline)
            guard let delta = accessibilityTrace.endpointDeltaProjection else {
                settleBaseline = current
                continue
            }
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

            if let result = evaluateWaitForChange(
                delta: delta,
                accessibilityTrace: accessibilityTrace,
                afterSnapshot: current.snapshot,
                expectation: predicate.expectation,
                start: start,
                round: round,
                message: "changed after \(elapsed)s (\(round) rounds)"
            ) {
                return result
            }

            settleBaseline = current
            insideJobLogger.debug("wait_for_change round \(round): \(Self.deltaKindDescription(delta)), expectation not yet met")
        }

        return nil
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

    private func refreshSemanticSnapshot(
        baseline: PostActionObservation.BeforeState? = nil
    ) async -> PostActionObservation.BeforeState? {
        guard stash.commitVisibleObservation() != nil else { return nil }
        if let baseline {
            return await postActionObservation.semanticStateAfterVisibleRefresh(baseline: baseline)
        }
        return postActionObservation.captureSemanticState()
    }

    private func waitForSettledSemanticSnapshot(
        baseline: PostActionObservation.BeforeState,
        timeout: TimeInterval
    ) async -> PostActionObservation.BeforeState? {
        let timeoutMs = max(1, Int(timeout * 1000))
        let settleSession = SettleSession.live(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: timeoutMs
        )
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baseline.tripwireSignal
        )
        guard settle.outcome.didSettleCleanly, let screen = settle.finalScreen else { return nil }
        stash.commitSettledVisibleObservation(screen)
        return await postActionObservation.semanticStateAfterVisibleRefresh(baseline: baseline)
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
