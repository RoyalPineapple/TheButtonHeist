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
            source: "func commit(_ owner: Observation.StoreOwner, _ admission: Observation.Admission) " +
                "async throws { try await owner.commitAdmission(admission) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_commit_ownership",
            path: path
        )))
    }

    @Test
    func streamOwnerMayCommitAnObservationAdmission() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+Settlement.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit(_ owner: Observation.StoreOwner, _ admission: Observation.Admission) " +
                "async throws { try await owner.commitAdmission(admission) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func rawStoreMutationOutsideStoreOwnerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/CompetingStoreOwner.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit(_ store: inout Observation.Store, _ admission: Observation.Admission) throws { try store.commitObservation(admission) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_store_mutation_ownership",
            path: path
        )))
    }

    @Test
    func storeOwnerMayMutateTheObservationStore() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStoreOwner.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit(_ store: inout Observation.Store, _ admission: Observation.Admission) throws { try store.commitObservation(admission) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func settlementExecutionFileMayConstructTheExecutor() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+Execution.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func execute<Boundary>(_ boundary: Boundary) { _ = Settlement.Executor(boundary: boundary) }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingSettlementExecutorOwnerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingSettlement.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func execute<Boundary>(_ boundary: Boundary) { _ = Settlement.Executor(boundary: boundary) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.settlement_executor_ownership",
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
