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

    func tripwireSignal(sequence: UInt64) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: nil,
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: sequence
        )
    }

    /// Counts visible readings and makes the tree stable, so a test can ask
    /// whether a second consumer started its own reading or joined the first.
    func installSettler(
        signal: @escaping @MainActor () -> TheTripwire.TripwireSignal,
        beforeSettle: @escaping @MainActor () async -> Void = {}
    ) -> @MainActor () -> Int {
        var count = 0
        vault.semanticObservationStream.readTripwireSignal = signal
        vault.semanticObservationStream.beforeVisibleReading = { [self] in
            count += 1
            await beforeSettle()
            vault.observeInterface(observation(label: "Stable", heistId: "stable"))
        }
        return { count }
    }

    /// A tree that moved and then stopped, as the two events that say so.
    typealias Reading = (
        changed: Observation.SnapshotEvent,
        settled: Observation.SnapshotEvent
    )

    /// A reading of a tree holding one header, that moved and then went quiet.
    func commitSettling(label: String) async -> Reading {
        await commitSettling(
            observation(label: label, heistId: HeistId(rawValue: label.lowercased()))
        )
    }

    /// A reading of `observation`, then the quiet reading that follows it.
    ///
    /// Two commits of the same tree: the second finds nothing changed, which is
    /// the only proof of stillness there is. A run needs it to settle, so the
    /// pair is what "the tree moved and then stopped" looks like as events.
    func commitSettling(_ observation: InterfaceObservation) async -> Reading {
        let changed = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)
        let settled = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)
        precondition(changed.isChange && !settled.isChange, "Second reading must be quiet")
        return (changed, settled)
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

/// Run a settlement to its terminal result through the real reducer.
///
/// Nothing here decides anything. `Settlement.Reducer` is
/// `(State, Event) -> Decision` over values — no clock, no actor, no I/O — so a
/// test drives it with the facts the executor would deliver and reads the same
/// `Result` production projects. A stand-in that assembled its own `Result`
/// could only ever be a second implementation of the thing under test, free to
/// drift from it.
///
/// `observation` and `dispatch` are the boundary's outputs, which the reducer
/// only ever consumes as values: a test names them the same way the executor
/// would deliver them. An observation is the one a test cannot fabricate — a
/// `Moment` carries the log's identity, so events come from the vault.
///
/// `settling` is the reading that found the tree unchanged, and a run needs one
/// to settle: stillness is proved by a quiet reading and nothing else, so a
/// script that stops at the first change describes a run that was still moving
/// when it ended. It is a real event from the vault too — `isChange` is derived
/// from the snapshot before it, so quiet is committed, never asserted.
@MainActor
func scriptedSettlement(
    _ command: Settlement.Command,
    observation event: Observation.SnapshotEvent?,
    settling: Observation.SnapshotEvent? = nil,
    dispatch: TheSafecracker.ActionDispatchResult? = nil,
    cancelled: Bool = false,
    elapsed: ElapsedMilliseconds = RuntimeElapsed.admit(milliseconds: 1)
) -> Settlement.Result {
    var run = ScriptedRun(command, elapsed: elapsed)

    if case .currentState = command {
        guard let event else { return run.finish(.baselineUnavailable(.unavailable)) }
        return run.finish(.baselineAdmitted(event))
    }
    if case .capture = command.baseline {
        guard let event else { return run.finish(.baselineUnavailable(.unavailable)) }
        run.send(.baselineAdmitted(event))
    }

    run.send(.channelsArmed)
    if case .action(let action) = command {
        // A caller that does not name a dispatch is describing a run whose
        // action plainly succeeded, which is the command's own payload.
        run.send(.dispatchCompleted(
            dispatch ?? .success(payload: action.command.actionResultPayload)
        ))
    }

    // Readiness before the observation: an admission with no established
    // readiness has no handoff to be admitted into.
    if let event {
        run.send(.readinessEstablished(.init(
            generation: .initial,
            observationBoundary: .including(event.moment)
        )))
        run.send(.observationAdmitted(.init(event: event)))
    }
    if let settling {
        run.send(.observationAdmitted(.init(event: settling)))
    }

    if cancelled {
        return run.finish(.cancelled)
    }
    // A run whose expectation was met is already terminal. Anything still
    // active ends the only other way a run can: its deadline.
    return run.timeOut()
}

/// A settlement being driven one fact at a time.
///
/// Holds only the reducer's own state, so what a scripted run believes is what
/// the reducer believes — there is no second model to reconcile.
@MainActor
private struct ScriptedRun {
    private var state: Settlement.State
    /// What every event in this run reports as time elapsed.
    ///
    /// Production reads a rising clock, but only the event that finalizes a run
    /// puts its elapsed on the result — every earlier one is discarded. So one
    /// value per run is exactly what is observable, and naming it here keeps it
    /// on the events rather than in a second copy beside them.
    private let elapsed: ElapsedMilliseconds
    /// The deadline the reducer last asked to have armed.
    ///
    /// Tracked from the effect rather than read off the session, because that is
    /// the contract: the reducer only honours a `deadlineReached` for the
    /// deadline it is currently waiting on, and `armDeadline` is how it says
    /// which one that is.
    private var armedDeadline: Settlement.PhaseDeadline?

    init(_ command: Settlement.Command, elapsed: ElapsedMilliseconds) {
        self.elapsed = elapsed
        state = Settlement.Reducer.begin(command).state
    }

    /// Deliver one fact, unless the run already ended.
    mutating func send(_ fact: Settlement.Event.Fact) {
        guard state.result == nil else { return }
        let decision = Settlement.Reducer.reduce(
            state,
            event: Settlement.Event(
                fact: fact,
                elapsed: elapsed,
                instant: scriptedInstant
            )
        )
        state = decision.state
        for effect in decision.effects {
            if case .armDeadline(let deadline) = effect {
                armedDeadline = deadline
            }
        }
    }

    /// Deliver a last fact and take the result.
    mutating func finish(_ fact: Settlement.Event.Fact) -> Settlement.Result {
        send(fact)
        return result()
    }

    /// End an unsettled run at its deadline.
    ///
    /// Uses the deadline the reducer armed, so the fact names the one the run
    /// is actually waiting on.
    mutating func timeOut() -> Settlement.Result {
        if let armedDeadline {
            send(.deadlineReached(armedDeadline))
        }
        return result()
    }

    /// The terminal result, finalizing first if the run still owes it.
    private mutating func result() -> Settlement.Result {
        if state.result == nil {
            send(.finalized(.retained))
        }
        guard let result = state.result else {
            preconditionFailure("Scripted settlement did not reach a terminal result")
        }
        return result
    }
}

/// One instant for every scripted event, so a run is a function of its facts
/// alone rather than of when it was run.
private let scriptedInstant = ContinuousClock.Instant.now

#endif // DEBUG
#endif // canImport(UIKit)
