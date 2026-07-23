#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

private typealias DiagnosisRow = (String, Settlement.Result, DiagnosisExpectation)

@MainActor
final class SettlementDiagnosisTests: SemanticObservationStreamTestCase {
    func testTerminalBreadcrumbProjectsCanonicalEvidenceOnce() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Observed")
        let announcement = Observation.AnnouncementEvent(announcement: CapturedAnnouncement(
            sequence: 9,
            text: "Saved",
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .announcement
        ))
        let predicate = try announcementPredicate()
        let readiness = Settlement.Readiness.Establishment(
            generation: .initial,
            path: .uikitIdle,
            observationBoundary: .including(observed.moment)
        )
        let history = Observation.EventsSince.events([
            .snapshot(observed),
            .announcement(announcement),
        ])
        let handoff = try XCTUnwrap(Settlement.Handoff.Admission.admit(
            Settlement.ObservationAdmission(event: observed, history: history),
            for: readiness
        ))

        let rows = diagnosisRows(
            baseline: baseline,
            observed: observed,
            announcement: announcement,
            predicate: predicate,
            readiness: readiness,
            handoff: handoff,
            history: history
        )

        for (name, result, expected) in rows {
            let diagnosis = Settlement.Diagnosis.project(result)
            XCTAssertEqual(diagnosis.outcome, expected.outcome, name)
            XCTAssertEqual(diagnosis.dispatch, expected.dispatch, name)
            XCTAssertEqual(diagnosis.predicate.status, expected.predicate, name)
            XCTAssertEqual(diagnosis.readiness, expected.readiness, name)
            XCTAssertEqual(diagnosis.handoff, expected.handoff, name)
            XCTAssertEqual(diagnosis.deadline.reached, expected.deadlineReached, name)
            XCTAssertEqual(
                diagnosis.observationMoments.baselineSequence,
                name == "tree unavailable" ? nil : baseline.sequence,
                name
            )
            XCTAssertEqual(
                diagnosis.observationMoments.currentSequence,
                name == "tree unavailable" ? nil : observed.sequence,
                name
            )
            XCTAssertEqual(
                diagnosis.announcementCursors,
                name == "tree unavailable"
                    ? .unavailable
                    : .bounded(
                        after: baseline.notificationSequence,
                        through: announcement.announcement.sequence
                    ),
                name
            )
        }
    }

    func testAutomaticTimeoutEmitsAfterCleanupAndPerformsNoExtraWork() async {
        let baseline = await commit(label: "Baseline")
        let boundary = AutomaticTimeoutDiagnosisBoundary(baseline: baseline)
        let recorder = SettlementDiagnosisRecorder(boundary: boundary)
        let command = Settlement.Command(
            trigger: .action(.dismiss),
            predicate: nil,
            deadline: .init(instant: .now)
        )

        let result = await Settlement.Executor(
            boundary: boundary,
            diagnosisSink: recorder.record
        ).execute(command)

        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertEqual(recorder.diagnoses.count, 1)
        XCTAssertEqual(recorder.diagnoses.first?.outcome, .timedOut)
        XCTAssertEqual(recorder.snapshotAtEmission, .init(
            captures: 1,
            admissions: 1,
            dispatches: 0,
            evaluations: 0,
            quiescence: 1,
            finalization: 1
        ))

        boundary.publishAfterTerminal()
        for _ in 0..<8 {
            await Task.yield()
        }

        XCTAssertEqual(boundary.snapshot, recorder.snapshotAtEmission)
        XCTAssertEqual(recorder.diagnoses.count, 1)
    }

    private func diagnosisRows(
        baseline: Observation.SnapshotEvent,
        observed: Observation.SnapshotEvent,
        announcement: Observation.AnnouncementEvent,
        predicate: Settlement.Predicate,
        readiness: Settlement.Readiness.Establishment,
        handoff: Settlement.Handoff.Admission,
        history: Observation.EventsSince
    ) -> [DiagnosisRow] {
        completionRows(
            baseline: baseline,
            observed: observed,
            announcement: announcement,
            predicate: predicate,
            readiness: readiness,
            handoff: handoff,
            history: history
        ) + timeoutRows(
            baseline: baseline,
            observed: observed,
            announcement: announcement,
            predicate: predicate,
            readiness: readiness,
            handoff: handoff,
            history: history
        ) + unavailableRows(
            baseline: baseline,
            predicate: predicate,
            history: history
        )
    }

    private func completionRows(
        baseline: Observation.SnapshotEvent,
        observed: Observation.SnapshotEvent,
        announcement: Observation.AnnouncementEvent,
        predicate: Settlement.Predicate,
        readiness: Settlement.Readiness.Establishment,
        handoff: Settlement.Handoff.Admission,
        history: Observation.EventsSince
    ) -> [DiagnosisRow] {
        [
            (
                "settled",
                result(
                    outcome: .settled,
                    predicate: predicate,
                    predicateEvidence: predicateEvidence(
                        predicate,
                        announcement: announcement,
                        met: true
                    ),
                    readiness: .established(readiness),
                    handoff: .admitted(handoff),
                    history: history,
                    baseline: baseline
                ),
                DiagnosisExpectation(
                    outcome: .settled,
                    dispatch: .notApplicable,
                    predicate: .satisfied(
                        .announcement(sequence: announcement.announcement.sequence),
                        actual: "Saved"
                    ),
                    readiness: .established(generation: .initial, path: .uikitIdle),
                    handoff: .admitted(
                        generation: .initial,
                        observationSequence: observed.sequence
                    ),
                    deadlineReached: false
                )
            ),
            (
                "dispatch failure",
                result(
                    outcome: .dispatchFailed,
                    trigger: .actionDispatched(.failure(
                        .dismiss,
                        message: "dismiss failed",
                        failureKind: .actionFailed
                    )),
                    commandTrigger: .action(.dismiss),
                    predicate: predicate,
                    predicateEvidence: dispatchFailureEvidence(predicate),
                    readiness: .established(readiness),
                    handoff: .admitted(handoff),
                    history: history,
                    baseline: baseline
                ),
                DiagnosisExpectation(
                    outcome: .dispatchFailed,
                    dispatch: .failed(.actionFailed),
                    predicate: .notEvaluated,
                    readiness: .established(generation: .initial, path: .uikitIdle),
                    handoff: .admitted(
                        generation: .initial,
                        observationSequence: observed.sequence
                    ),
                    deadlineReached: false
                )
            ),
            (
                "cancellation",
                result(
                    outcome: .cancelled,
                    predicate: predicate,
                    predicateEvidence: Settlement.Predicate.Evidence(predicate: predicate),
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    history: history,
                    baseline: baseline
                ),
                DiagnosisExpectation(
                    outcome: .cancelled,
                    dispatch: .notApplicable,
                    predicate: .pending,
                    readiness: .pending(generation: .initial),
                    handoff: .pending(generation: .initial),
                    deadlineReached: false
                )
            ),
        ]
    }

    private func timeoutRows(
        baseline: Observation.SnapshotEvent,
        observed: Observation.SnapshotEvent,
        announcement: Observation.AnnouncementEvent,
        predicate: Settlement.Predicate,
        readiness: Settlement.Readiness.Establishment,
        handoff: Settlement.Handoff.Admission,
        history: Observation.EventsSince
    ) -> [DiagnosisRow] {
        let metEvidence = predicateEvidence(
            predicate,
            announcement: announcement,
            met: true
        )
        let target = Settlement.DiagnosisPredicateTarget.announcement(
            sequence: announcement.announcement.sequence
        )
        return [
            (
                "readiness timeout",
                result(
                    outcome: .timedOut,
                    predicate: predicate,
                    predicateEvidence: metEvidence,
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    history: history,
                    baseline: baseline,
                    deadlineReached: true
                ),
                DiagnosisExpectation(
                    outcome: .timedOut,
                    dispatch: .notApplicable,
                    predicate: .satisfied(target, actual: "Saved"),
                    readiness: .pending(generation: .initial),
                    handoff: .pending(generation: .initial),
                    deadlineReached: true
                )
            ),
            (
                "predicate timeout",
                result(
                    outcome: .timedOut,
                    predicate: predicate,
                    predicateEvidence: predicateEvidence(
                        predicate,
                        announcement: announcement,
                        met: false
                    ),
                    readiness: .established(readiness),
                    handoff: .admitted(handoff),
                    history: history,
                    baseline: baseline,
                    deadlineReached: true
                ),
                DiagnosisExpectation(
                    outcome: .timedOut,
                    dispatch: .notApplicable,
                    predicate: .unmet(target, actual: "Saved"),
                    readiness: .established(generation: .initial, path: .uikitIdle),
                    handoff: .admitted(
                        generation: .initial,
                        observationSequence: observed.sequence
                    ),
                    deadlineReached: true
                )
            ),
            (
                "handoff timeout",
                result(
                    outcome: .timedOut,
                    predicate: predicate,
                    predicateEvidence: metEvidence,
                    readiness: .established(readiness),
                    handoff: .captureRequested(.init(
                        scope: .visible,
                        readinessGeneration: .initial
                    )),
                    history: history,
                    baseline: baseline,
                    deadlineReached: true
                ),
                DiagnosisExpectation(
                    outcome: .timedOut,
                    dispatch: .notApplicable,
                    predicate: .satisfied(target, actual: "Saved"),
                    readiness: .established(generation: .initial, path: .uikitIdle),
                    handoff: .captureRequested(generation: .initial),
                    deadlineReached: true
                )
            ),
        ]
    }

    private func unavailableRows(
        baseline: Observation.SnapshotEvent,
        predicate: Settlement.Predicate,
        history: Observation.EventsSince
    ) -> [DiagnosisRow] {
        [
            (
                "tree unavailable",
                result(
                    outcome: .baselineUnavailable,
                    predicate: predicate,
                    predicateEvidence: Settlement.Predicate.Evidence(predicate: predicate),
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    history: nil,
                    boundary: .unavailable(.unavailable),
                    baseline: baseline
                ),
                DiagnosisExpectation(
                    outcome: .baselineUnavailable,
                    dispatch: .notApplicable,
                    predicate: .pending,
                    readiness: .pending(generation: .initial),
                    handoff: .pending(generation: .initial),
                    deadlineReached: false
                )
            ),
            (
                "unresponsive action",
                result(
                    outcome: .timedOut,
                    trigger: .actionPending(.dismiss),
                    commandTrigger: .action(.dismiss),
                    predicate: predicate,
                    predicateEvidence: Settlement.Predicate.Evidence(predicate: predicate),
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    history: history,
                    baseline: baseline,
                    deadlineReached: true
                ),
                DiagnosisExpectation(
                    outcome: .timedOut,
                    dispatch: .pending,
                    predicate: .pending,
                    readiness: .pending(generation: .initial),
                    handoff: .pending(generation: .initial),
                    deadlineReached: true
                )
            ),
        ]
    }

    private func result(
        outcome: Settlement.Outcome,
        trigger: Settlement.TriggerEvidence = .observation,
        commandTrigger: Settlement.Trigger = .observation,
        predicate: Settlement.Predicate,
        predicateEvidence: Settlement.Predicate.Evidence,
        readiness: Settlement.Readiness.Evidence,
        handoff: Settlement.Handoff.Evidence,
        history: Observation.EventsSince?,
        boundary: Settlement.BoundaryEvidence? = nil,
        baseline: Observation.SnapshotEvent,
        deadlineReached: Bool = false
    ) -> Settlement.Result {
        let command = Settlement.Command(
            trigger: commandTrigger,
            predicate: predicate,
            deadline: .init(instant: .now)
        )
        return Settlement.Result(
            outcome: outcome,
            evidence: Settlement.Evidence(
                command: command,
                boundary: boundary ?? .established(.init(moment: baseline.moment)),
                trigger: trigger,
                predicate: predicateEvidence,
                readiness: readiness,
                handoff: handoff,
                observationHistory: history,
                deadline: .init(
                    deadline: command.deadline,
                    elapsed: 25,
                    reached: deadlineReached
                )
            )
        )
    }

    private func predicateEvidence(
        _ predicate: Settlement.Predicate,
        announcement: Observation.AnnouncementEvent,
        met: Bool
    ) -> Settlement.Predicate.Evidence {
        var evidence = Settlement.Predicate.Evidence(predicate: predicate)
        let request = Settlement.Predicate.EvaluationRequest(
            predicate: predicate,
            target: .announcement(sequence: announcement.announcement.sequence),
            evidence: .announcement(announcement)
        )
        precondition(evidence.schedule(request))
        evidence.record(.init(
            target: request.target,
            result: PredicateEvaluationResult(met: met, actual: "Saved")
        ))
        return evidence
    }

    private func dispatchFailureEvidence(
        _ predicate: Settlement.Predicate
    ) -> Settlement.Predicate.Evidence {
        var evidence = Settlement.Predicate.Evidence(predicate: predicate)
        evidence.recordDispatchFailure()
        return evidence
    }

    private func announcementPredicate() throws -> Settlement.Predicate {
        let authored = AccessibilityPredicate.announcement("Saved")
        return Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
    }

    private func commit(label: String) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: label, heistId: HeistId(rawValue: label.lowercased()))
        )
    }
}

