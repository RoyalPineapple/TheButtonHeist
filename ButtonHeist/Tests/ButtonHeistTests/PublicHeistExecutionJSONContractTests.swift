import ButtonHeistTestSupport
import TheScore
@_spi(ButtonHeistInternals) @testable import ButtonHeist
import XCTest

final class PublicHeistExecutionJSONContractTests: XCTestCase {
    func testCanonicalPublicHeistExecutionFixture() throws {
        let json = try publicHeistExecutionJSON(
            step: HeistResultFixture.warning(message: "heads up")
        )

        try assertPublicHeistJSONContract(
            json,
            equals: PublicHeistActionJSONFixture.warningResponse
        )
    }

    func testFailureContract() throws {
        let json = try publicHeistExecutionJSON(
            step: HeistResultFixture.explicitFailure(message: "stop")
        )
        let node = try XCTUnwrap(try json.object("report").array("nodes").first)

        XCTAssertEqual(try json.string("status"), "partial")
        try assertPublicHeistJSONContract(
            node.object("failure"),
            equals: PublicHeistActionJSONFixture.failure
        )
        try node.assertMissing("evidence")
    }

    func testActionExpectationContract() throws {
        let node = try publicHeistExecutionNodeJSON(
            step: PublicHeistExecutionJSONContractFixture.actionWithExpectation()
        )

        try assertPublicHeistJSONContract(
            node.object("evidence"),
            equals: PublicHeistActionJSONFixture.actionWithExpectation
        )
        try assertPublicHeistJSONContract(
            node.object("expectation"),
            equals: PublicHeistActionJSONFixture.expectation
        )
    }

    func testWaitEvidenceContract() throws {
        let waitEvidenceJSON = try evidence(
            for: PublicHeistExecutionJSONContractFixture.wait()
        )

        try assertPublicHeistJSONContract(
            waitEvidenceJSON,
            equals: PublicHeistActionJSONFixture.wait
        )
        try waitEvidenceJSON.object("wait").assertMissing("continuity")

        let explicitTokenless = try evidence(
            for: PublicHeistExecutionJSONContractFixture.wait(
                continuity: EvidenceContinuity.WaitEvidence(
                    status: .notProvided,
                    match: .current
                )
            )
        )
        try explicitTokenless.object("wait").assertMissing("continuity")
    }

    func testContinuityWaitEvidenceContract() throws {
        let actionBoundary = EvidenceContinuity.Position(source: .settledObservation, sequence: 10)
        let matchPosition = EvidenceContinuity.Position(source: .settledObservation, sequence: 11)
        let observedThrough = EvidenceContinuity.Position(source: .settledObservation, sequence: 12)
        let continuity = EvidenceContinuity.WaitEvidence(
            status: .applied(reference: EvidenceContinuity.Reference()),
            match: .backdated(position: matchPosition),
            actionBoundary: actionBoundary,
            observedThrough: observedThrough
        )
        let wait = try evidence(
            for: PublicHeistExecutionJSONContractFixture.wait(continuity: continuity)
        ).object("wait")
        let projected = try wait.object("continuity")

        XCTAssertEqual(try projected.string("status"), "applied")
        XCTAssertEqual(try projected.object("match").string("kind"), "backdated")
        XCTAssertEqual(try projected.object("match").object("position").string("source"), "settled_observation")
        XCTAssertEqual(try projected.object("match").object("position").int("sequence"), 11)
        XCTAssertEqual(try projected.object("actionBoundary").int("sequence"), 10)
        XCTAssertEqual(try projected.object("observedThrough").int("sequence"), 12)
        try projected.assertMissing("reference")
    }

