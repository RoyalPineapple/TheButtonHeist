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
                    expectation: settled.command.predicate.map { predicate in
                        ExpectationResult(
                            met: true,
                            predicate: predicate.authored,
                            actual: matchedAnnouncement(predicate, in: settled.tickLog)
                        )
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
                let expectation = ExpectationResult(
                    met: true,
                    predicate: settled.predicate.authored,
                    actual: nil
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
                    outstanding: failed.attempt.outstanding
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
            tickLog: settled.tickLog,
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
                (.actionFailed, dispatch.message ?? Strings.Failure.actionDispatchFailed)
            } else {
                preconditionFailure("Dispatch failure requires completed dispatch evidence")
            }
        case .baselineUnavailable:
            (.accessibilityTreeUnavailable, TheBrains.treeUnavailableMessage)
        case .timedOut:
            if case .captureFailed = attempt.handoff {
                (.actionFailed, Strings.Failure.treeCaptureFailed)
            } else if let predicate = attempt.command.predicate {
                (
                    .timeout,
                    renderTimeoutMessage(
                        predicate: predicate,
                        outstanding: attempt.outstanding,
                        boundary: attempt.boundary,
                        readiness: attempt.readiness,
                        handoff: attempt.handoff,
                        tickLog: attempt.tickLog,
                        elapsed: attempt.timing.elapsed
                    )
                )
            } else {
                (
                    .timeout,
                    Strings.Timeout.dispatchIncomplete(attempt.timing.elapsed)
                )
            }
        case .cancelled:
            (.actionFailed, Strings.Failure.cancelled(attempt.timing.elapsed))
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
                    tickLog: attempt.tickLog,
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
                tickLog: attempt.tickLog,
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
        tickLog: TickLog,
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
                tickLog: tickLog,
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
        return expectation(predicate: predicate, outstanding: failed.attempt.outstanding)
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
                tickLog: settled.tickLog,
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
                    outstanding: attempt.outstanding,
                    boundary: attempt.boundary,
                    readiness: attempt.readiness,
                    handoff: attempt.handoff,
                    tickLog: attempt.tickLog,
                    elapsed: attempt.timing.elapsed
                )
            )
        case .baselineUnavailable:
            (.accessibilityTreeUnavailable, TheBrains.treeUnavailableMessage)
        case .cancelled:
            (.actionFailed, Strings.Failure.settlementCancelled(attempt.timing.elapsed))
        case .viewportExitFailed:
            (.actionFailed, viewportExitFailureMessage)
        }
        return ActionResult.failure(
            payload: .wait,
            failureKind: failure.kind,
            message: failure.message,
            observation: projectedObservation(
                boundary: attempt.boundary,
                tickLog: attempt.tickLog,
                handoff: attempt.handoff,
                readiness: attempt.readiness,
                duration: attempt.timing.elapsed
            ),
            timing: ActionPerformanceTiming(totalMs: attempt.timing.elapsed)
        )
    }

    /// A failed run has exactly one thing to say: it ran out of time while
    /// waiting on the head of the list. Everything behind the head was never
    /// asked.
    static func expectation(
        predicate: Settlement.Predicate,
        outstanding: [PendingPredicate]
    ) -> ExpectationResult {
        ExpectationResult(
            met: false,
            predicate: predicate.authored,
            actual: outstanding.first.map { Strings.Timeout.waitingOn($0.description) }
        )
    }

    static func projectedObservation(
        boundary: Settlement.BoundaryEvidence,
        tickLog: TickLog,
        handoff: Settlement.Handoff.Evidence,
        readiness: Settlement.Readiness.Evidence,
        duration: ElapsedMilliseconds
    ) -> ActionResultObservationEvidence {
        let trace = traceEvidence(
            boundary: boundary.established,
            tickLog: tickLog,
            handoff: handoff.event,
            completeness: handoff.admission == nil ? .incomplete : .complete
        )
        guard let trace else { return .none }
        let settlement: ActionSettlementEvidence = switch readiness {
        case .pending:
            .timedOut(duration: duration)
        case .established(let establishment):
            if let admission = handoff.admission, admission.belongs(to: establishment) {
                .settled(duration: duration)
            } else {
                .observationHandoffTimedOut(duration: duration)
            }
        }
        return .settledTrace(trace, settlement)
    }

    /// The run's trace, projected from the ticks it observed.
    ///
    /// The boundary capture is already the log's first tick, so only the handoff
    /// is added here: it is admitted outside the tick stream.
    static func traceEvidence(
        boundary: Settlement.EvidenceBoundary?,
        tickLog: TickLog,
        handoff: Observation.SnapshotEvent?,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> AccessibilityTraceEvidence? {
        var traces = tickLog.trace.map { [$0] } ?? []
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

    /// The announcement a met announcement predicate matched.
    ///
    /// An announcement is a tick, so the log is where one is recorded and this
    /// reads it there. The trace only carries the announcements that arrived
    /// while a reading was being folded into a capture, which is a fact about
    /// when the notification landed rather than about what was announced.
    static func matchedAnnouncement(
        _ predicate: Settlement.Predicate,
        in tickLog: TickLog
    ) -> String? {
        guard case .announcement = predicate.resolved else { return nil }
        return tickLog.announcements.last
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
        outstanding: [PendingPredicate],
        boundary: Settlement.BoundaryEvidence,
        readiness: Settlement.Readiness.Evidence,
        handoff: Settlement.Handoff.Evidence,
        tickLog: TickLog,
        elapsed: ElapsedMilliseconds
    ) -> String {
        let headline = if let tip = outstanding.first?.description {
            Strings.Timeout.settlementElapsed(elapsed, waitingOn: tip)
        } else {
            Strings.Timeout.settlementElapsed(elapsed)
        }

        var parts = [headline]
        let target = predicate.resolved.singularTarget
        var candidates: [ElementDiagnosticSummary] = []
        var interfaceElementCount: Int?
        let trace = traceEvidence(
            boundary: boundary.established,
            tickLog: tickLog,
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
                ? Strings.Diagnostic.waitingToAppear
                : Strings.Diagnostic.waitingToDisappear
            parts += [
                Strings.Diagnostic.expected(renderExpectedTarget(target)),
                Strings.Diagnostic.interfaceElementCount(count),
                Strings.Diagnostic.lastResult(
                    exists
                        ? Strings.Diagnostic.elementNotFound
                        : Strings.Diagnostic.elementStillPresent
                ),
                Strings.Diagnostic.nextStep,
            ]
        case (.announcement, _, _), (.noChange, _, _), (.screenChanged, _, _), (.elementsChanged, _, _):
            parts.append(Strings.Diagnostic.expected(predicate.authored.description))
            parts.append(Strings.Timeout.stillWaitingOn(
                outstanding.first?.description ?? Strings.Diagnostic.none
            ))
        case (.exists, _, _), (.missing, _, _):
            break
        }
        parts += candidates.map {
            Strings.Diagnostic.candidateDidNotMatch(
                $0.rendered(using: .predicateMismatchCandidate),
                predicate.authored.description
            )
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

// MARK: - Messages

/// What a caller reads when a run did not do what was asked.
///
/// Templates rather than a vocabulary: each interpolates something, and the
/// same sentence is assembled from more than one branch below.
private enum Strings {
    /// Why a run ended without doing what was asked.
    ///
    /// There is only one failure — the clock ran out — so the only content is
    /// which predicate it ran out on.
    internal enum Timeout {
        static func waitingOn(_ tip: String) -> String {
            "timed out while waiting on \(tip)"
        }

        static func stillWaitingOn(_ tip: String) -> String {
            "still waiting on: \(tip)"
        }

        static func settlementElapsed(_ milliseconds: some CustomStringConvertible) -> String {
            "settlement timed out after \(milliseconds)ms"
        }

        static func settlementElapsed(_ milliseconds: some CustomStringConvertible, waitingOn tip: String) -> String {
            "\(settlementElapsed(milliseconds)) while waiting on \(tip)"
        }

        static func dispatchIncomplete(_ milliseconds: some CustomStringConvertible) -> String {
            "action dispatch did not complete before settlement deadline after \(milliseconds)ms"
        }
    }

    /// What the run was looking for, and what it saw instead.
    internal enum Diagnostic {
        static var waitingToAppear: String { " waiting for element to appear" }
        static var waitingToDisappear: String { " waiting for element to disappear" }
        static var elementNotFound: String { "element not found" }
        static var elementStillPresent: String { "element still present" }
        static var none: String { "none" }

        static var nextStep: String {
            "Next: get_interface() to inspect current elements, "
                + "then retry wait with an exact predicate."
        }

        static func expected(_ target: String) -> String {
            "expected: \(target)"
        }

        static func interfaceElementCount(_ count: Int) -> String {
            "interface: \(count) elements"
        }

        static func lastResult(_ result: String) -> String {
            "last result: \(result)"
        }

        static func candidateDidNotMatch(_ candidate: String, _ predicate: String) -> String {
            "observed accessibility candidate \(candidate) did not match \(predicate)"
        }
    }

    /// Things that went wrong before any predicate could be asked.
    internal enum Failure {
        static var treeCaptureFailed: String { "Could not capture accessibility tree after action" }
        static var actionDispatchFailed: String { "action dispatch failed" }

        static func cancelled(_ milliseconds: some CustomStringConvertible) -> String {
            "cancelled after \(milliseconds)ms"
        }

        static func settlementCancelled(_ milliseconds: some CustomStringConvertible) -> String {
            "settlement cancelled after \(milliseconds)ms"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
