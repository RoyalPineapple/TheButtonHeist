import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Canonical runtime ownership")
struct CanonicalRuntimeOwnerRuleTests {
    @Test
    func observationCommitsOutsideStreamOwnerAreRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/CompetingCommitter.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit() { commitObservation() }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_commit_ownership",
            path: path
        )))
    }

}
