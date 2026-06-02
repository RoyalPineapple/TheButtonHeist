#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct HeistSemanticObservation {
    let event: TheStash.SettledSemanticObservationEvent
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

@MainActor
enum InteractionObservationProjection {
    struct InitialTraceResult {
        let trace: AccessibilityTrace
        let summary: String?
        let expectation: ExpectationResult
        let shouldReturn: Bool
    }

    static func semanticObservation(
        event: TheStash.SettledSemanticObservationEvent,
        state: PostActionObservation.BeforeState
    ) -> HeistSemanticObservation {
        HeistSemanticObservation(
            event: event,
            state: state,
            accessibilityTrace: event.trace,
            delta: event.delta,
            summary: observationSummary(state)
        )
    }

    static func actionResult(
        method: ActionMethod,
        capture: AccessibilityTrace.Capture,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        success: Bool
    ) -> ActionResult {
        var builder = ActionResultBuilder(method: method, capture: capture)
        builder.message = message
        if let accessibilityTrace {
            builder.accessibilityTrace = accessibilityTrace
        }
        builder.settled = settled
        builder.settleTimeMs = settleTimeMs
        if success {
            return builder.success(payload: payload)
        }
        return builder.failure(errorKind: errorKind ?? .actionFailed, payload: payload)
    }

    static func failedActionResult(
        method: ActionMethod,
        capture: AccessibilityTrace.Capture,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind? = .actionFailed,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil
    ) -> ActionResult {
        actionResult(
            method: method,
            capture: capture,
            message: message,
            payload: payload,
            errorKind: errorKind,
            settled: settled,
            settleTimeMs: settleTimeMs,
            success: false
        )
    }

    static func initialTraceResult(
        for step: WaitStep,
        initialTrace: AccessibilityTrace?,
        timeout: Double
    ) -> InitialTraceResult? {
        guard let initialTrace else { return nil }
        let expectation = evaluate(step.predicate, in: initialTrace)
        return InitialTraceResult(
            trace: initialTrace,
            summary: traceSummary(initialTrace),
            expectation: expectation,
            shouldReturn: expectation.met || timeout == 0
        )
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        in observation: HeistSemanticObservation
    ) -> ExpectationResult {
        predicate.evaluate(
            currentElements: observation.state.interface.projectedElements,
            delta: observation.delta
        )
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        in trace: AccessibilityTrace
    ) -> ExpectationResult {
        predicate.evaluate(
            currentElements: trace.captures.last?.interface.projectedElements ?? [],
            delta: trace.endpointDeltaProjection
        )
    }

    static func traceSummary(_ trace: AccessibilityTrace) -> String? {
        guard let capture = trace.captures.last else { return nil }
        var parts = ["known: \(capture.interface.projectedElements.count) elements"]
        if let screenId = capture.context.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    static func observationSummary(_ state: PostActionObservation.BeforeState) -> String {
        var parts = ["known: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    static func transientElements(
        settleResult: SettleSession.Outcome,
        before: PostActionObservation.BeforeState,
        final: PostActionObservation.BeforeState,
        classification: ScreenClassifier.Classification
    ) -> [HeistElement] {
        guard !classification.isScreenChange,
              !settleResult.events.containsTripwireSignalChange else {
            return []
        }
        return SettleSession.transientElements(
            seenByKey: settleResult.elementsByKey,
            baseline: before.elements,
            final: final.elements
        ).map { TheStash.WireConversion.convert($0) }
    }

    static func waitReceipt(
        for step: WaitStep,
        observation: HeistSemanticObservation?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        presenceTimeoutMessage: String? = nil
    ) -> HeistWaitReceipt {
        waitReceipt(
            for: step,
            trace: observation?.accessibilityTrace,
            observationSummary: observation?.summary,
            expectation: expectation,
            elapsed: elapsed,
            success: success,
            presenceTimeoutMessage: presenceTimeoutMessage
        )
    }

    static func waitReceipt(
        for step: WaitStep,
        trace: AccessibilityTrace?,
        observationSummary: String?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        presenceTimeoutMessage: String? = nil
    ) -> HeistWaitReceipt {
        var builder = ActionResultBuilder(method: .wait)
        builder.accessibilityTrace = trace
        builder.message = success
            ? waitSuccessMessage(for: step.predicate, elapsed: elapsed)
            : waitTimeoutMessage(
                for: step,
                expectation: expectation,
                observationSummary: observationSummary,
                elapsed: elapsed,
                presenceTimeoutMessage: presenceTimeoutMessage
            )

        let actionResult = success
            ? builder.success()
            : builder.failure(errorKind: .timeout)
        return HeistWaitReceipt(actionResult: actionResult, expectation: expectation)
    }

    static func waitSuccessMessage(
        for predicate: AccessibilityPredicate,
        elapsed: String
    ) -> String {
        switch predicate {
        case .state(.present):
            return elapsed == "0.0" ? "matched immediately" : "matched after \(elapsed)s"
        case .state(.absent):
            return "absent confirmed after \(elapsed)s"
        default:
            return "predicate met after \(elapsed)s"
        }
    }

    static func waitTimeoutMessage(
        for step: WaitStep,
        expectation: ExpectationResult,
        observationSummary: String?,
        elapsed: String,
        presenceTimeoutMessage: String?
    ) -> String {
        guard let observationSummary else {
            return [
                "timed out after \(elapsed)s waiting for heist predicate",
                "expected: \(step.predicate.description)",
                "last result: \(expectation.actual ?? "not met")",
                "last observed: no settled semantic observation available",
            ].joined(separator: "; ")
        }

        if let presenceTimeoutMessage {
            return presenceTimeoutMessage
        }

        return [
            "timed out after \(elapsed)s waiting for heist predicate",
            "expected: \(step.predicate.description)",
            "last result: \(expectation.actual ?? "not met")",
            "last observed: \(observationSummary)",
        ].joined(separator: "; ")
    }

    static func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
