#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@testable import TheScore

@MainActor
class SemanticObservationStreamTestCase: XCTestCase {
    var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
    }

    func observation(label: String, heistId: HeistId) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label, traits: .header), heistId),
        ])
    }

    func scrollObservation(
        headerId: HeistId,
        rowLabel: String,
        rowId: HeistId,
        headerObject: NSObject,
        rowObject: NSObject
    ) -> InterfaceObservation {
        let containerPath = TreePath([0])
        let headerPath = containerPath.appending(0)
        let rowPath = containerPath.appending(1)
        let header = AccessibilityElement.make(label: "Menu", traits: .header)
        let row = AccessibilityElement.make(label: rowLabel, traits: .button)
        let scroll = AccessibilityContainer(
            type: .list,
            scrollableContentSize: AccessibilitySize(width: 320, height: 1_200),
            frame: AccessibilityRect(x: 0, y: 80, width: 320, height: 560)
        )
        let membership = InterfaceTree.ScrollMembership(containerPath: containerPath, index: nil)
        return InterfaceObservation.makeForTests(
            elements: [
                headerId: InterfaceTree.Element(
                    heistId: headerId,
                    scrollMembership: membership,
                    element: header
                ),
                rowId: InterfaceTree.Element(
                    heistId: rowId,
                    scrollMembership: membership,
                    element: row
                ),
            ],
            hierarchy: [
                .container(scroll, children: [
                    .element(header, traversalIndex: 0),
                    .element(row, traversalIndex: 1),
                ]),
            ],
            heistIdsByPath: [
                headerPath: headerId,
                rowPath: rowId,
            ],
            elementRefs: [
                headerId: .init(object: headerObject, scrollView: nil),
                rowId: .init(object: rowObject, scrollView: nil),
            ],
            firstResponderHeistId: nil
        )
    }

    func screenChangedBatch() -> AccessibilityNotificationBatch {
        AccessibilityNotificationBatch(
            events: [PendingAccessibilityNotificationEvent(
                sequence: 1,
                kind: .screenChanged,
                timestamp: Date(timeIntervalSince1970: 0),
                notificationData: .none,
                associatedElement: .none,
                provenance: .scoped
            )],
            through: AccessibilityNotificationCursor(sequence: 1),
            scopedScreenChangedThrough: 1,
            gap: nil
        )
    }

    func settleResult(
        _ outcome: SettleOutcome,
        observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal
    ) -> SettleSession.Result {
        SettleSession.Result(
            outcome: outcome,
            finalObservation: SettleSessionFinalObservation(observation: observation),
            tripwireSignal: tripwireSignal
        )
    }

    func tripwireSignal(sequence: UInt64) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: nil,
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: sequence
        )
    }

    func installSettler(
        signal: @escaping @MainActor () -> TheTripwire.TripwireSignal,
        beforeSettle: @escaping @MainActor () async -> Void = {}
    ) -> @MainActor () -> Int {
        var count = 0
        vault.semanticObservationStream.readTripwireSignal = signal
        vault.semanticObservationStream.settleVisibleObservation = { vault, _, _, baseline, _ in
            count += 1
            await beforeSettle()
            let observation = self.observation(label: "Stable", heistId: "stable")
            vault.observeInterface(observation)
            return self.settleResult(
                .settled(timeMs: count),
                observation: observation,
                tripwireSignal: baseline
            )
        }
        return { count }
    }

    func admittedVisibleObservation() async throws -> Observation.Store.AdmittedObservation {
        let evidence = await vault.semanticObservationStream.admittedVisibleObservation(timeout: 1)
        return try XCTUnwrap(evidence)
    }

    func waitForSettleCount(
        _ expectedCount: Int,
        current: @escaping () -> Int
    ) async {
        for _ in 0..<1_000 {
            guard current() != expectedCount else { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) settle sessions")
    }

    func waitForObservationWaiterCount(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard vault.semanticObservationStream.observationWaiterCount != expectedCount else {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) observation waiters")
    }
}

