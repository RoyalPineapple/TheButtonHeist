#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import TheScore

@MainActor
final class EvidenceContinuityHostedTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await runHeist("EvidenceContinuity.prepare") {
            try DogfoodHome.openScreen("Evidence Continuity")
        }
    }

    override func tearDown() async throws {
        try await runHeist("EvidenceContinuity.cleanup") {
            try DemoNavigation.backToRoot()
        }
        try await super.tearDown()
    }

    func testTransientAppearancePassesOnlyWithActionContinuity() async throws {
        let reference = try await emitTransientEvidence("EvidenceContinuity.emitAppearance")

        let followUp = try await runHeist(
            "EvidenceContinuity.assertAppearance",
            continuity: reference
        ) {
            WaitFor(
                .changed(.elements([.appeared(.label("Transfer complete"))])),
                timeout: 1
            )
        }
        try assertBackdated(
            result: followUp.result,
            reference: reference,
            source: .settledObservation
        )

        let tokenlessFailure = try await expectHeistFailure(
            "EvidenceContinuity.assertAppearanceTokenless"
        ) {
            WaitFor(
                .changed(.elements([.appeared(.label("Transfer complete"))])),
                timeout: 0.2
            )
        }
        XCTAssertNil(try waitStep(in: tokenlessFailure.result).waitEvidence?.continuity)
        XCTAssertNil(try reportContinuity(in: tokenlessFailure.result))
    }

    func testAnnouncementPassesOnlyWithActionContinuity() async throws {
        let reference = try await emitTransientEvidence("EvidenceContinuity.emitAnnouncement")

        let followUp = try await runHeist(
            "EvidenceContinuity.assertAnnouncement",
            continuity: reference
        ) {
            WaitFor(.announcement("Transfer confirmed"), timeout: 1)
        }
        try assertBackdated(
            result: followUp.result,
            reference: reference,
            source: .announcement
        )

        let tokenlessFailure = try await expectHeistFailure(
            "EvidenceContinuity.assertAnnouncementTokenless"
        ) {
            WaitFor(.announcement("Transfer confirmed"), timeout: 0.2)
        }
        XCTAssertNil(try waitStep(in: tokenlessFailure.result).waitEvidence?.continuity)
        XCTAssertNil(try reportContinuity(in: tokenlessFailure.result))
    }

    private func emitTransientEvidence(
        _ path: HeistDefinitionPath
    ) async throws -> EvidenceContinuity.Reference {
        let disappearance = AccessibilityPredicate.changed(
            .elements([.disappeared(.label("Transfer complete"))])
        )
        let action = try await runHeist(path) {
            Activate(.label("Emit transient evidence"))
                .expect(disappearance, timeout: 3)
        }
        XCTAssertFalse(action.result.outputNodes.contains { $0.kind == .wait })
        let actionExpectation = HeistReport.project(result: action.result).outputNodes
            .first(where: { $0.kind == .action })?
            .expectation
        XCTAssertEqual(actionExpectation?.predicate, disappearance)
        XCTAssertEqual(actionExpectation?.met, true)
        return try XCTUnwrap(action.result.evidenceContinuity)
    }

    private func assertBackdated(
        result: HeistResult,
        reference: EvidenceContinuity.Reference,
        source: EvidenceContinuity.PositionSource,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let evidence = try XCTUnwrap(
            try waitStep(in: result).waitEvidence?.continuity,
            file: file,
            line: line
        )
        XCTAssertEqual(evidence.status, .applied(reference: reference), file: file, line: line)
        guard case .backdated(let position)? = evidence.match else {
            return XCTFail("Expected backdated continuity evidence", file: file, line: line)
        }
        XCTAssertEqual(position.source, source, file: file, line: line)
        XCTAssertNotNil(evidence.actionBoundary, file: file, line: line)
        XCTAssertNotNil(evidence.observedThrough, file: file, line: line)

        let projected = try XCTUnwrap(
            try reportContinuity(in: result),
            file: file,
            line: line
        )
        XCTAssertEqual(projected.status, .applied, file: file, line: line)
        guard case .backdated(let reportPosition)? = projected.match else {
            return XCTFail("Expected projected backdated evidence", file: file, line: line)
        }
        XCTAssertEqual(reportPosition, position, file: file, line: line)
    }

    private func waitStep(in result: HeistResult) throws -> HeistExecutionStepResult {
        try XCTUnwrap(result.outputNodes.first(where: { $0.kind == .wait }))
    }

    private func reportContinuity(
        in result: HeistResult
    ) throws -> HeistReport.Continuity? {
        HeistReport.project(result: result).outputNodes
            .first(where: { $0.kind == .wait })?
            .continuity
    }
}
#endif // canImport(UIKit)
