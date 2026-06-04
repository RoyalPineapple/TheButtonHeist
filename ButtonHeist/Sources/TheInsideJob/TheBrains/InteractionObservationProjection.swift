#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct HeistSemanticObservation {
    let event: SettledSemanticObservationEvent
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

enum SemanticObservationTiming {
    static let defaultTimeout: Double = 1
}

@MainActor enum InteractionObservationProjection { // swiftlint:disable:this agent_main_actor_value_type
    struct InitialTraceResult {
        let trace: AccessibilityTrace
        let summary: String?
        let expectation: ExpectationResult
        let shouldReturn: Bool
    }

    struct SettledEventSummary {
        let sequence: UInt64
        let hash: String?

        init(event: SettledSemanticObservationEvent) {
            sequence = event.sequence
            hash = event.currentCaptureRef?.hash
        }

        var description: String {
            if let hash {
                return "sequence \(sequence), hash \(hash)"
            }
            return "sequence \(sequence), hash unavailable"
        }
    }

    struct SettledWaitDiagnostics {
        let baseline: SettledEventSummary?
        let last: SettledEventSummary?
        let lastDelta: AccessibilityTrace.Delta?
        let sawFutureObservation: Bool
    }

    struct PostActionResultInput {
        let success: Bool
        let method: ActionMethod
        let message: String?
        let payload: ResultPayload?
        let afterStatePayload: ((PostActionObservation.BeforeState) -> ResultPayload?)?
        let errorKind: ErrorKind?
        let subjectEvidence: ActionSubjectEvidence?
        let before: PostActionObservation.BeforeState
        let settleEvidence: PostActionObservation.SettleEvidence
        let finalEvidence: PostActionObservation.FinalEvidence?
    }

    nonisolated static func clampedWaitTimeout(_ timeout: Double) -> Double {
        max(0, min(timeout, 30))
    }

    static func unresolvedWaitPredicate() -> AccessibilityPredicate {
        AccessibilityPredicate.state(.absent(ElementPredicate(identifier: "__unresolved_heist_predicate__")))
    }

    static func semanticObservation(
        event: SettledSemanticObservationEvent,
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
        subjectEvidence: ActionSubjectEvidence? = nil,
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
        builder.subjectEvidence = subjectEvidence
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
        subjectEvidence: ActionSubjectEvidence? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil
    ) -> ActionResult {
        actionResult(
            method: method,
            capture: capture,
            message: message,
            payload: payload,
            errorKind: errorKind,
            subjectEvidence: subjectEvidence,
            settled: settled,
            settleTimeMs: settleTimeMs,
            success: false
        )
    }

    static func postActionResult(_ input: PostActionResultInput) -> ActionResult {
        if let cancelled = cancelledActionResult(
            method: input.method,
            payload: input.payload,
            subjectEvidence: input.subjectEvidence,
            before: input.before,
            settleEvidence: input.settleEvidence
        ) {
            return cancelled
        }

        guard let finalEvidence = input.finalEvidence else {
            return postActionParseFailureResult(
                method: input.method,
                payload: input.payload,
                subjectEvidence: input.subjectEvidence,
                before: input.before,
                settleEvidence: input.settleEvidence
            )
        }

        let resolvedPayload = input.success
            ? (input.afterStatePayload?(finalEvidence.state) ?? input.payload)
            : input.payload

        guard finalEvidence.capture != nil else {
            return failedActionResult(
                method: input.method,
                capture: input.before.capture,
                message: input.message,
                payload: resolvedPayload,
                subjectEvidence: input.subjectEvidence
            )
        }

        return actionResult(
            method: input.method,
            capture: finalEvidence.capture ?? finalEvidence.state.capture,
            message: input.message,
            payload: resolvedPayload,
            errorKind: input.errorKind,
            accessibilityTrace: finalEvidence.trace,
            subjectEvidence: input.subjectEvidence,
            settled: input.settleEvidence.didSettleCleanly,
            settleTimeMs: input.settleEvidence.timeMs,
            success: input.success
        )
    }