@MainActor
func scriptedSettlement(
    _ command: Settlement.Command,
    observation event: Observation.SnapshotEvent?
) -> Settlement.Result {
    if case .currentState = command {
        return scriptedCurrentStateSettlement(command, event: event)
    }

    let predicate: Settlement.Predicate
    let baseline: Settlement.Baseline
    let trigger: Settlement.TriggerEvidence
    let timeoutPhase: Settlement.DeadlinePhase
    switch command {
    case .action(let action):
        guard let actionPredicate = action.predicate else {
            preconditionFailure("Scripted action settlement requires a predicate")
        }
        predicate = actionPredicate
        baseline = action.baseline
        trigger = .actionDispatched(.success(payload: action.command.actionResultPayload))
        timeoutPhase = event == nil ? .actionReadiness : .actionExpectation
    case .observation(let observationPredicate, _, let observationBaseline):
        predicate = observationPredicate
        baseline = observationBaseline
        trigger = .observation
        timeoutPhase = .observation
    case .currentState:
        preconditionFailure("Current-state settlement must use its capture path")
    }
    var predicateEvidence = Settlement.Predicate.Evidence(predicate: predicate)
    guard let event else {
        return Settlement.Result(
            outcome: .timedOut(timeoutPhase),
            evidence: Settlement.Evidence(
                command: command,
                boundary: scriptedBoundary(baseline, fallback: nil),
                trigger: trigger,
                predicate: predicateEvidence,
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                observationHistory: nil,
                elapsed: 1
            )
        )
    }
    let expectation = Settlement.PredicateEvaluation.evaluate(
        predicate.resolved,
        expression: predicate.authored,
        in: event
    )
    let evaluationEvidence: Settlement.Predicate.EvaluationEvidence = switch predicate.semantics {
    case .currentState:
        .currentState(event)
    case .positiveTransition:
        .positiveTransition(event)
    case .completeHistory:
        .completeHistory(.init(
            history: .events([.snapshot(event)]),
            handoff: event
        ))
    case .announcement:
        preconditionFailure("Scripted snapshot settlement cannot evaluate an announcement")
    }
    let request = Settlement.Predicate.EvaluationRequest(
        predicate: predicate,
        target: .observation(event.moment),
        evidence: evaluationEvidence
    )
    precondition(predicateEvidence.schedule(request))
    predicateEvidence.record(.init(
        target: request.target,
        result: PredicateEvaluationResult(
            met: expectation.met,
            actual: expectation.actual
        )
    ))
    let readiness = Settlement.Readiness.Establishment(
        generation: .initial,
        path: .semanticStability,
        observationBoundary: .including(event.moment)
    )
    let history = Observation.EventsSince.events([.snapshot(event)])
    let admission = Settlement.ObservationAdmission(event: event, history: history)
    guard let handoff = Settlement.Handoff.Admission.admit(admission, for: readiness) else {
        preconditionFailure("Scripted settlement handoff was not admitted")
    }
    return Settlement.Result(
        outcome: expectation.met
            ? .settled
            : .timedOut(timeoutPhase),
        evidence: Settlement.Evidence(
            command: command,
            boundary: scriptedBoundary(baseline, fallback: event.moment),
            trigger: trigger,
            predicate: predicateEvidence,
            readiness: .established(readiness),
            handoff: .admitted(handoff),
            observationHistory: history,
            elapsed: 1
        )
    )
}

private func scriptedCurrentStateSettlement(
    _ command: Settlement.Command,
    event: Observation.SnapshotEvent?
) -> Settlement.Result {
    guard let event else {
        return Settlement.Result(
            outcome: .baselineUnavailable,
            evidence: Settlement.Evidence(
                command: command,
                boundary: .unavailable(.unavailable),
                trigger: .observation,
                predicate: Settlement.Predicate.Evidence(predicate: nil),
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                observationHistory: nil,
                elapsed: 0
            )
        )
    }
    let readiness = Settlement.Readiness.Establishment(
        generation: .initial,
        path: .currentStateCapture,
        observationBoundary: .including(event.moment)
    )
    return Settlement.Result(
        outcome: .settled,
        evidence: Settlement.Evidence(
            command: command,
            boundary: .established(.init(moment: event.moment)),
            trigger: .observation,
            predicate: Settlement.Predicate.Evidence(predicate: nil),
            readiness: .established(readiness),
            handoff: .admitted(.currentState(event)),
            observationHistory: .events([]),
            elapsed: 0
        )
    )
}

private func scriptedBoundary(
    _ baseline: Settlement.Baseline,
    fallback: Observation.Moment?
) -> Settlement.BoundaryEvidence {
    switch baseline {
    case .capture:
        fallback.map {
            .established(Settlement.EvidenceBoundary(moment: $0))
        } ?? .pending
    case .supplied(let boundary):
        .established(boundary)
    case .unavailable(let failure):
        .unavailable(failure)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
