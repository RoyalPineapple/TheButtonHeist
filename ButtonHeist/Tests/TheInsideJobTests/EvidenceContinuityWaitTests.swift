#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class EvidenceContinuityWaitTests: XCTestCase {
    func testAppearedWaitUsesEarliestRetainedPrefixAndReportsBackdatedMatch() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        let firstAppearance = fixture.commit(labels: ["Ready"])
        _ = fixture.commit(labels: [])
        _ = fixture.commit(labels: ["Ready"])
        let final = fixture.commit(labels: [])

        let result = try await fixture.execute(
            .changed(.elements([.appeared(.label("Ready"))])),
            continuity: reference
        )
        let evidence = try XCTUnwrap(result.steps.first?.waitEvidence?.continuity)

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertEqual(evidence.status, .applied(reference: reference))
        XCTAssertEqual(
            evidence.match,
            .backdated(position: observationPosition(firstAppearance))
        )
        XCTAssertEqual(evidence.actionBoundary, observationPosition(fixture.boundaryEvent))
        XCTAssertEqual(evidence.observedThrough, observationPosition(final))
    }

    func testRetainedDisappearanceAndUpdateCanSatisfyLaterWaits() async throws {
        let cases: [(AccessibilityPredicate, [String: String], [String: String])] = [
            (
                .changed(.elements([.disappeared(.label("Loading"))])),
                ["Loading": ""],
                [:]
            ),
            (
                .changed(.elements([.updated(
                    .label("Volume"),
                    .value(before: "2", after: "3")
                )])),
                ["Volume": "2"],
                ["Volume": "3"]
            ),
        ]

        for (predicate, baseline, changed) in cases {
            let fixture = makeFixture(values: baseline)
            defer { fixture.brains.stopSemanticObservation() }
            let reference = try fixture.registerBoundary()
            let matchingEvent = fixture.commit(values: changed)

            let result = try await fixture.execute(predicate, continuity: reference)
            let evidence = try XCTUnwrap(result.steps.first?.waitEvidence?.continuity)

            XCTAssertEqual(result.outcome, .passed)
            XCTAssertEqual(
                evidence.match,
                .backdated(position: observationPosition(matchingEvent))
            )
        }
    }

    func testEvidenceAtOrBeforeActionBoundaryCannotSatisfyAppearedWait() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        _ = fixture.commit(labels: ["Ready"])
        let reference = try fixture.registerBoundary(atLatestObservation: true)
        let final = fixture.commit(labels: [])

        let result = try await fixture.execute(
            .changed(.elements([.appeared(.label("Ready"))])),
            continuity: reference
        )
        let evidence = try XCTUnwrap(result.steps.first?.waitEvidence?.continuity)

        XCTAssertNotEqual(result.outcome, .passed)
        XCTAssertEqual(evidence.status, .applied(reference: reference))
        XCTAssertNil(evidence.match)
        XCTAssertEqual(evidence.observedThrough, observationPosition(final))
    }

    func testAnnouncementAfterActionMatchesWhilePreActionAnnouncementIsExcluded() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        fixture.recordAnnouncement("Before action")
        let reference = try fixture.registerBoundary(notificationAtLatest: true)
        fixture.recordAnnouncement("Saved")
        let savedSequence = fixture.brains.vault.accessibilityNotifications.cursor().sequence

        let result = try await fixture.execute(.announcement("Saved"), continuity: reference)
        let evidence = try XCTUnwrap(result.steps.first?.waitEvidence?.continuity)

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertEqual(evidence.status, .applied(reference: reference))
        XCTAssertEqual(
            evidence.match,
            .backdated(position: EvidenceContinuity.Position(
                source: .announcement,
                sequence: savedSequence
            ))
        )

        let excluded = try await fixture.execute(
            .announcement("Before action"),
            continuity: reference
        )
        XCTAssertNotEqual(excluded.outcome, .passed)
        XCTAssertNil(excluded.steps.first?.waitEvidence?.continuity?.match)
    }

    func testCurrentAnnouncementWinsWhenRetainedBackdatedAnnouncementAlsoMatches() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        fixture.recordAnnouncement("Saved")
        let live = TheBrains.HeistExecutionRuntime.live(
            fixture.brains,
            continuity: reference
        )
        let runtime = TheBrains.HeistExecutionRuntime(
            execute: live.execute,
            wait: { request in
                fixture.recordAnnouncement("Saved")
                return await live.wait(request)
            },
            selectPredicateCase: live.selectPredicateCase,
            settledEvidence: live.settledEvidence
        )

        let result = try await fixture.execute(
            .announcement("Saved"),
            continuity: reference,
            runtime: runtime
        )
        let evidence = try XCTUnwrap(result.steps.first?.waitEvidence?.continuity)
        let diagnostics = fixture.brains.interactionCoordinator.evidenceContinuityDiagnostics

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertEqual(evidence.status, .applied(reference: reference))
        XCTAssertEqual(evidence.match, .current)
        XCTAssertEqual(diagnostics.recordedOutcomes, 1)
        XCTAssertEqual(diagnostics.backdatedMatches, 0)
    }

    func testObservationEvictionFallsBackWithoutBlockingRetainedAnnouncementChannel() async throws {
        let fixture = makeFixture(observationRetentionLimit: 1)
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary(notificationAtLatest: true)
        fixture.recordAnnouncement("Saved")
        _ = fixture.commit(labels: ["Ready"])
        _ = fixture.commit(labels: [])

        let announcement = try await fixture.execute(.announcement("Saved"), continuity: reference)
        XCTAssertEqual(announcement.outcome, .passed)
        XCTAssertEqual(
            announcement.steps.first?.waitEvidence?.continuity?.status,
            .applied(reference: reference)
        )

        let appeared = try await fixture.execute(
            .changed(.elements([.appeared(.label("Ready"))])),
            continuity: reference
        )
        XCTAssertNotEqual(appeared.outcome, .passed)
        XCTAssertEqual(
            appeared.steps.first?.waitEvidence?.continuity?.status,
            .fallback(reason: .observationHistoryUnavailable)
        )
        XCTAssertNil(appeared.steps.first?.waitEvidence?.continuity?.match)
    }

    func testCandidateLosingLineageRecordsFinalFallbackOutcomeExactlyOnce() async throws {
        let fixture = makeFixture(observationRetentionLimit: 1)
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        let step = try resolvedWait(WaitStep(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            timeout: .milliseconds(1)
        ))
        let continuity = fixture.brains.admitWaitContinuity(reference, for: step.predicate)
        guard case .candidate = continuity else {
            return XCTFail("Expected continuity admission before retained lineage eviction")
        }
        _ = fixture.commit(labels: ["Ready"])
        _ = fixture.commit(labels: [])

        let result = await fixture.brains.interactionCoordinator.waitForPredicate(
            step,
            continuity: continuity
        )
        let diagnostics = fixture.brains.interactionCoordinator.evidenceContinuityDiagnostics

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(
            result.continuity?.status,
            .fallback(reason: .observationHistoryUnavailable)
        )
        XCTAssertEqual(diagnostics.recordedOutcomes, 1)
        XCTAssertEqual(diagnostics.admittedReferences, 1)
        XCTAssertEqual(diagnostics.observationHistoryFallbacks, 1)
    }

    func testPresenceWaitRemainsCurrentOnlyWhenContinuityIsSupplied() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        _ = fixture.commit(labels: ["Ready"])
        _ = fixture.commit(labels: [])

        let result = try await fixture.execute(.exists(.label("Ready")), continuity: reference)

        XCTAssertNotEqual(result.outcome, .passed)
        XCTAssertEqual(
            result.steps.first?.waitEvidence?.continuity?.status,
            .ineligible
        )
        XCTAssertNil(result.steps.first?.waitEvidence?.continuity?.match)
    }

    func testExplicitBaselineTakesPrecedenceOverMatchingRetainedEvidence() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        let explicitBaselineEvent = fixture.commit(labels: ["Ready"])
        _ = fixture.commit(labels: [])
        let step = try resolvedWait(WaitStep(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            timeout: .milliseconds(1)
        ))
        let continuity = fixture.brains.admitWaitContinuity(reference, for: step.predicate)

        let result = await fixture.brains.interactionCoordinator.waitForPredicate(
            step,
            changeBaseline: .supplied(try XCTUnwrap(explicitBaselineEvent.settledCapture)),
            continuity: continuity
        )

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(result.continuity?.status, .ineligible)
        XCTAssertNil(result.continuity?.match)
    }

    func testNoChangeOutcomeMatchesTokenlessRouteAndCannotBackdate() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        _ = fixture.commit(labels: [])
        let baseline = try XCTUnwrap(fixture.boundaryEvent.settledCapture)
        let step = try resolvedWait(WaitStep(
            predicate: .noChange,
            timeout: .milliseconds(1)
        ))
        let continuity = fixture.brains.admitWaitContinuity(reference, for: step.predicate)

        let supplied = await fixture.brains.interactionCoordinator.waitForPredicate(
            step,
            changeBaseline: .supplied(baseline),
            continuity: continuity
        )
        let tokenless = await fixture.brains.interactionCoordinator.waitForPredicate(
            step,
            changeBaseline: .supplied(baseline)
        )

        XCTAssertEqual(
            supplied.outcome.actionResult.outcome.isSuccess,
            tokenless.outcome.actionResult.outcome.isSuccess
        )
        XCTAssertEqual(supplied.outcome.expectation, tokenless.outcome.expectation)
        XCTAssertEqual(supplied.continuity?.status, .ineligible)
        XCTAssertEqual(supplied.continuity?.match, .current)
        XCTAssertNil(tokenless.continuity)
    }

    func testBackdatedEvaluationPerformsNoScheduledWaitOrActionEffects() async throws {
        let workSpy = ContinuityWorkSpy()
        let fixture = makeFixture(workSpy: workSpy)
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        _ = fixture.commit(labels: ["Ready"])
        let stream = fixture.brains.vault.semanticObservationStream
        let cursorBeforeWait = stream.latestCommittedObservationCursor(scope: .visible)
        let live = TheBrains.HeistExecutionRuntime.live(
            fixture.brains,
            continuity: reference
        )
        let runtime = TheBrains.HeistExecutionRuntime(
            execute: { command, scope in
                workSpy.recordActionDispatch()
                return await live.execute(command, scope)
            },
            wait: live.wait,
            selectPredicateCase: live.selectPredicateCase,
            settledEvidence: live.settledEvidence
        )

        let result = try await fixture.execute(
            .changed(.elements([.appeared(.label("Ready"))])),
            continuity: reference,
            runtime: runtime
        )
        let diagnostics = fixture.brains.interactionCoordinator.evidenceContinuityDiagnostics

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertTrue(workSpy.scheduledEffects.isEmpty)
        XCTAssertEqual(workSpy.captureCount, 0)
        XCTAssertEqual(workSpy.settlementCount, 0)
        XCTAssertEqual(workSpy.actionDispatchCount, 0)
        XCTAssertEqual(stream.latestCommittedObservationCursor(scope: .visible), cursorBeforeWait)
        XCTAssertEqual(diagnostics.recordedOutcomes, 1)
        XCTAssertEqual(diagnostics.admittedReferences, 1)
        XCTAssertEqual(diagnostics.backdatedMatches, 1)
        XCTAssertEqual(diagnostics.observationHistoryFallbacks, 0)
    }

    func testTokenlessWaitKeepsContinuityEvidenceAbsent() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        _ = fixture.commit(labels: ["Ready"])
        _ = fixture.commit(labels: [])

        let result = try await fixture.execute(
            .changed(.elements([.appeared(.label("Ready"))])),
            continuity: nil
        )

        XCTAssertNotEqual(result.outcome, .passed)
        XCTAssertNil(result.steps.first?.waitEvidence?.continuity)
    }

    private func makeFixture(
        values: [String: String] = [:],
        observationRetentionLimit: Int = SemanticObservationStore.defaultRetentionLimit,
        workSpy: ContinuityWorkSpy? = nil
    ) -> ContinuityWaitFixture {
        let brains = TheBrains(
            tripwire: TheTripwire(),
            failureEvidencePolicy: .hierarchy,
            visibleObservationSource: { vault in
                workSpy?.capture(vault)
            }
        )
        brains.vault.semanticObservationStream.observationStore = SemanticObservationStore(
            retentionLimit: observationRetentionLimit
        )
        if let workSpy {
            brains.interactionCoordinator.observePredicateWaitScheduledEffects(
                workSpy.recordScheduledEffect
            )
            brains.vault.semanticObservationStream.settleVisibleObservation = { vault, _, _, baseline, _ in
                workSpy.recordSettlement()
                let observation = vault.latestObservation
                return SettleSession.Result(
                    outcome: .settled(timeMs: 0),
                    events: [],
                    finalObservation: SettleSessionFinalObservation(observation: observation),
                    elementsByKey: [:],
                    tripwireSignal: baseline
                )
            }
        }
        let boundaryEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            screen(values: values)
        )
        return ContinuityWaitFixture(
            brains: brains,
            boundaryEvent: boundaryEvent,
            screen: screen(values:)
        )
    }

    private func screen(values: [String: String]) -> InterfaceObservation {
        InterfaceObservation.makeForTests(elements: values.sorted(by: { $0.key < $1.key }).map {
            (
                AccessibilityElement.make(
                    label: $0.key,
                    value: $0.value.isEmpty ? nil : $0.value,
                    traits: .staticText,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: $0.key.lowercased().replacingOccurrences(of: " ", with: "_"))
            )
        })
    }

    private func observationPosition(_ event: SettledObservationEvent) -> EvidenceContinuity.Position {
        EvidenceContinuity.Position(
            source: .settledObservation,
            sequence: event.sequence.rawValue
        )
    }
}