private struct DiagnosisExpectation {
    let outcome: Settlement.Outcome
    let dispatch: Settlement.DiagnosisDispatch
    let predicate: Settlement.DiagnosisPredicateStatus
    let readiness: Settlement.DiagnosisReadiness
    let handoff: Settlement.DiagnosisHandoff
    let deadlineReached: Bool
}

private struct AutomaticTimeoutBoundarySnapshot: Sendable, Equatable {
    var captures = 0
    var admissions = 0
    var dispatches = 0
    var evaluations = 0
    var quiescence = 0
    var finalization = 0
}

/// `NSLock` protects the complete mutable `state` value: work counters and retained sink.
private final class AutomaticTimeoutDiagnosisBoundary: SettlementExecutionBoundary, @unchecked Sendable {
    typealias CapturedObservation = Observation.SnapshotEvent

    private struct State {
        var snapshot = AutomaticTimeoutBoundarySnapshot()
        var sink: Settlement.ExecutionSink?
    }

    private let lock = NSLock()
    private var state = State()
    private let baseline: Observation.SnapshotEvent

    init(baseline: Observation.SnapshotEvent) {
        self.baseline = baseline
    }

    var snapshot: AutomaticTimeoutBoundarySnapshot {
        lock.withLock { state.snapshot }
    }

