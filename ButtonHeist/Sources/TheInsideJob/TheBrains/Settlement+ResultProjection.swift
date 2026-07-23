#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension Settlement {
    internal enum UnmatchedWaitDisposition: Sendable, Equatable {
        case failed
        case handledElse
    }

    internal enum ResultProjector {
        internal static func projectAction(_ result: Result) -> HeistActionEvidence {
            let dispatchResult = actionResult(from: result)
            guard result.evidence.command.predicate != nil,
                  !result.evidence.trigger.dispatchFailed,
                  let expectation = expectation(from: result) else {
                return .dispatch(dispatchResult: dispatchResult)
            }
            return .expectation(
                dispatchResult: dispatchResult,
                expectationResult: waitActionResult(from: result),
                expectation: expectation
            )
        }

        internal static func projectWait(
            _ result: Result,
            unmatched disposition: UnmatchedWaitDisposition = .failed
        ) -> HeistWaitEvidence {
            precondition(
                result.evidence.command.trigger == .observation,
                "Wait projection requires an observation settlement trigger"
            )
            guard let expectation = expectation(from: result) else {
                preconditionFailure("Wait projection requires evaluated predicate evidence")
            }
            let actionResult = waitActionResult(from: result)
            if result.outcome == .settled,
               let met = ExpectationResult.Met(expectation),
               let check = HeistWaitEvidence.MatchedCheck(
                   actionResult: actionResult,
                   expectation: met
               ) {
                return .matched(check, finalSummary: expectation.actual)
            }
            guard let check = HeistWaitEvidence.UnmatchedCheck(
                actionResult: actionResult,
                expectation: expectation
            ) else {
                preconditionFailure("Incomplete wait settlement requires unmatched public evidence")
            }
            switch disposition {
            case .failed:
                return .failed(check, finalSummary: expectation.actual)
            case .handledElse:
                return .handledElse(check, finalSummary: expectation.actual)
            }
        }
    }
}

private extension Settlement.ResultProjector {
    static func actionResult(from result: Settlement.Result) -> ActionResult {
        guard case .action(let command) = result.evidence.command.trigger else {
            preconditionFailure("Action projection requires an action settlement trigger")
        }
        let assemblyStart = RuntimeElapsed.now
        let observation = projectedObservation(from: result)
        switch result.evidence.trigger {
        case .actionDispatched(let dispatch):
            let payload = actionPayload(dispatch, result: result)
            let timing = actionTiming(
                dispatch: dispatch,
                result: result,
                assemblyStart: assemblyStart
            )
            switch dispatch.outcome {
            case .success:
                return ActionResult(
                    outcome: .success,
                    payload: payload,
                    message: dispatch.message,
                    observation: observation,
                    subjectEvidence: dispatch.subjectEvidence,
                    activationTrace: dispatch.activationTrace,
                    screenActionHandler: dispatch.screenActionHandler,
                    timing: timing
                )
            case .failure(let failure):
                return ActionResult(
                    outcome: .failure(TheBrains.actionFailureKind(for: failure)),
                    payload: dispatch.payload,
                    message: dispatch.message,
                    observation: observation,
                    subjectEvidence: dispatch.subjectEvidence,
                    activationTrace: dispatch.activationTrace,
                    timing: timing
                )
            }
        case .actionPending:
            let resultAssemblyMs = RuntimeElapsed.milliseconds(since: assemblyStart)
            return ActionResult.failure(
                payload: command.actionResultPayload,
                failureKind: .timeout,
                message: "action dispatch did not complete before settlement deadline "
                    + "after \(result.evidence.deadline.elapsed)ms",
                observation: observation,
                timing: ActionPerformanceTiming(
                    beforeObservationMs: result.evidence.timing.beforeObservationMs,
                    finalSemanticEvidenceMs: result.evidence.timing.finalSemanticEvidenceMs,
                    resultAssemblyMs: resultAssemblyMs,
                    totalMs: RuntimeElapsed.admit(
                        milliseconds: result.evidence.deadline.elapsed.milliseconds
                            + resultAssemblyMs.milliseconds
                    )
                )
            )
        case .observation:
            preconditionFailure("Action projection cannot consume observation trigger evidence")
        }
    }

    static func actionPayload(
        _ dispatch: TheSafecracker.ActionDispatchResult,
        result: Settlement.Result
    ) -> ActionResult.Payload {
        guard case .typeText = dispatch.payload,
              let resolvedElementId = dispatch.resolvedElementId,
              let handoff = result.evidence.handoff.event,
              let value = handoff.snapshot.observation.tree
                  .findElement(heistId: resolvedElementId)?
                  .element.value else {
            return dispatch.payload
        }
        return .typeText(value)
    }

