import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Observation stream ownership")
struct ObservationOwnershipRuleTests {
    @Test
    func canonicalStreamOwnsLogConstructionAndPublication() throws {
        let report = try evaluateButtonHeistRules()

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingObservationLogConstructionIsRejected() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingLog.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func makeLog() { _ = SemanticObservationLog() }"
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_log_ownership",
            path: path
        )))
    }

    @Test
    func publicationOutsideObservationStreamIsRejected() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingPublisher.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            func publishDirectly(observationLog: SemanticObservationLog) {
                observationLog.publish(0)
            }
            """
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_publication_ownership",
            path: path
        )))
    }
}
