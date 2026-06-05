#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

/// Owns the before/body/after observation contract for executable interactions.
///
/// It coordinates settled semantic evidence. It does not choose command
/// payloads, resolve element inflation, decide recording policy, or format reports.
@MainActor
final class InteractionObservation {
    private let stash: TheStash
    private let postActionObservation: PostActionObservation
    private let predicateWait: PredicateWait

    init(stash: TheStash, postActionObservation: PostActionObservation) {
        self.stash = stash
        self.postActionObservation = postActionObservation
        self.predicateWait = PredicateWait(
            observeEvent: { scope, sequence, timeout in
                await stash.observeSettledSemanticObservation(
                    scope: scope,
                    after: sequence,
                    timeout: timeout
                )
            },
            latestEvent: {
                stash.latestSettledSemanticObservationEvent
            },
            semanticObservation: { event in
                postActionObservation.semanticObservation(from: event)
            },
            presenceTimeoutMessage: { predicate, elapsed in
                stash.presenceWaitTimeoutMessage(for: predicate, elapsed: elapsed)
            }
        )
    }

    func prepareBeforeState(timeout: Double? = 1.0) async -> PostActionObservation.BeforeState? {
        guard let event = await stash.observeSettledSemanticObservation(
            scope: .visible, after: nil, timeout: timeout
        ) else { return nil }
        return postActionObservation.captureSemanticState(from: event.observation)
    }

    func observeSemanticState(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        let event = await stash.observeSettledSemanticObservation(
            scope: scope,
            after: sequence,
            timeout: timeout ?? SemanticObservationTiming.defaultTimeout
        )

        guard let event else { return nil }
        return postActionObservation.semanticObservation(from: event)
    }

    func finishAfterAction(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil,
        afterStatePayload: ((PostActionObservation.BeforeState) -> ResultPayload?)? = nil,
        errorKind: ErrorKind? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        before: PostActionObservation.BeforeState,
        settleOutcome: SettleSession.Outcome? = nil
    ) async -> ActionResult {
        let settleEvidence = await postActionObservation.settleEvidence(
            before: before,
            outcome: settleOutcome
        )
        let finalEvidence = await postActionObservation.finalSemanticEvidence(
            before: before,
            settleEvidence: settleEvidence
        )
        return PostActionObservation.result(
            PostActionObservation.ResultInput(
                success: success,
                method: method,
                message: message,
                payload: payload,
                afterStatePayload: afterStatePayload,
                errorKind: errorKind,
                subjectEvidence: subjectEvidence,
                before: before,
                settleEvidence: settleEvidence,
                finalEvidence: finalEvidence
            )
        )
    }

    func waitForPredicate(
        _ step: WaitStep,
        initialTrace: AccessibilityTrace? = nil
    ) async -> HeistWaitReceipt {
        await predicateWait.wait(for: step, initialTrace: initialTrace)
    }

    func waitForPredicate(
        _ step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace? = nil
    ) async -> HeistWaitReceipt {
        await predicateWait.wait(for: step, initialTrace: initialTrace)
    }

    func waitForPredicateCases(
        _ cases: [ResolvedPredicateCase],
        timeout rawTimeout: Double
    ) async -> HeistCaseSelectionResult {
        await PredicateCaseSelection.waitFor(
            cases,
            timeout: rawTimeout,
            observeSemanticState: { scope, sequence, timeout in
                await self.observeSemanticState(
                    scope: scope,
                    after: sequence,
                    timeout: timeout
                )
            }
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