    static func waitActionResult(from result: Settlement.Result) -> ActionResult {
        let projection = projectedEvidence(from: result)
        if result.outcome == .settled {
            let message: String? = switch result.evidence.command.trigger {
            case .observation:
                standaloneWaitSuccessMessage(from: result)
            case .action:
                expectation(from: result)?.actual
            }
            return ActionResult.success(
                payload: .wait,
                message: message,
                observation: projection.observation,
                timing: projection.timing
            )
        }
        return ActionResult.failure(
            payload: .wait,
            failureKind: waitFailureKind(for: result.outcome),
            message: waitFailureMessage(from: result),
            observation: projection.observation,
            timing: projection.timing
        )
    }

    static func standaloneWaitSuccessMessage(from result: Settlement.Result) -> String {
        guard case .observation = result.evidence.command.trigger,
              result.outcome == .settled,
              let predicate = result.evidence.command.predicate else {
            preconditionFailure("Successful standalone wait message requires a settled observation predicate")
        }
        let elapsed = String(
            format: "%.1f",
            Double(result.evidence.deadline.elapsed.milliseconds) / 1_000
        )
        if case .presence(.missing) = predicate.resolved.core {
            return "absent confirmed after \(elapsed)s"
        }
        return "matched after \(elapsed)s"
    }

    static func expectation(from result: Settlement.Result) -> ExpectationResult? {
        guard let predicate = result.evidence.command.predicate else { return nil }
        switch result.evidence.predicate.status {
        case .satisfied(let response), .unmet(let response):
            return response.result.expectation(for: predicate.authored)
        case .pending:
            return ExpectationResult(
                met: false,
                predicate: predicate.authored,
                actual: "deadline reached before predicate evaluation completed"
            )
        case .unavailable(let unavailable):
            return ExpectationResult(
                met: false,
                predicate: predicate.authored,
                actual: String(describing: unavailable)
            )
        case .notEvaluated:
            return nil
        case .notRequired:
            preconditionFailure("Predicate command cannot carry not-required evidence")
        }
    }

    static func projectedEvidence(
        from result: Settlement.Result
    ) -> (observation: ActionResultObservationEvidence, timing: ActionPerformanceTiming) {
        let timing = ActionPerformanceTiming(totalMs: result.evidence.deadline.elapsed)
        return (projectedObservation(from: result), timing)
    }

    static func projectedObservation(
        from result: Settlement.Result
    ) -> ActionResultObservationEvidence {
        let settlement = settlementEvidence(from: result)
        guard let traceEvidence = traceEvidence(from: result) else {
            return .none
        }
        return .settledTrace(traceEvidence, settlement)
    }

    static func actionTiming(
        dispatch: TheSafecracker.ActionDispatchResult,
        result: Settlement.Result,
        assemblyStart: RuntimeElapsed.Instant
    ) -> ActionPerformanceTiming {
        let resultAssemblyMs = RuntimeElapsed.milliseconds(since: assemblyStart)
        return ActionPerformanceTiming(
            beforeObservationMs: result.evidence.timing.beforeObservationMs,
            targetResolutionMs: dispatch.timing?.targetResolutionMs,
            actionDispatchMs: dispatch.timing?.actionDispatchMs,
            interactionMs: dispatch.timing?.interactionMs,
            finalSemanticEvidenceMs: result.evidence.timing.finalSemanticEvidenceMs,
            resultAssemblyMs: resultAssemblyMs,
            totalMs: RuntimeElapsed.admit(
                milliseconds: result.evidence.deadline.elapsed.milliseconds
                    + resultAssemblyMs.milliseconds
            )
        )
    }

    static func settlementEvidence(from result: Settlement.Result) -> ActionSettlementEvidence {
        let duration = result.evidence.deadline.elapsed
        guard case .established(let readiness) = result.evidence.readiness else {
            return .timedOut(duration: duration)
        }
        let path = readiness.path.actionSettlementPath
        guard let handoff = result.evidence.handoff.admission,
              handoff.belongs(to: readiness) else {
            return .observationHandoffTimedOut(duration: duration, path: path)
        }
        return .settled(duration: duration, path: path)
    }

    static func traceEvidence(from result: Settlement.Result) -> AccessibilityTraceEvidence? {
        var traces: [AccessibilityTrace] = []
        if case .established(let boundary) = result.evidence.boundary {
            traces.append(boundary.moment.snapshot.trace)
        }
        if case .events(let events)? = result.evidence.observationHistory {
            traces += events.compactMap { event in
                guard case .snapshot(let snapshot) = event else { return nil }
                return snapshot.trace
            }
        }
        if let handoff = result.evidence.handoff.event {
            traces.append(handoff.trace)
        }
        guard let trace = AccessibilityTrace.combinedTrace(from: traces) ?? traces.last else {
            return nil
        }
        let completeness: AccessibilityTraceEvidence.Completeness = result.evidence.handoff.admission == nil
            ? .incomplete
            : .complete
        return AccessibilityTraceEvidence(trace: trace, completeness: completeness)
    }

    static func waitFailureKind(for outcome: Settlement.Outcome) -> ActionFailure.Kind {
        switch outcome {
        case .timedOut:
            .timeout
        case .baselineUnavailable:
            .accessibilityTreeUnavailable
        case .dispatchFailed, .cancelled:
            .actionFailed
        case .settled:
            preconditionFailure("Settled wait has no failure kind")
        }
    }