    @MainActor
    func capture(_: Settlement.Capture.Request) async -> Observation.SnapshotEvent? {
        lock.withLock { state.snapshot.captures += 1 }
        return baseline
    }

    func admit(
        _ capture: Observation.SnapshotEvent,
        for _: Settlement.Capture.Request
    ) async -> Settlement.CaptureAdmissionOutcome {
        lock.withLock { state.snapshot.admissions += 1 }
        return .admitted(capture)
    }

    func events(since _: Observation.Moment) async -> Observation.EventsSince {
        .events([])
    }

    func beginSettlement(_: Settlement.Arming) async {}

    func armObservations(_: Settlement.Arming, sink: Settlement.ExecutionSink) async {
        lock.withLock { state.sink = sink }
    }

    func armAnnouncements(_: Settlement.Arming, sink _: Settlement.ExecutionSink) async {}

    func armReadiness(_: Settlement.Arming, sink _: Settlement.ExecutionSink) async {}

    func armDeadline(_: Settlement.Arming, sink: Settlement.ExecutionSink) async {
        sink.reachDeadline()
    }

    func armObservationEffects(_: Settlement.Arming) async {}

    func quiesceSettlement(_: Settlement.Arming) async {
        lock.withLock { state.snapshot.quiescence += 1 }
    }