    func testContinuityFailureJSONReportsEffectiveScopeOrFallbackReasonWithoutMatch() throws {
        let applied = EvidenceContinuity.WaitEvidence(
            status: .applied(reference: EvidenceContinuity.Reference()),
            actionBoundary: .init(source: .announcement, sequence: 20),
            observedThrough: .init(source: .announcement, sequence: 24)
        )
        let appliedJSON = try continuityJSON(for: applied)

        XCTAssertEqual(try appliedJSON.string("status"), "applied")
        XCTAssertEqual(try appliedJSON.object("actionBoundary").int("sequence"), 20)
        XCTAssertEqual(try appliedJSON.object("observedThrough").int("sequence"), 24)
        try appliedJSON.assertMissing("match")

        let fallback = EvidenceContinuity.WaitEvidence(
            status: .fallback(reason: .announcementHistoryUnavailable),
            match: .current
        )
        let fallbackJSON = try continuityJSON(for: fallback)

        XCTAssertEqual(try fallbackJSON.string("status"), "fallback")
        XCTAssertEqual(try fallbackJSON.string("reason"), "announcement_history_unavailable")
        try fallbackJSON.assertMissing("match")
        try fallbackJSON.assertMissing("actionBoundary")
        try fallbackJSON.assertMissing("observedThrough")
    }

    func testCaseSelectionEvidenceContractAndOmittedCases() throws {
        let evidence = try evidence(
            for: PublicHeistExecutionJSONContractFixture.caseSelection(),
            profile: PublicHeistExecutionJSONContractFixture.oneVisibleCaseProfile
        )

        try assertPublicHeistJSONContract(
            evidence,
            equals: PublicHeistControlFlowJSONFixture.caseSelection
        )
    }

    func testForEachStringEvidenceContract() throws {
        let evidence = try evidence(
            for: PublicHeistExecutionJSONContractFixture.forEachString()
        )

        try assertPublicHeistJSONContract(
            evidence,
            equals: PublicHeistControlFlowJSONFixture.forEachString
        )
    }

    func testForEachElementEvidenceContract() throws {
        let evidence = try evidence(
            for: PublicHeistExecutionJSONContractFixture.forEachElement()
        )

        try assertPublicHeistJSONContract(
            evidence,
            equals: PublicHeistControlFlowJSONFixture.forEachElement
        )
    }

    func testRepeatUntilEvidenceContract() throws {
        let evidence = try evidence(
            for: PublicHeistExecutionJSONContractFixture.repeatUntil()
        )

        try assertPublicHeistJSONContract(
            evidence,
            equals: PublicHeistControlFlowJSONFixture.repeatUntil
        )
    }

    func testInvocationEvidenceContract() throws {
        let evidence = try evidence(
            for: PublicHeistExecutionJSONContractFixture.invocation()
        )

        try assertPublicHeistJSONContract(
            evidence,
            equals: PublicHeistActionJSONFixture.invocation
        )
    }

    func testActionEvidenceOmissionContract() throws {
        let node = try publicHeistExecutionNodeJSON(
            step: PublicHeistExecutionJSONContractFixture.actionWithOmissions()
        )
        let result = try node
            .object("evidence")
            .object("action")
            .object("result")

        try assertPublicHeistJSONContract(
            result.object("omitted"),
            equals: PublicHeistActionJSONFixture.omissions
        )
        try result.assertMissing("accessibilityTrace")
        try result.assertMissing("subjectEvidence")
    }

    func testNetDeltaContract() throws {
        let fixture = PublicHeistExecutionJSONContractFixture.netDelta()
        let report = try publicHeistExecutionJSON(step: fixture.step).object("report")
        let before = try XCTUnwrap(fixture.trace.captures.first)
        let after = try XCTUnwrap(fixture.trace.captures.last)

        try assertPublicHeistJSONContract(
            report.object("netDelta"),
            equals: PublicHeistActionJSONFixture.netDelta(
                beforeHash: before.hash,
                afterHash: after.hash
            )
        )
    }

    private func evidence(
        for step: HeistExecutionStepResult,
        profile: ProjectionProfile = .summary
    ) throws -> JSONProbe {
        try publicHeistExecutionNodeJSON(step: step, profile: profile).object("evidence")
    }

    private func continuityJSON(
        for continuity: EvidenceContinuity.WaitEvidence
    ) throws -> JSONProbe {
        let step = HeistResultFixture.wait(
            expectation: ExpectationResult(
                met: false,
                predicate: .exists(.label("Done")),
                actual: "not observed"
            ),
            failure: HeistFailureDetail(
                category: .wait,
                contract: "wait predicate is satisfied",
                observed: "timed out"
            ),
            continuity: continuity
        )
        return try evidence(for: step).object("wait").object("continuity")
    }
}
