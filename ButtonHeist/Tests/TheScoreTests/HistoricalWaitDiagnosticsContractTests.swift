import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HistoricalWaitDiagnosticsContractTests {
    @Test func testHistoricalWaitDiagnosticsAreTypedBoundedAndOmittedByDefault() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(predicate: .exists(.label("Ticket saved.")), timeout: 1)),
        ])
        let tokenless = HeistPlanRun(plan: plan)
        let activated = HeistPlanRun(
            plan: plan,
            historicalWaitDiagnostics: .predicateMismatches
        )
        let candidate = try #require(HistoricalWaitDiagnostics.SemanticCandidate(
            label: "Ticket saved., Dismiss",
            value: nil,
            hint: "Dismiss confirmation",
            traits: [.staticText]
        ))
        let provenance = try #require(HistoricalWaitDiagnostics.CandidateProvenance(
            firstObservationSequence: 12,
            lastObservationSequence: 16
        ))
        let mismatch = HistoricalWaitDiagnostics.PredicateMismatch(
            exactPredicate: .exists(.label("Ticket saved.")),
            candidate: candidate,
            provenance: provenance
        )
        let bounded = try #require(HistoricalWaitDiagnostics.Evidence(
            predicateMismatches: Array(
                repeating: mismatch,
                count: HistoricalWaitDiagnostics.Evidence.maximumCandidateCount
            )
        ))

        requireSendable(HistoricalWaitDiagnostics.Evidence.self)
        #expect(try roundTrip(bounded) == bounded)
        #expect(try jsonKeys(candidate) == ["hint", "label", "traits"])
        #expect(HistoricalWaitDiagnostics.SemanticCandidate(
            label: nil,
            value: nil,
            hint: nil,
            traits: []
        ) == nil)
        #expect(try jsonKeys(tokenless) == ["argument", "plan"])
        #expect(try jsonKeys(activated) == ["argument", "historicalWaitDiagnostics", "plan"])
        #expect(tokenless.historicalWaitDiagnostics == nil)
        #expect(activated.historicalWaitDiagnostics == .predicateMismatches)
        #expect(HistoricalWaitDiagnostics.Evidence(
            predicateMismatches: Array(
                repeating: mismatch,
                count: HistoricalWaitDiagnostics.Evidence.maximumCandidateCount + 1
            )
        ) == nil)

        let oversized = try JSONEncoder().encode([
            "predicateMismatches": Array(
                repeating: mismatch,
                count: HistoricalWaitDiagnostics.Evidence.maximumCandidateCount + 1
            ),
        ])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HistoricalWaitDiagnostics.Evidence.self, from: oversized)
        }
    }

    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private func jsonKeys<Value: Encodable>(_ value: Value) throws -> Set<String> {
        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
