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
final class EvidenceContinuityFollowUpRegressionTests: XCTestCase {
    func testFollowUpRequestsReplayPostActionTransientAndAnnouncementEvidence() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        fixture.recordAnnouncement("Before action")
        let reference = try fixture.registerBoundary()
        let appearance = fixture.commit(labels: ["Transfer complete"])
        fixture.recordAnnouncement("Transfer confirmed")
        let announcementSequence = fixture.brains.vault.accessibilityNotifications.cursor().sequence
        _ = fixture.commit(labels: [])

        let appeared = try await fixture.execute(
            .changed(.elements([.appeared(.label("Transfer complete"))])),
            continuity: reference
        )
        let announcement = try await fixture.execute(
            .announcement("Transfer confirmed"),
            continuity: reference
        )
        let excluded = try await fixture.execute(
            .announcement("Before action"),
            continuity: reference,
            runtime: fixture.deterministicUnmatchedRuntime(continuity: reference)
        )

        try assertBackdated(
            appeared,
            reference: reference,
            position: .init(
                source: .settledObservation,
                sequence: appearance.sequence.rawValue
            )
        )
        try assertBackdated(
            announcement,
            reference: reference,
            position: .init(source: .announcement, sequence: announcementSequence)
        )
        XCTAssertNotEqual(excluded.outcome, .passed)
        XCTAssertEqual(
            try waitContinuity(in: excluded)?.status,
            .applied(reference: reference)
        )
        XCTAssertNil(try waitContinuity(in: excluded)?.match)
    }

    func testFollowUpRequestPreservesTokenlessAndCurrentEvidenceSemantics() async throws {
        let fixture = makeFixture()
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()
        fixture.recordAnnouncement("Saved")

        let tokenless = try await fixture.execute(
            .announcement("Saved"),
            continuity: nil,
            runtime: fixture.deterministicUnmatchedRuntime(continuity: nil)
        )
        XCTAssertNotEqual(tokenless.outcome, .passed)
        XCTAssertNil(try waitContinuity(in: tokenless))
        XCTAssertNil(try reportContinuity(in: tokenless))

        let live = TheBrains.HeistExecutionRuntime.live(
            fixture.brains,
            continuity: reference
        )
        let currentRuntime = TheBrains.HeistExecutionRuntime(
            execute: live.execute,
            wait: { request in
                fixture.recordAnnouncement("Saved")
                return await live.wait(request)
            },
            selectPredicateCase: live.selectPredicateCase,
            settledEvidence: live.settledEvidence
        )
        let current = try await fixture.execute(
            .announcement("Saved"),
            continuity: reference,
            runtime: currentRuntime
        )

        XCTAssertEqual(current.outcome, .passed)
        XCTAssertEqual(
            try waitContinuity(in: current)?.status,
            .applied(reference: reference)
        )
        XCTAssertEqual(try waitContinuity(in: current)?.match, .current)
        XCTAssertEqual(try reportContinuity(in: current)?.status, .applied)
        XCTAssertEqual(try reportContinuity(in: current)?.match, .current)
    }

    func testUnknownAndStaleFollowUpReferencesReportFallbackWithoutMatches() async throws {
        let unknownFixture = makeFixture()
        defer { unknownFixture.brains.stopSemanticObservation() }
        let unknownReference = EvidenceContinuity.Reference()
        let unknown = try await unknownFixture.execute(
            .changed(.elements([.appeared(.label("Transfer complete"))])),
            continuity: unknownReference,
            runtime: unknownFixture.deterministicUnmatchedRuntime(
                continuity: unknownReference
            )
        )
        try assertFallback(unknown, reason: .unknownReference)

        let staleFixture = makeFixture()
        defer { staleFixture.brains.stopSemanticObservation() }
        let staleReference = try staleFixture.registerBoundary()
        staleFixture.brains.rotateEvidenceContinuityGeneration()
        let stale = try await staleFixture.execute(
            .announcement("Transfer confirmed"),
            continuity: staleReference,
            runtime: staleFixture.deterministicUnmatchedRuntime(continuity: staleReference)
        )
        try assertFallback(stale, reason: .generationMismatch)
    }

    func testInterveningTokenlessRequestDoesNotInvalidateRetainedReference() async throws {
        let fixture = makeFixture(labels: ["Anchor"])
        defer { fixture.brains.stopSemanticObservation() }
        let reference = try fixture.registerBoundary()

        let tokenless = try await fixture.execute(.exists(.label("Anchor")), continuity: nil)
        XCTAssertEqual(tokenless.outcome, .passed)
        XCTAssertNil(try waitContinuity(in: tokenless))

        _ = fixture.commit(labels: ["Anchor", "Transfer complete"])
        _ = fixture.commit(labels: ["Anchor"])
        let followUp = try await fixture.execute(
            .changed(.elements([.appeared(.label("Transfer complete"))])),
            continuity: reference
        )

        XCTAssertEqual(followUp.outcome, .passed)
        XCTAssertEqual(
            try waitContinuity(in: followUp)?.status,
            .applied(reference: reference)
        )
        guard case .backdated? = try waitContinuity(in: followUp)?.match else {
            return XCTFail("Expected retained continuity after an intervening tokenless request")
        }
    }

    private func makeFixture(labels: [String] = []) -> FollowUpFixture {
        let brains = TheBrains(tripwire: TheTripwire(), failureEvidencePolicy: .hierarchy)
        let boundaryEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            screen(labels: labels)
        )
        return FollowUpFixture(
            brains: brains,
            boundaryEvent: boundaryEvent,
            screen: screen(labels:)
        )
    }

    private func screen(labels: [String]) -> InterfaceObservation {
        InterfaceObservation.makeForTests(elements: labels.sorted().map {
            (
                AccessibilityElement.make(
                    label: $0,
                    traits: .staticText,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: $0.lowercased().replacingOccurrences(of: " ", with: "_"))
            )
        })
    }

    private func assertBackdated(
        _ result: HeistResult,
        reference: EvidenceContinuity.Reference,
        position: EvidenceContinuity.Position,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let continuity = try XCTUnwrap(
            try waitContinuity(in: result),
            file: file,
            line: line
        )
        XCTAssertEqual(continuity.status, .applied(reference: reference), file: file, line: line)
        XCTAssertEqual(continuity.match, .backdated(position: position), file: file, line: line)

        let projected = try XCTUnwrap(
            try reportContinuity(in: result),
            file: file,
            line: line
        )
        XCTAssertEqual(projected.status, .applied, file: file, line: line)
        XCTAssertEqual(projected.match, .backdated(position: position), file: file, line: line)
    }

    private func assertFallback(
        _ result: HeistResult,
        reason: EvidenceContinuity.FallbackReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNotEqual(result.outcome, .passed, file: file, line: line)
        let continuity = try XCTUnwrap(
            try waitContinuity(in: result),
            file: file,
            line: line
        )
        XCTAssertEqual(continuity.status, .fallback(reason: reason), file: file, line: line)
        XCTAssertNil(continuity.match, file: file, line: line)

        let projected = try XCTUnwrap(
            try reportContinuity(in: result),
            file: file,
            line: line
        )
        XCTAssertEqual(projected.status, .fallback, file: file, line: line)
        XCTAssertEqual(projected.fallbackReason, reason, file: file, line: line)
        XCTAssertNil(projected.match, file: file, line: line)
    }

    private func waitContinuity(
        in result: HeistResult
    ) throws -> EvidenceContinuity.WaitEvidence? {
        try XCTUnwrap(result.outputNodes.first(where: { $0.kind == .wait }))
            .waitEvidence?
            .continuity
    }

    private func reportContinuity(
        in result: HeistResult
    ) throws -> HeistReport.Continuity? {
        HeistReport.project(result: result).outputNodes
            .first(where: { $0.kind == .wait })?
            .continuity
    }
}

