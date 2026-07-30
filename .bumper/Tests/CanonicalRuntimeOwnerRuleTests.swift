import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Canonical runtime ownership")
struct CanonicalRuntimeOwnerRuleTests {
    @Test
    func observationStreamMayOwnTheObservationCycle() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            func arm(_ tripwire: TheTripwire, _ bus: AccessibilityNotificationBus) {
                tripwire.observePulses { _ in }
                tripwire.setObservationPulseDemand(.immediate)
                tripwire.stopObservingPulses()
                _ = bus.freezeObservationCycleClaim()
            }
            """
        )

        #expect(report.violations.isEmpty)
    }

    @Test(arguments: [
        "freezeObservationCycleClaim",
        "observePulses",
        "setObservationPulseDemand",
        "stopObservingPulses",
    ])
    func competingObservationCycleOwnerIsRejected(_ memberName: String) throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingObservationCycleOwner.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func compete(_ owner: Owner) { owner.\(memberName)() }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_cycle_ownership",
            path: path,
            observed: .exact("owner.\(memberName)")
        )))
    }

    @Test("Canonical runtime owner is accepted", arguments: runtimeOwnershipFixtures)
    func canonicalRuntimeOwnerIsAccepted(_ fixture: RuntimeOwnershipFixture) throws {
        let report = try evaluateButtonHeistRules(
            path: fixture.ownerPath,
            component: .runtime,
            source: fixture.source
        )

        #expect(report.violations.isEmpty)
    }

    @Test("Competing runtime owner is rejected", arguments: runtimeOwnershipFixtures)
    func competingRuntimeOwnerIsRejected(_ fixture: RuntimeOwnershipFixture) throws {
        let report = try evaluateButtonHeistRules(
            path: fixture.competingPath,
            component: .runtime,
            source: fixture.source
        )

        #expect(report.contains(ViolationMatcher(id: fixture.id, path: fixture.competingPath)))
    }

    @Test
    func visibleObservationSourceReferenceDoesNotPerformRawCapture() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            let source: TheVault.VisibleObservationSource =
                TheVault.captureVisibleObservation
            """
        )

        #expect(report.violations.isEmpty)
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

private let runtimeOwnershipFixtures: [RuntimeOwnershipFixture] = [
    RuntimeOwnershipFixture(
        id: "buttonheist.observation_history_construction_ownership",
        ownerPath: "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStore.swift",
        competingPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingObservationHistory.swift",
        source: "_ = Observation.History(retentionLimit: 256)"
    ),
    RuntimeOwnershipFixture(
        id: "buttonheist.semantic_observation_commit_ownership",
        ownerPath: "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+CaptureAdmission.swift",
        competingPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingObservationCommit.swift",
        source: """
        func commit(_ state: inout TheVault.State, _ admission: Observation.Admission) {
            _ = state.commitObservation(admission)
        }
        """
    ),
    RuntimeOwnershipFixture(
        id: "buttonheist.semantic_observation_live_capture_ownership",
        ownerPath: "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+CaptureAdmission.swift",
        competingPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingVisibleObservationCapture.swift",
        source: "func capture(_ vault: TheVault) { _ = vault.captureVisibleObservation() }"
    ),
    RuntimeOwnershipFixture(
        id: "buttonheist.observation_pulse_clock_ownership",
        ownerPath: "ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire+Pulse.swift",
        competingPath: "ButtonHeist/Sources/TheInsideJob/TheVault/CompetingPulseClock.swift",
        source: "_ = CADisplayLink(target: target, selector: selector)"
    ),
    RuntimeOwnershipFixture(
        id: "buttonheist.heist_execution_machine_ownership",
        ownerPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Host.swift",
        competingPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingHeistExecutor.swift",
        source: "func execute(_ plan: HeistPlan) throws { _ = try HeistExecution.Machine(plan: plan) }"
    ),
    RuntimeOwnershipFixture(
        id: "buttonheist.heist_execution_host_ownership",
        ownerPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecution.swift",
        competingPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingHeistEntry.swift",
        source: "func execute(_ brains: TheBrains) { _ = HeistExecution.Host(brains: brains) }"
    ),
    RuntimeOwnershipFixture(
        id: "buttonheist.heist_action_dispatch_ownership",
        ownerPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Host.swift",
        competingPath: "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingActionExecutor.swift",
        source: "func dispatch(_ brains: TheBrains, _ command: Command) async { _ = await brains.dispatchRuntimeAction(command) }"
    ),
]

struct RuntimeOwnershipFixture: Sendable {
    let id: RuleID
    let ownerPath: RelativeFilePath
    let competingPath: RelativeFilePath
    let source: String
}
