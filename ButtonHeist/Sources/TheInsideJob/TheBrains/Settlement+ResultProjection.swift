#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension Settlement {
    internal enum ResultProjector {
        internal static func projectAction(_ result: Result) -> HeistActionEvidence {
            guard case .action(let action) = result else {
                preconditionFailure("Action projection requires an action settlement result")
            }
            switch action {
            case .settled(let settled):
                return .completed(
                    result: actionResult(settled),
                    expectation: settled.evaluation.map {
                        $0.result.expectation(for: settled.command.predicate?.authored)
                    }
                )
            case .failed(let failed):
                return .completed(
                    result: actionResult(failed),
                    expectation: actionExpectation(failed)
                )
            }
        }

        internal static func projectWait(_ result: Result) -> HeistSettlementEvidence {
            guard case .observation(let observation) = result else {
                preconditionFailure("Wait projection requires an observation settlement result")
            }
            switch observation {
            case .settled(let settled):
                let expectation = settled.evaluation.result.expectation(
                    for: settled.predicate.authored
                )
                guard let met = ExpectationResult.Met(expectation),
                      let check = HeistSettlementEvidence.MatchedCheck(
                          actionResult: waitActionResult(settled),
                          expectation: met
                      ) else {
                    preconditionFailure("Settled observation requires matched public evidence")
                }
                return .matched(
                    check,
                    baselineSummary: settled.boundary.moment.capture.summary,
                    finalSummary: expectation.actual
                )
            case .failed(let failed):
                let expectation = expectation(
                    predicate: failed.attempt.predicate,
                    evidence: failed.attempt.evaluation
                )
                guard let check = HeistSettlementEvidence.UnmatchedCheck(
                    actionResult: waitActionResult(failed),
                    expectation: expectation
                ) else {
                    preconditionFailure("Failed observation requires unmatched public evidence")
                }
                return .failed(
                    check,
                    baselineSummary: baselineSummary(failed.attempt.boundary),
                    finalSummary: expectation.actual
                )
            }
        }
    }
}

private extension Settlement.ResultProjector {
    static func actionResult(
        _ settled: Settlement.Result.SettledAction
    ) -> ActionResult {
        actionResult(
            dispatch: settled.dispatch,
            outcome: .success,
            message: settled.dispatch.message,
            boundary: .established(settled.boundary),
            history: settled.history,
            handoff: .admitted(settled.handoff),
            readiness: .established(settled.readiness),
            timing: settled.timing
        )
    }

    static func actionResult(
        _ failed: Settlement.Result.FailedAction
    ) -> ActionResult {
        let assemblyStart = RuntimeElapsed.now
        let attempt = failed.attempt
        let failure: (kind: ActionFailure.Kind, message: String) = switch failed.reason {
        case .dispatchFailed:
            if case .completed(let dispatch) = attempt.dispatch {
                (.actionFailed, dispatch.message ?? "action dispatch failed")
            } else {
                preconditionFailure("Dispatch failure requires completed dispatch evidence")
            }
        case .baselineUnavailable:
            (.accessibilityTreeUnavailable, TheBrains.treeUnavailableMessage)
        case .timedOut:
            if case .captureFailed = attempt.handoff {
                (.actionFailed, "Could not capture accessibility tree after action")
            } else if let predicate = attempt.command.predicate {
                (
                    .timeout,
                    renderTimeoutMessage(
                        predicate: predicate,
                        evidence: attempt.evaluation,
                        boundary: attempt.boundary,
                        readiness: attempt.readiness,
                        handoff: attempt.handoff,
                        history: attempt.history,
                        elapsed: attempt.timing.elapsed
                    )
                )
            } else {
                (
                    .timeout,
                    "action dispatch did not complete before settlement deadline "
                        + "after \(attempt.timing.elapsed)ms"
                )
            }
        case .cancelled:
            (.actionFailed, "cancelled after \(attempt.timing.elapsed)ms")
        case .viewportExitFailed:
            (.actionFailed, viewportExitFailureMessage)
        }
        switch attempt.dispatch {
        case .pending:
            let assembly = RuntimeElapsed.milliseconds(since: assemblyStart)
            return ActionResult.failure(
                payload: attempt.command.command.actionResultPayload,
                failureKind: failure.kind,
                message: failure.message,
                observation: projectedObservation(
                    boundary: attempt.boundary,
                    history: attempt.history,
                    handoff: attempt.handoff,
                    readiness: attempt.readiness,
                    duration: attempt.timing.elapsed
                ),
                timing: ActionPerformanceTiming(
                    beforeObservationMs: attempt.timing.execution.beforeObservationMs,
                    finalSemanticEvidenceMs: attempt.timing.execution.finalSemanticEvidenceMs,
                    resultAssemblyMs: assembly,
                    totalMs: RuntimeElapsed.admit(
                        milliseconds: attempt.timing.elapsed.milliseconds + assembly.milliseconds
                    )
                )
            )
        case .completed(let dispatch):
            let outcome: ActionResultOutcome
            let message: String?
            switch dispatch.outcome {
            case .failure(let kind):
                outcome = .failure(TheBrains.actionFailureKind(for: kind))
                message = dispatch.message
            case .success:
                outcome = .failure(failure.kind)
                message = failure.message
            }
            return actionResult(
                dispatch: dispatch,
                outcome: outcome,
                message: message,
                boundary: attempt.boundary,
                history: attempt.history,
                handoff: attempt.handoff,
                readiness: attempt.readiness,
                timing: attempt.timing
            )
        }
    }

