import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Settled observation commit ownership")
struct SettledObservationCommitOwnershipRuleTests {
    @Test
    func proofBearingStreamCommitAndLifecycleResetAreValid() throws {
        let report = try evaluateButtonHeistRules()

        #expect(report.violations.isEmpty)
    }

    @Test
    func committedReducerCallRequiresProofBearingStreamFunction() throws {
        let report = try evaluateButtonHeistRules(mutations: [
            .swift(
                semanticObservationStreamPath,
                component: ButtonHeistComponent.runtime,
                source: """
                final class SemanticObservationLog {
                    func publish(_ value: Int) {}
                }
                struct InterfaceObservation {}
                final class SemanticObservationStream {
                    let observationLog = SemanticObservationLog()
                    let stash: TheStash

                    init(stash: TheStash) {
                        self.stash = stash
                    }

                    func publishCommittedObservation(_ observation: InterfaceObservation) {
                        stash.reduceInterfaceGraph()
                        observationLog.publish(0)
                    }
                }
                """
            ),
        ])

        #expect(violations(in: report).count == 1)
        #expect(report.contains(ViolationMatcher(
            id: ruleID,
            path: semanticObservationStreamPath
        )))
    }

    @Test
    func graphMutationOutsideReducerIsRejected() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/TheBrains/GraphBypass.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            extension TheStash {
                func bypassCommit() {
                    interfaceTree = 2
                }
            }
            """
        )

        #expect(violations(in: report).count == 1)
        #expect(report.contains(ViolationMatcher(id: ruleID, path: path)))
    }

    @Test
    func reducerMustActuallyMutateGraphTruth() throws {
        let report = try evaluateButtonHeistRules(mutations: [
            .swift(
                interfaceStatePath,
                component: ButtonHeistComponent.runtime,
                source: """
                final class TheStash {
                    var interfaceTree = 0

                    func reduceInterfaceGraph() {}

                    func clearInterfaceForLifecycleReset() {
                        interfaceTree = 0
                    }
                }
                """
            ),
        ])

        #expect(violations(in: report).count == 1)
        #expect(report.contains(ViolationMatcher(id: ruleID, path: interfaceStatePath)))
    }

    @Test
    func secondReducerEntryIsRejected() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/TheBrains/SecondCommit.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            func commitAgain(stash: TheStash) {
                stash.reduceInterfaceGraph()
            }
            """
        )

        #expect(violations(in: report).count == 2)
        #expect(report.contains(ViolationMatcher(id: ruleID, path: path)))
        #expect(report.contains(ViolationMatcher(id: ruleID, path: semanticObservationStreamPath)))
    }

    private func violations(in report: RuleReport) -> [RuleViolation] {
        report.violations.filter { $0.rule.id == ruleID }
    }

    private let ruleID: RuleID = "buttonheist.settled_observation_commit_ownership"
    private let semanticObservationStreamPath: RelativeFilePath =
        "ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream.swift"
    private let interfaceStatePath: RelativeFilePath =
        "ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+InterfaceState.swift"
}
