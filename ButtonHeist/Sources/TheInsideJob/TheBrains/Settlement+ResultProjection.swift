#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension Settlement {
    internal enum ResultProjector {
        internal static func projectAction(_ result: Result) -> HeistActionEvidence {
            let actionResult = actionResult(from: result)
            let expectation = result.evidence.trigger.permitsCompletion
                ? expectation(from: result)
                : nil
            return .completed(result: actionResult, expectation: expectation)
        }

        internal static func projectWait(_ result: Result) -> HeistSettlementEvidence {
            precondition(
                result.evidence.command.waitsForObservation,
                "Wait projection requires an observation settlement trigger"
            )
            guard let expectation = expectation(from: result) else {
                preconditionFailure("Wait projection requires evaluated predicate evidence")
            }
            let actionResult = standaloneWaitActionResult(from: result)
            if result.outcome == .settled,
               let met = ExpectationResult.Met(expectation),
               let check = HeistSettlementEvidence.MatchedCheck(
                   actionResult: actionResult,
                   expectation: met
               ) {
                return .matched(
                    check,
                    baselineSummary: baselineSummary(from: result),
                    finalSummary: expectation.actual
                )
            }
            guard let check = HeistSettlementEvidence.UnmatchedCheck(
                actionResult: actionResult,
                expectation: expectation
            ) else {
                preconditionFailure("Incomplete wait settlement requires unmatched public evidence")
            }
            return .failed(
                check,
                baselineSummary: baselineSummary(from: result),
                finalSummary: expectation.actual
            )
        }
    }
}

private extension Settlement.ResultProjector {
    static func baselineSummary(from result: Settlement.Result) -> String? {
        guard case .established(let boundary) = result.evidence.boundary else { return nil }
        return boundary.moment.capture.summary
    }

    static func actionResult(from result: Settlement.Result) -> ActionResult {
        guard case .action(let action) = result.evidence.command else {
            preconditionFailure("Action projection requires an action settlement trigger")
        }
        let command = action.command
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
                let failure = actionFailure(from: result)
                return ActionResult(
                    outcome: failure.map { .failure($0.kind) } ?? .success,
                    payload: payload,
                    message: failure?.message ?? dispatch.message,
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
            let failure: (kind: ActionFailure.Kind, message: String) = switch result.outcome {
            case .timedOut:
                (
                    .timeout,
                    "action dispatch did not complete before settlement deadline "
                        + "after \(result.evidence.elapsed)ms"
                )
            case .baselineUnavailable:
                (.accessibilityTreeUnavailable, TheBrains.treeUnavailableMessage)
            case .cancelled:
                (.actionFailed, "cancelled after \(result.evidence.elapsed)ms")
            case .settled, .dispatchFailed:
                preconditionFailure("Pending action requires a pre-dispatch terminal outcome")
            }
            return ActionResult.failure(
                payload: command.actionResultPayload,
                failureKind: failure.kind,
                message: failure.message,
                observation: observation,
                timing: ActionPerformanceTiming(
                    beforeObservationMs: result.evidence.timing.beforeObservationMs,
                    finalSemanticEvidenceMs: result.evidence.timing.finalSemanticEvidenceMs,
                    resultAssemblyMs: resultAssemblyMs,
                    totalMs: RuntimeElapsed.admit(
                        milliseconds: result.evidence.elapsed.milliseconds
                            + resultAssemblyMs.milliseconds
                    )
                )
            )
        case .observation:
            preconditionFailure("Action projection cannot consume observation trigger evidence")
        }
    }