@MainActor
private final class ContinuityWorkSpy {
    private(set) var scheduledEffects: [PredicateWait.ScheduledEffect] = []
    private(set) var captureCount = 0
    private(set) var settlementCount = 0
    private(set) var actionDispatchCount = 0

    func recordScheduledEffect(_ effect: PredicateWait.ScheduledEffect) {
        scheduledEffects.append(effect)
    }

    func capture(_ vault: TheVault) -> InterfaceObservation? {
        captureCount += 1
        return vault.latestObservation
    }

    func recordSettlement() {
        settlementCount += 1
    }

    func recordActionDispatch() {
        actionDispatchCount += 1
    }
}

@MainActor
private final class ContinuityWaitFixture {
    let brains: TheBrains
    private(set) var boundaryEvent: SettledObservationEvent
    private let screen: ([String: String]) -> InterfaceObservation

    init(
        brains: TheBrains,
        boundaryEvent: SettledObservationEvent,
        screen: @escaping ([String: String]) -> InterfaceObservation
    ) {
        self.brains = brains
        self.boundaryEvent = boundaryEvent
        self.screen = screen
    }

    func registerBoundary(
        atLatestObservation: Bool = false,
        notificationAtLatest: Bool = false
    ) throws -> EvidenceContinuity.Reference {
        if atLatestObservation {
            boundaryEvent = try XCTUnwrap(
                brains.vault.semanticObservationStream.latestCommittedEvent
            )
        }
        let settledCapture = try XCTUnwrap(boundaryEvent.settledCapture)
        let notificationCursor = notificationAtLatest
            ? brains.vault.accessibilityNotifications.cursor()
            : .origin
        let boundary = brains.evidenceContinuityStore.captureBoundary(
            settledCapture: settledCapture,
            notificationCursor: notificationCursor
        )
        return try XCTUnwrap(brains.evidenceContinuityStore.register(boundary))
    }

    @discardableResult
    func commit(labels: [String]) -> SettledObservationEvent {
        commit(values: Dictionary(uniqueKeysWithValues: labels.map { ($0, "") }))
    }

    @discardableResult
    func commit(values: [String: String]) -> SettledObservationEvent {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            screen(values)
        )
    }

    func recordAnnouncement(_ text: String) {
        brains.vault.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload(text as NSString),
            associatedElement: .none
        )
    }

    func execute(
        _ predicate: AccessibilityPredicate,
        continuity: EvidenceContinuity.Reference?,
        runtime: TheBrains.HeistExecutionRuntime? = nil
    ) async throws -> HeistResult {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(predicate: predicate, timeout: .milliseconds(1))),
        ])
        let result = await brains.executeHeistPlanForTest(
            plan,
            continuity: continuity,
            runtime: runtime ?? .live(brains, continuity: continuity)
        )
        guard case .heist(let heistResult?) = result.payload else {
            throw ContinuityWaitFixtureError.missingHeistResult
        }
        return heistResult
    }
}

private enum ContinuityWaitFixtureError: Error {
    case missingHeistResult
}

#endif // DEBUG
#endif // canImport(UIKit)
