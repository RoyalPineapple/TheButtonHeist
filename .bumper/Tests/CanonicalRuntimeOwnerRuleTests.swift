import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Canonical runtime ownership")
struct CanonicalRuntimeOwnerRuleTests {
    @Test
    func tripwirePulseOwnerMayConstructDisplayLink() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire+Pulse.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "_ = CADisplayLink(target: target, selector: selector)"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingDisplayLinkClockIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/CompetingPulseClock.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "_ = CADisplayLink(target: target, selector: selector)"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.observation_pulse_clock_ownership",
            path: path
        )))
    }

    @Test
    func observationStreamMaySetPulseDemandAndClaimNotifications() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            func arm(_ tripwire: TheTripwire, _ bus: AccessibilityNotificationBus) {
                tripwire.setObservationPulseDemand(.immediate)
                _ = bus.freezeObservationCycleClaim()
            }
            """
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingPulseDemandOwnerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingPulseDriver.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func arm(_ tripwire: TheTripwire) { tripwire.setObservationPulseDemand(.ambient) }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.observation_pulse_demand_ownership",
            path: path
        )))
    }

    @Test
    func competingNotificationCycleClaimOwnerIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingNotificationConsumer.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func claim(_ bus: AccessibilityNotificationBus) { _ = bus.freezeObservationCycleClaim() }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.notification_cycle_claim_ownership",
            path: path
        )))
    }

    @Test
    func observationCycleMayCaptureLiveState() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+CaptureAdmission.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func capture(_ vault: TheVault) { _ = vault.captureVisibleObservation() }"
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func competingLiveCaptureBypassIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingLiveCapture.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func capture(_ vault: TheVault) { _ = vault.captureVisibleObservation() }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_live_capture_ownership",
            path: path,
            message: .exact("direct live capture bypasses the semantic observation cycle"),
            observed: .exact("vault.captureVisibleObservation()"),
            expectation: .exact(
                "request a semantic observation publication from Observation.Stream"
            )
        )))
    }

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

    @Test
    func machineAcceptsValueOnlyReducerCode() throws {
        let report = try evaluateButtonHeistRules(
            path: machinePath,
            component: .runtime,
            source: """
            extension HeistExecution {
                struct Machine {
                    var inputs: [Input]

                    mutating func advance(_ input: Input) {
                        inputs.append(input)
                    }
                }
            }
            """
        )

        #expect(report.violations.isEmpty)
    }

    @Test(
        "Machine rejects runtime capability ownership",
        arguments: [
            MachineCapabilityMutation(
                source: "import UIKit",
                capability: "UIKit",
                observed: "import UIKit"
            ),
            MachineCapabilityMutation(
                source: "struct State { let vault: TheVault.State }",
                capability: "TheVault",
                observed: "TheVault"
            ),
            MachineCapabilityMutation(
                source: "struct State { let task: Task<Void, Never> }",
                capability: "Task",
                observed: "Task<Void, Never>"
            ),
            MachineCapabilityMutation(
                source: "struct State { let subscription: SemanticObservationSubscription }",
                capability: "SemanticObservationSubscription",
                observed: "SemanticObservationSubscription"
            ),
            MachineCapabilityMutation(
                source: "struct State { let deadline: SemanticObservationDeadline }",
                capability: "SemanticObservationDeadline",
                observed: "SemanticObservationDeadline"
            ),
        ]
    )
    func machineRejectsRuntimeCapabilityOwnership(_ mutation: MachineCapabilityMutation) throws {
        let report = try evaluateButtonHeistRules(
            path: machinePath,
            component: .runtime,
            source: mutation.source
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.heist_execution_machine_purity",
            path: machinePath,
            message: .exact("HeistExecution.Machine owns runtime capability: \(mutation.capability)"),
            observed: .exact(mutation.observed),
            expectation: .exact(
                "keep runtime capabilities in HeistExecution.Host and pass values through typed inputs"
            )
        )))
        #expect(report.violations.first?.location != nil)
    }

}

private let machinePath: RelativeFilePath =
    "ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Reducer.swift"

struct MachineCapabilityMutation: Sendable {
    let source: String
    let capability: String
    let observed: String
}