    static func actionResult(
        dispatch: TheSafecracker.ActionDispatchResult,
        outcome: ActionResultOutcome,
        message: String?,
        boundary: Settlement.BoundaryEvidence,
        history: Observation.EventsSince?,
        handoff: Settlement.Handoff.Evidence,
        readiness: Settlement.Readiness.Evidence,
        timing: Settlement.Result.Timing
    ) -> ActionResult {
        let assemblyStart = RuntimeElapsed.now
        return ActionResult(
            outcome: outcome,
            payload: actionPayload(dispatch, handoff: handoff.event),
            message: message,
            observation: projectedObservation(
                boundary: boundary,
                history: history,
                handoff: handoff,
                readiness: readiness,
                duration: timing.elapsed
            ),
            subjectEvidence: dispatch.subjectEvidence,
            activationTrace: dispatch.activationTrace,
            screenActionHandler: dispatch.screenActionHandler,
            timing: actionTiming(
                dispatch: dispatch,
                timing: timing,
                assemblyStart: assemblyStart
            )
        )
    }

    static func actionExpectation(
        _ failed: Settlement.Result.FailedAction
    ) -> ExpectationResult? {
        guard case .completed(let dispatch) = failed.attempt.dispatch,
              dispatch.success,
              let predicate = failed.attempt.command.predicate else {
            return nil
        }
        return expectation(predicate: predicate, evidence: failed.attempt.evaluation)
    }

    static func waitActionResult(
        _ settled: Settlement.Result.SettledObservation
    ) -> ActionResult {
        ActionResult.success(
            payload: .wait,
            message: waitSuccessMessage(
                predicate: settled.predicate,
                elapsed: settled.timing.elapsed
            ),
            observation: projectedObservation(
                boundary: .established(settled.boundary),
                history: settled.history,
                handoff: .admitted(settled.handoff),
                readiness: .established(settled.readiness),
                duration: settled.timing.elapsed
            ),
            timing: ActionPerformanceTiming(totalMs: settled.timing.elapsed)
        )
    }

    static func waitActionResult(
        _ failed: Settlement.Result.FailedObservation
    ) -> ActionResult {
        let attempt = failed.attempt
        let failure: (kind: ActionFailure.Kind, message: String) = switch failed.reason {
        case .timedOut:
            (
                .timeout,
                renderTimeoutMessage(
                    predicate: attempt.predicate,
                    evidence: attempt.evaluation,
                    boundary: attempt.boundary,
                    readiness: attempt.readiness,
                    handoff: attempt.handoff,
                    history: attempt.history,
                    elapsed: attempt.timing.elapsed
                )
            )
        case .baselineUnavailable:
            (.accessibilityTreeUnavailable, TheBrains.treeUnavailableMessage)
        case .cancelled:
            (.actionFailed, "settlement cancelled after \(attempt.timing.elapsed)ms")
        case .viewportExitFailed:
            (.actionFailed, viewportExitFailureMessage)
        }
        return ActionResult.failure(
            payload: .wait,
            failureKind: failure.kind,
            message: failure.message,
            observation: projectedObservation(
                boundary: attempt.boundary,
                history: attempt.history,
                handoff: attempt.handoff,
                readiness: attempt.readiness,
                duration: attempt.timing.elapsed
            ),
            timing: ActionPerformanceTiming(totalMs: attempt.timing.elapsed)
        )
    }