@MainActor
private final class FollowUpFixture {
    let brains: TheBrains
    private let boundaryEvent: SettledObservationEvent
    private let screen: ([String]) -> InterfaceObservation

    init(
        brains: TheBrains,
        boundaryEvent: SettledObservationEvent,
        screen: @escaping ([String]) -> InterfaceObservation
    ) {
        self.brains = brains
        self.boundaryEvent = boundaryEvent
        self.screen = screen
    }

    func registerBoundary() throws -> EvidenceContinuity.Reference {
        let boundary = brains.evidenceContinuityStore.captureBoundary(
            settledCapture: try XCTUnwrap(boundaryEvent.settledCapture),
            notificationCursor: brains.vault.accessibilityNotifications.cursor()
        )
        return try XCTUnwrap(brains.evidenceContinuityStore.register(boundary))
    }

    @discardableResult
    func commit(labels: [String]) -> SettledObservationEvent {
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(screen(labels))
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
            .wait(WaitStep(predicate: predicate, timeout: 5)),
        ])
        let result = await brains.executeHeistPlanForTest(
            plan,
            continuity: continuity,
            runtime: runtime ?? .live(brains, continuity: continuity)
        )
        guard case .heist(let heistResult?) = result.payload else {
            throw FollowUpFixtureError.missingHeistResult
        }
        return heistResult
    }

    func deterministicUnmatchedRuntime(
        continuity: EvidenceContinuity.Reference?
    ) -> TheBrains.HeistExecutionRuntime {
        let live = TheBrains.HeistExecutionRuntime.live(
            brains,
            continuity: continuity
        )
        return TheBrains.HeistExecutionRuntime(
            execute: live.execute,
            wait: { request in
                let admitted = self.brains.admitWaitContinuity(
                    continuity,
                    for: request.step.predicate
                )
                let source: EvidenceContinuity.PositionSource = switch request.step.predicate.core {
                case .announcement:
                    .announcement
                case .changed, .presence, .noChange:
                    .settledObservation
                }
                let actual = "deterministic unmatched evaluation"
                return .timedOut(
                    message: actual,
                    traceEvidence: nil,
                    expectation: ExpectationResult.Unmet(
                        predicate: request.step.predicateExpression,
                        actual: actual
                    ),
                    continuity: admitted.initialEvidence(for: source)
                )
            },
            selectPredicateCase: live.selectPredicateCase,
            settledEvidence: live.settledEvidence
        )
    }
}

private enum FollowUpFixtureError: Error {
    case missingHeistResult
}
#endif // DEBUG
#endif // canImport(UIKit)
