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
                tripwireSignal: baseline.tripwireSignal
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
    switch command {
    case .action(let action):
        guard let actionPredicate = action.predicate else {
            preconditionFailure("Scripted action settlement requires a predicate")
        }
        return scriptedActionSettlement(action, predicate: actionPredicate, event: event)
    case .observation(let predicate, _, let baseline):
        return scriptedObservationSettlement(predicate, baseline: baseline, event: event)
    case .currentState:
        return scriptedCurrentStateSettlement(command, event: event)
    }
}

@MainActor
private func scriptedActionSettlement(
    _ action: Settlement.Command.Action,
    predicate: Settlement.Predicate,
    event: Observation.SnapshotEvent?
) -> Settlement.Result {
    let timeoutPhase: Settlement.DeadlinePhase = event == nil
        ? .actionReadiness
        : .actionExpectation
    let boundary = scriptedBoundary(action.baseline, fallback: event?.moment)
    guard let event else {
        return .action(.failed(.init(
            reason: .timedOut(timeoutPhase),
            attempt: .init(
                command: action,
                boundary: boundary,
                dispatch: .completed(.success(payload: action.command.actionResultPayload)),
                outstanding: Expectation([predicate.resolved]).outstanding,
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                history: nil,
                timing: scriptedTiming
            )
        )))
    }
    let observation = scriptedPredicateObservation(predicate, event: event)
    let dispatch = TheSafecracker.ActionDispatchResult.success(
        payload: action.command.actionResultPayload
    )
    guard observation.met else {
        return .action(.failed(.init(
            reason: .timedOut(timeoutPhase),
            attempt: .init(
                command: action,
                boundary: boundary,
                dispatch: .completed(dispatch),
                outstanding: observation.outstanding,
                readiness: .established(observation.readiness),
                handoff: .admitted(observation.handoff),
                history: observation.history,
                timing: scriptedTiming
            )
        )))
    }
    guard case .established(let establishedBoundary) = boundary else {
        preconditionFailure("Settled scripted action requires an established boundary")
    }
    return .action(.settled(.init(
        command: action,
        boundary: establishedBoundary,
        dispatch: dispatch,
        readiness: observation.readiness,
        handoff: observation.handoff,
        history: observation.history,
        timing: scriptedTiming
    )))
}

@MainActor
private func scriptedObservationSettlement(
    _ predicate: Settlement.Predicate,
    baseline: Settlement.Baseline,
    event: Observation.SnapshotEvent?
) -> Settlement.Result {
    let boundary = scriptedBoundary(baseline, fallback: event?.moment)
    guard let event else {
        return .observation(.failed(.init(
            reason: .timedOut(.observation),
            attempt: .init(
                predicate: predicate,
                boundary: boundary,
                outstanding: Expectation([predicate.resolved]).outstanding,
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                history: nil,
                timing: scriptedTiming
            )
        )))
    }
    let observation = scriptedPredicateObservation(predicate, event: event)
    guard observation.met else {
        return .observation(.failed(.init(
            reason: .timedOut(.observation),
            attempt: .init(
                predicate: predicate,
                boundary: boundary,
                outstanding: observation.outstanding,
                readiness: .established(observation.readiness),
                handoff: .admitted(observation.handoff),
                history: observation.history,
                timing: scriptedTiming
            )
        )))
    }
    guard case .established(let establishedBoundary) = boundary else {
        preconditionFailure("Settled scripted observation requires an established boundary")
    }
    return .observation(.settled(.init(
        predicate: predicate,
        boundary: establishedBoundary,
        readiness: observation.readiness,
        handoff: observation.handoff,
        history: observation.history,
        timing: scriptedTiming
    )))
}

private struct ScriptedPredicateObservation {
    let met: Bool
    let outstanding: [String]
    let readiness: Settlement.Readiness.Establishment
    let handoff: Settlement.Handoff.Admission
    let history: Observation.EventsSince
}

/// The scripted stand-in for a run that reached one observation.
///
/// It drives the same expectation the reducer drives: the event goes in as a
/// snapshot tick, then a no-change tick says the tree stopped. What comes out
/// is what settlement itself would decide.
@MainActor
private func scriptedPredicateObservation(
    _ predicate: Settlement.Predicate,
    event: Observation.SnapshotEvent
) -> ScriptedPredicateObservation {
    var expectation = Expectation([predicate.resolved])
    if let interface = event.trace.captures.last?.interface {
        expectation.snapshot(interface)
    }
    expectation.noChange()
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
    return ScriptedPredicateObservation(
        met: expectation.isMet,
        outstanding: expectation.outstanding,
        readiness: readiness,
        handoff: handoff,
        history: history
    )
}

private var scriptedTiming: Settlement.Result.Timing {
    .init(
        execution: .init(),
        elapsed: RuntimeElapsed.admit(milliseconds: 1)
    )
}

private func scriptedCurrentStateSettlement(
    _ command: Settlement.Command,
    event: Observation.SnapshotEvent?
) -> Settlement.Result {
    guard case .currentState = command else {
        preconditionFailure("Current-state settlement requires a current-state command")
    }
    guard let event else {
        return .currentState(.failed(.init(
            reason: .unavailable(.unavailable),
            timing: .init(
                execution: .init(),
                elapsed: RuntimeElapsed.admit(milliseconds: 0)
            )
        )))
    }
    return .currentState(.captured(.init(
        event: event,
        timing: .init(
            execution: .init(),
            elapsed: RuntimeElapsed.admit(milliseconds: 0)
        )
    )))
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