    static func actionFailure(
        from result: Settlement.Result
    ) -> (kind: ActionFailure.Kind, message: String)? {
        switch result.outcome {
        case .cancelled:
            (.actionFailed, "cancelled after \(result.evidence.elapsed)ms")
        case .timedOut:
            if case .captureFailed = result.evidence.handoff {
                (.actionFailed, "Could not capture accessibility tree after action")
            } else {
                (.timeout, renderTimeoutMessage(from: result))
            }
        case .baselineUnavailable:
            (.accessibilityTreeUnavailable, TheBrains.treeUnavailableMessage)
        case .settled:
            nil
        case .dispatchFailed:
            preconditionFailure("Successful dispatch cannot have dispatch-failed settlement outcome")
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

    static func standaloneWaitActionResult(from result: Settlement.Result) -> ActionResult {
        let observation = projectedObservation(from: result)
        let timing = ActionPerformanceTiming(totalMs: result.evidence.elapsed)
        if result.outcome == .settled {
            return ActionResult.success(
                payload: .wait,
                message: standaloneWaitSuccessMessage(from: result),
                observation: observation,
                timing: timing
            )
        }
        return ActionResult.failure(
            payload: .wait,
            failureKind: waitFailureKind(for: result.outcome),
            message: waitFailureMessage(from: result),
            observation: observation,
            timing: timing
        )
    }

    static func standaloneWaitSuccessMessage(from result: Settlement.Result) -> String {
        guard case .observation = result.evidence.command,
              result.outcome == .settled,
              let predicate = result.evidence.command.predicate else {
            preconditionFailure("Successful standalone wait message requires a settled observation predicate")
        }
        let elapsed = String(
            format: "%.1f",
            Double(result.evidence.elapsed.milliseconds) / 1_000
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
                milliseconds: result.evidence.elapsed.milliseconds
                    + resultAssemblyMs.milliseconds
            )
        )
    }

    static func settlementEvidence(from result: Settlement.Result) -> ActionSettlementEvidence {
        let duration = result.evidence.elapsed
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
            traces.append(AccessibilityTrace(capture: boundary.moment.capture))
        }
        if case .events(let events)? = result.evidence.observationHistory {
            traces += events.compactMap { event in
                guard case .snapshot(let snapshot) = event else { return nil }
                return AccessibilityTrace(capture: snapshot.moment.capture)
            }
        }
        if let handoff = result.evidence.handoff.event {
            traces.append(AccessibilityTrace(capture: handoff.moment.capture))
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
            renderTimeoutMessage(from: result)
        case .baselineUnavailable:
            TheBrains.treeUnavailableMessage
        case .dispatchFailed:
            "observation settlement cannot fail action dispatch"
        case .cancelled:
            "settlement cancelled after \(result.evidence.elapsed)ms"
        case .settled:
            preconditionFailure("Settled wait has no failure message")
        }
    }

    static func renderTimeoutMessage(
        from result: Settlement.Result
    ) -> String {
        let headline = "settlement timed out after \(result.evidence.elapsed)ms"
        guard let predicate = result.evidence.command.predicate else { return headline }
        if case .satisfied = result.evidence.predicate.status {
            let incompleteAxis = if !result.evidence.readiness.isEstablished {
                "interface readiness did not complete"
            } else if result.evidence.handoff.admission == nil {
                "settled observation handoff did not complete"
            } else {
                "settlement completion evidence was unavailable"
            }
            return "\(headline); predicate was satisfied but \(incompleteAxis)"
        }

        var parts = [headline]
        let target = predicate.resolved.singularTarget
        let traceProjection = traceEvidence(from: result).map {
            TimeoutTraceProjection(trace: $0.trace, target: target)
        }
        switch (predicate.resolved.core, target, traceProjection?.interfaceElementCount) {
        case (.presence(let presence), let target?, let count?):
            let expectation: String
            let reason: String
            switch presence {
            case .exists:
                expectation = "element to appear"
                reason = "element not found"
            case .missing:
                expectation = "element to disappear"
                reason = "element still present"
            }
            parts[0] += " waiting for \(expectation)"
            parts += [
                "expected: \(renderExpectedTarget(target))",
                "interface: \(count) elements",
                "last result: \(reason)",
                "Next: get_interface() to inspect current elements, then retry wait with an exact predicate.",
            ]
        case (.announcement, _, _), (.changed, _, _), (.noChange, _, _):
            parts.append("expected: \(predicate.authored.description)")
            if let actual = expectation(from: result)?.actual {
                parts.append("last observed: \(actual)")
            }
        case (.presence, _, _):
            break
        }
        if case .unmet = result.evidence.predicate.status {
            parts += traceProjection?.candidates.map {
                "observed accessibility candidate \($0.rendered(using: .predicateMismatchCandidate)) "
                    + "did not match \(predicate.authored.description)"
            } ?? []
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

private struct TimeoutTraceProjection {
    private static let maximumCandidateCount = 8

    let candidates: [ElementDiagnosticSummary]
    let interfaceElementCount: Int?

    init(
        trace: AccessibilityTrace,
        target: ResolvedAccessibilityTarget?
    ) {
        var candidates: [ElementDiagnosticSummary] = []
        var interfaceElementCount: Int?
        for capture in trace.captures {
            let interface = capture.interface
            guard let target else {
                interfaceElementCount = interface.projectedElements.count
                continue
            }
            let observedCandidates = AccessibilityTargetMatchGraph(interface: interface)
                .elementCandidates(in: target)
                .elements
                .compactMap(ElementDiagnosticSummary.init(waitMismatchCandidate:))
            guard !observedCandidates.isEmpty else { continue }
            for candidate in observedCandidates where !candidates.contains(candidate) {
                if candidates.count == Self.maximumCandidateCount {
                    candidates.removeFirst()
                }
                candidates.append(candidate)
            }
            interfaceElementCount = interface.projectedElements.count
        }
        self.candidates = candidates
        self.interfaceElementCount = interfaceElementCount
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
