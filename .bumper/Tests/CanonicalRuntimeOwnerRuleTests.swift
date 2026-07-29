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
            source: "func commit(_ owner: TheVault.StateOwner, _ admission: Observation.Admission) " +
                "async { _ = await owner.commitAdmission(admission) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_commit_ownership",
            path: path
        )))
    }

    @Test
    func streamOwnerMayCommitAnObservationAdmission() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+CaptureAdmission.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit(_ owner: TheVault.StateOwner, _ admission: Observation.Admission) " +
                "async { _ = await owner.commitAdmission(admission) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func rawVaultStateMutationOutsideStateOwnerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/CompetingStoreOwner.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit(_ state: inout TheVault.State, _ admission: Observation.Admission) {" +
                " _ = state.commitObservation(admission) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_store_mutation_ownership",
            path: path
        )))
    }

    @Test
    func stateOwnerMayMutateVaultState() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStoreOwner.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit(_ state: inout TheVault.State, _ admission: Observation.Admission) {" +
                " _ = state.commitObservation(admission) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func heistHostMayConstructTheExecutionMachine() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Host.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func execute(_ plan: HeistPlan) throws { _ = try HeistExecution.Machine(plan: plan) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingHeistExecutionMachineOwnerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingHeistExecutor.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func execute(_ plan: HeistPlan) throws { _ = try HeistExecution.Machine(plan: plan) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.heist_execution_machine_ownership",
            path: path
        )))
    }

    @Test
    func canonicalHeistEntryMayConstructTheHost() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecution.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func execute(_ brains: TheBrains) { _ = HeistExecution.Host(brains: brains) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingHeistHostOwnerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingHeistEntry.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func execute(_ brains: TheBrains) { _ = HeistExecution.Host(brains: brains) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.heist_execution_host_ownership",
            path: path
        )))
    }

    @Test
    func safecrackerOwnsContentOffsetDispatch() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+Scroll.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func dispatch(_ scrollView: UIScrollView) { scrollView.setContentOffset(.zero, animated: false) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingRuntimeContentOffsetDispatchIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingScroller.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func dispatch(_ scrollView: UIScrollView) { scrollView.setContentOffset(.zero, animated: false) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.scroll_content_offset_ownership",
            path: path
        )))
    }

    @Test
    func transportWiringMayConsumeTransportEvents() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheGetaway/TransportControlPlane.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func consume(_ transport: ServerTransport) { _ = transport.transportEvents }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func serverTransportMayPublishTransportEvents() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/Server/ServerTransport.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            final class ServerTransport {
                let transportEvents: Events
                init(events: Events) { self.transportEvents = events }
            }
            """
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingTransportEventConsumerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheGetaway/CompetingTransportConsumer.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func consume(_ transport: ServerTransport) { _ = transport.transportEvents }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.transport_event_consumption_ownership",
            path: path
        )))
    }

}