    static func expectation(
        predicate: Settlement.Predicate,
        evidence: Settlement.Predicate.Evidence
    ) -> ExpectationResult {
        switch evidence.status {
        case .satisfied(let response), .unmet(let response):
            response.result.expectation(for: predicate.authored)
        case .pending:
            ExpectationResult(
                met: false,
                predicate: predicate.authored,
                actual: "deadline reached before predicate evaluation completed"
            )
        case .unavailable(let unavailable):
            ExpectationResult(
                met: false,
                predicate: predicate.authored,
                actual: String(describing: unavailable)
            )
        case .notEvaluated:
            ExpectationResult(
                met: false,
                predicate: predicate.authored,
                actual: "predicate was not evaluated"
            )
        case .notRequired:
            preconditionFailure("Predicate result cannot carry not-required evidence")
        }
    }

    static func projectedObservation(
        boundary: Settlement.BoundaryEvidence,
        history: Observation.EventsSince?,
        handoff: Settlement.Handoff.Evidence,
        readiness: Settlement.Readiness.Evidence,
        duration: ElapsedMilliseconds
    ) -> ActionResultObservationEvidence {
        let trace = traceEvidence(
            boundary: boundary.established,
            history: history,
            handoff: handoff.event,
            completeness: handoff.admission == nil ? .incomplete : .complete
        )
        guard let trace else { return .none }
        let settlement: ActionSettlementEvidence = switch readiness {
        case .pending:
            .timedOut(duration: duration)
        case .established(let establishment):
            if let admission = handoff.admission, admission.belongs(to: establishment) {
                .settled(duration: duration, path: establishment.path.actionSettlementPath)
            } else {
                .observationHandoffTimedOut(
                    duration: duration,
                    path: establishment.path.actionSettlementPath
                )
            }
        }
        return .settledTrace(trace, settlement)
    }