    static func initialTraceResult(
        for step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace?,
        timeout: Double
    ) -> InitialTraceResult? {
        guard let initialTrace else { return nil }
        let expectation = PredicateEvaluation.evaluate(step.predicate, in: initialTrace)
        return InitialTraceResult(
            trace: initialTrace,
            summary: traceSummary(initialTrace),
            expectation: expectation,
            shouldReturn: expectation.met || timeout == 0
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
        for step: ResolvedWaitStep,
        trace: AccessibilityTrace?,
        observationSummary: String?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        presenceTimeoutMessage: String? = nil,
        settledDiagnostics: SettledWaitDiagnostics? = nil
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
                presenceTimeoutMessage: presenceTimeoutMessage,
                settledDiagnostics: settledDiagnostics
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
        for step: ResolvedWaitStep,
        expectation: ExpectationResult,
        observationSummary: String?,
        elapsed: String,
        presenceTimeoutMessage: String?,
        settledDiagnostics: SettledWaitDiagnostics?
    ) -> String {
        let diagnostics = settledDiagnostics.map(settledDiagnosticsMessage) ?? []
        guard let observationSummary else {
            return ([
                "timed out after \(elapsed)s waiting for heist predicate",
                "expected: \(step.predicate.description)",
                "last result: \(expectation.actual ?? "not met")",
                "last observed: no settled semantic observation available",
            ] + diagnostics).joined(separator: "; ")
        }

        if let presenceTimeoutMessage {
            return ([presenceTimeoutMessage] + diagnostics).joined(separator: "; ")
        }

        return ([
            "timed out after \(elapsed)s waiting for heist predicate",
            "expected: \(step.predicate.description)",
            "last result: \(expectation.actual ?? "not met")",
            "last observed: \(observationSummary)",
        ] + diagnostics).joined(separator: "; ")
    }

    static func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }

    private static func settledDiagnosticsMessage(_ diagnostics: SettledWaitDiagnostics) -> [String] {
        var parts: [String] = []
        if let baseline = diagnostics.baseline {
            parts.append("baseline: \(baseline.description)")
        }
        if let last = diagnostics.last {
            parts.append("last settled: \(last.description)")
        }
        parts.append("last delta: \(deltaSummary(diagnostics.lastDelta))")
        if diagnostics.baseline != nil, !diagnostics.sawFutureObservation {
            parts.append("no future settled observation arrived after baseline")
        }
        return parts
    }

    private static func deltaSummary(_ delta: AccessibilityTrace.Delta?) -> String {
        guard let delta else { return "none" }
        switch delta {
        case .noChange:
            return "no_change"
        case .elementsChanged:
            return "elements_changed"
        case .screenChanged:
            return "screen_changed"
        }
    }

    private static func cancelledActionResult(
        method: ActionMethod,
        payload: ResultPayload?,
        subjectEvidence: ActionSubjectEvidence?,
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionObservation.SettleEvidence
    ) -> ActionResult? {
        guard case .cancelled(let cancelMs) = settleEvidence.outcome.outcome else { return nil }
        return failedActionResult(
            method: method,
            capture: before.capture,
            message: "cancelled after \(cancelMs)ms",
            payload: payload,
            subjectEvidence: subjectEvidence,
            settled: false,
            settleTimeMs: cancelMs
        )
    }

    private static func postActionParseFailureResult(
        method: ActionMethod,
        payload: ResultPayload?,
        subjectEvidence: ActionSubjectEvidence?,
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionObservation.SettleEvidence
    ) -> ActionResult {
        failedActionResult(
            method: method,
            capture: before.capture,
            message: "Could not parse post-action accessibility tree",
            payload: payload,
            subjectEvidence: subjectEvidence,
            settled: settleEvidence.didSettleCleanly,
            settleTimeMs: settleEvidence.timeMs
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
