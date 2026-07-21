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
        let evidence = try evidence(
            for: PublicHeistExecutionJSONContractFixture.wait()
        )

        try assertPublicHeistJSONContract(
            evidence,
            equals: PublicHeistActionJSONFixture.wait
        )
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
}