    func finalizeSettlement(_: Settlement.Arming) async {
        lock.withLock { state.snapshot.finalization += 1 }
    }

    @MainActor
    func dispatch(
        _: ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult {
        lock.withLock { state.snapshot.dispatches += 1 }
        return .success(payload: .dismiss)
    }

    func evaluate(
        _: Settlement.Predicate.EvaluationRequest
    ) async -> PredicateEvaluationResult {
        lock.withLock { state.snapshot.evaluations += 1 }
        return PredicateEvaluationResult(met: false)
    }

    func elapsed() async -> ElapsedMilliseconds {
        25
    }

    func publishAfterTerminal() {
        let sink = lock.withLock { state.sink }
        sink?.reachDeadline()
        sink?.observe(.snapshot(baseline))
        sink?.observeReadiness(.established(
            path: .uikitIdle,
            observationBoundary: .including(baseline.moment)
        ))
    }
}

/// `NSLock` protects `diagnoses` and `snapshotAtEmission`.
private final class SettlementDiagnosisRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDiagnoses: [Settlement.Diagnosis] = []
    private var recordedSnapshot: AutomaticTimeoutBoundarySnapshot?
    private let boundary: AutomaticTimeoutDiagnosisBoundary

    init(boundary: AutomaticTimeoutDiagnosisBoundary) {
        self.boundary = boundary
    }

    var diagnoses: [Settlement.Diagnosis] {
        lock.withLock { recordedDiagnoses }
    }

    var snapshotAtEmission: AutomaticTimeoutBoundarySnapshot? {
        lock.withLock { recordedSnapshot }
    }

    func record(_ diagnosis: Settlement.Diagnosis) {
        lock.withLock {
            recordedDiagnoses.append(diagnosis)
            recordedSnapshot = boundary.snapshot
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