    static func waitFailureMessage(from result: Settlement.Result) -> String {
        switch result.outcome {
        case .timedOut:
            renderTimeoutMessage(
                elapsed: result.evidence.deadline.elapsed,
                report: timeoutReport(from: result)
            )
        case .baselineUnavailable:
            TheBrains.treeUnavailableMessage
        case .dispatchFailed:
            "observation settlement cannot fail action dispatch"
        case .cancelled:
            "settlement cancelled after \(result.evidence.deadline.elapsed)ms"
        case .settled:
            preconditionFailure("Settled wait has no failure message")
        }
    }

    static func timeoutReport(
        from result: Settlement.Result
    ) -> PredicateWaitHistoricalDiagnostics.TimeoutReport? {
        guard let predicate = result.evidence.command.predicate else { return nil }
        var diagnostics = PredicateWaitHistoricalDiagnostics(
            target: predicate.resolved.waitTarget,
            predicate: predicate.authored
        )
        if let trace = traceEvidence(from: result)?.trace {
            diagnostics = diagnostics.recording(trace)
        }
        let predicateStatus: PredicateWaitHistoricalDiagnostics.TerminalPredicateStatus
        switch result.evidence.predicate.status {
        case .satisfied:
            predicateStatus = .satisfied
        case .unmet:
            predicateStatus = .unmet
        case .pending, .unavailable, .notEvaluated, .notRequired:
            predicateStatus = .unavailable
        }
        return diagnostics.timeoutReport(terminal: .init(
            predicateStatus: predicateStatus,
            readinessEstablished: result.evidence.readiness.isEstablished,
            handoffCompleted: result.evidence.handoff.admission != nil
        ))
    }

    static func renderTimeoutMessage(
        elapsed: ElapsedMilliseconds,
        report: PredicateWaitHistoricalDiagnostics.TimeoutReport?
    ) -> String {
        let headline = "settlement timed out after \(elapsed)ms"
        guard let report else { return headline }
        if report.predicateStatus == .satisfied {
            let incompleteAxis = switch report.incompleteAxis {
            case .readiness:
                "interface readiness did not complete"
            case .handoff:
                "settled observation handoff did not complete"
            case nil:
                "settlement completion evidence was unavailable"
            }
            return "\(headline); predicate was satisfied but \(incompleteAxis)"
        }

        var parts = [headline]
        if let presence = report.presence {
            let expectation: String
            let reason: String
            switch presence.expectation {
            case .appear:
                expectation = "element to appear"
                reason = "element not found"
            case .disappear:
                expectation = "element to disappear"
                reason = "element still present"
            }
            parts[0] += " waiting for \(expectation)"
            parts += [
                "expected: \(renderExpectedTarget(presence.target))",
                "interface: \(presence.interfaceElementCount) elements",
                "last result: \(reason)",
                "Next: get_interface() to inspect current elements, then retry wait with an exact predicate.",
            ]
        }
        parts += report.candidates.map {
            "observed accessibility candidate \($0.rendered(using: .predicateMismatchCandidate)) "
                + "did not match \(report.predicate.description)"
        }
        return parts.joined(separator: "; ")
    }

    static func renderExpectedTarget(_ target: ResolvedAccessibilityTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            return [
                TheVault.Diagnostics.formatMatcher(predicate),
                ordinal.map { "ordinal=\($0)" },
            ].compactMap { $0 }.joined(separator: " ")
        case .within(let container, let target):
            return "\(renderExpectedTarget(target)) within \(container)"
        case .container(let container, let ordinal):
            return [
                "container \(container)",
                ordinal.map { "ordinal=\($0)" },
            ].compactMap { $0 }.joined(separator: " ")
        }
    }
}

private extension Settlement.Readiness.Path {
    var actionSettlementPath: ActionSettlementPath {
        switch self {
        case .uikitIdle:
            .uikitIdle
        case .semanticStability:
            .semanticStability
        case .accessibilityQuietWindow:
            .accessibilityQuietWindow
        }
    }
}

extension ResolvedHeistActionCommand {
    internal var actionResultPayload: ActionResult.Payload {
        switch self {
        case .activate: .activate
        case .increment: .increment
        case .decrement: .decrement
        case .customAction: .customAction
        case .rotor: .rotor(nil)
        case .dismiss: .dismiss
        case .magicTap: .magicTap
        case .typeText: .typeText(nil)
        case .oneFingerTap: .oneFingerTap
        case .longPress: .longPress
        case .swipe: .swipe
        case .drag: .drag
        case .scroll: .scroll
        case .scrollToVisible: .scrollToVisible
        case .scrollToEdge: .scrollToEdge
        case .editAction: .editAction
        case .setPasteboard: .setPasteboard(nil)
        case .takeScreenshot: .screenshot(nil)
        case .dismissKeyboard: .dismissKeyboard
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