    static func traceEvidence(
        boundary: Settlement.EvidenceBoundary?,
        history: Observation.EventsSince?,
        handoff: Observation.SnapshotEvent?,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> AccessibilityTraceEvidence? {
        var traces = boundary.map { [AccessibilityTrace(capture: $0.moment.capture)] } ?? []
        if case .events(let events)? = history {
            traces += events.compactMap { event in
                guard case .snapshot(let snapshot) = event else { return nil }
                return AccessibilityTrace(capture: snapshot.moment.capture)
            }
        }
        if let handoff {
            traces.append(AccessibilityTrace(capture: handoff.moment.capture))
        }
        guard let trace = AccessibilityTrace.combinedTrace(from: traces) ?? traces.last else {
            return nil
        }
        return AccessibilityTraceEvidence(trace: trace, completeness: completeness)
    }

    static func actionTiming(
        dispatch: TheSafecracker.ActionDispatchResult,
        timing: Settlement.Result.Timing,
        assemblyStart: RuntimeElapsed.Instant
    ) -> ActionPerformanceTiming {
        let assembly = RuntimeElapsed.milliseconds(since: assemblyStart)
        return ActionPerformanceTiming(
            beforeObservationMs: timing.execution.beforeObservationMs,
            targetResolutionMs: dispatch.timing?.targetResolutionMs,
            actionDispatchMs: dispatch.timing?.actionDispatchMs,
            interactionMs: dispatch.timing?.interactionMs,
            finalSemanticEvidenceMs: timing.execution.finalSemanticEvidenceMs,
            resultAssemblyMs: assembly,
            totalMs: RuntimeElapsed.admit(
                milliseconds: timing.elapsed.milliseconds + assembly.milliseconds
            )
        )
    }

    static func actionPayload(
        _ dispatch: TheSafecracker.ActionDispatchResult,
        handoff: Observation.SnapshotEvent?
    ) -> ActionResult.Payload {
        guard case .typeText = dispatch.payload,
              let resolvedElementId = dispatch.resolvedElementId,
              let value = handoff?.snapshot.observation.tree
                  .findElement(heistId: resolvedElementId)?
                  .element.value else {
            return dispatch.payload
        }
        return .typeText(value)
    }

    static func waitSuccessMessage(
        predicate: Settlement.Predicate,
        elapsed: ElapsedMilliseconds
    ) -> String {
        let elapsedSeconds = String(
            format: "%.1f",
            Double(elapsed.milliseconds) / 1_000
        )
        if case .missing = predicate.resolved {
            return "absent confirmed after \(elapsedSeconds)s"
        }
        return "matched after \(elapsedSeconds)s"
    }

    static func baselineSummary(_ boundary: Settlement.BoundaryEvidence) -> String? {
        boundary.established?.moment.capture.summary
    }

    static func renderTimeoutMessage(
        predicate: Settlement.Predicate,
        evidence: Settlement.Predicate.Evidence,
        boundary: Settlement.BoundaryEvidence,
        readiness: Settlement.Readiness.Evidence,
        handoff: Settlement.Handoff.Evidence,
        history: Observation.EventsSince?,
        elapsed: ElapsedMilliseconds
    ) -> String {
        let headline = "settlement timed out after \(elapsed)ms"
        if case .satisfied = evidence.status {
            let incompleteAxis = if !readiness.isEstablished {
                "interface readiness did not complete"
            } else if handoff.admission == nil {
                "settled observation handoff did not complete"
            } else {
                "settlement completion evidence was unavailable"
            }
            return "\(headline); predicate was satisfied but \(incompleteAxis)"
        }

        var parts = [headline]
        let target = predicate.resolved.singularTarget
        var candidates: [ElementDiagnosticSummary] = []
        var interfaceElementCount: Int?
        let trace = traceEvidence(
            boundary: boundary.established,
            history: history,
            handoff: handoff.event,
            completeness: .incomplete
        )?.trace
        for capture in trace?.captures ?? [] {
            let interface = capture.interface
            interfaceElementCount = interface.projectedElements.count
            guard let target else { continue }
            let observed = AccessibilityTargetMatchGraph(interface: interface)
                .elementCandidates(in: target)
                .elements
                .compactMap(ElementDiagnosticSummary.init(waitMismatchCandidate:))
            for candidate in observed where !candidates.contains(candidate) {
                if candidates.count == 8 { candidates.removeFirst() }
                candidates.append(candidate)
            }
        }
        switch (predicate.resolved, target, interfaceElementCount) {
        case (.exists, let target?, let count?), (.missing, let target?, let count?):
            let exists = if case .exists = predicate.resolved { true } else { false }
            parts[0] += exists
                ? " waiting for element to appear"
                : " waiting for element to disappear"
            parts += [
                "expected: \(renderExpectedTarget(target))",
                "interface: \(count) elements",
                "last result: \(exists ? "element not found" : "element still present")",
                "Next: get_interface() to inspect current elements, then retry wait with an exact predicate.",
            ]
        case (.announcement, _, _), (.changed, _, _), (.noChange, _, _):
            parts.append("expected: \(predicate.authored.description)")
            parts.append("last observed: \(expectation(predicate: predicate, evidence: evidence).actual ?? "none")")
        case (.exists, _, _), (.missing, _, _):
            break
        }
        if case .unmet = evidence.status {
            parts += candidates.map {
                "observed accessibility candidate \($0.rendered(using: .predicateMismatchCandidate)) "
                    + "did not match \(predicate.authored.description)"
            }
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

    static var viewportExitFailureMessage: String {
        "Could not restore the accessibility viewport after observation"
    }
}

private extension ElementDiagnosticSummary {
    init?(waitMismatchCandidate element: HeistElement) {
        self.init(element: element)
        guard label != nil
                || identifier != nil
                || value != nil
                || hint != nil
                || !traits.isEmpty
                || !actions.isEmpty
                || !rotors.isEmpty
        else { return nil }
    }
}

private extension Settlement.Readiness.Path {
    var actionSettlementPath: ActionSettlementPath {
        switch self {
        case .currentStateCapture:
            preconditionFailure("Current-state capture has no public action settlement path")
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
