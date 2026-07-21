#if canImport(UIKit)
import ButtonHeistSupport
import XCTest
import TheScore
@testable import TheInsideJob

@MainActor
final class TheGetawayTransportWiringTests: XCTestCase {

    func testOlderWiringPausedBeforeBeginCannotReplaceCurrentWiring() async {
        let muscle = TheMuscle(sessionToken: "transport-wiring-token", sessionReleaseTimeout: 1)
        let brains = TheBrains(tripwire: TheTripwire())
        let getaway = TheGetaway(
            muscle: muscle,
            brains: brains,
            identity: .init(
                launchId: "transport-wiring-launch",
                effectiveInstanceId: "transport-wiring-instance",
                tlsActive: false
            )
        )
        let staleTransport = ServerTransport(token: "transport-wiring-token")
        let currentTransport = ServerTransport(token: "transport-wiring-token")
        let enteredStaleBegin = CompletionSignal()
        let releaseStaleBegin = CompletionSignal()
        getaway.pauseBeforeTransportCallbackBeginForTesting = {
            enteredStaleBegin.finish()
            await releaseStaleBegin.wait()
        }

        let staleWiringTask = Task { @MainActor in
            let outcome = await getaway.wireTransport(staleTransport) { _ in }
            guard case .rejected = outcome else { return false }
            return true
        }
        await enteredStaleBegin.wait()
        getaway.pauseBeforeTransportCallbackBeginForTesting = nil

        let currentOutcome = await getaway.wireTransport(currentTransport) { _ in }
        guard case .admitted(let currentAdmission) = currentOutcome else {
            return XCTFail("Expected current wiring to be admitted")
        }
        var staleReachedInstallation = false
        getaway.pauseBeforeTransportCallbackInstallationForTesting = {
            staleReachedInstallation = true
        }

        releaseStaleBegin.finish()
        let staleRejectedWiring = await staleWiringTask.value

        XCTAssertTrue(staleRejectedWiring, "Expected stale begin to reject its wiring attempt")
        XCTAssertFalse(staleReachedInstallation, "Rejected begin must not continue to callback installation")
        let finalGeneration = await muscle.callbackDeliveryGenerationForTesting
        XCTAssertEqual(finalGeneration, currentAdmission.attempt.deliveryGeneration)
        guard case .wired(let wiredTransport) = getaway.transportWiring else {
            return XCTFail("Expected current transport to remain wired, got \(getaway.transportWiring)")
        }
        XCTAssertTrue(wiredTransport.attempt.transport === currentTransport)
        await getaway.tearDown()
        await muscle.tearDown()
    }

    func testTearDownDuringTransportWiringPreventsStaleConsumerCommit() async {
        let muscle = TheMuscle(sessionToken: "transport-wiring-token", sessionReleaseTimeout: 1)
        let brains = TheBrains(tripwire: TheTripwire())
        let getaway = TheGetaway(
            muscle: muscle,
            brains: brains,
            identity: .init(
                launchId: "transport-wiring-launch",
                effectiveInstanceId: "transport-wiring-instance",
                tlsActive: false
            )
        )
        let transport = ServerTransport(token: "transport-wiring-token")
        let enteredInstallation = CompletionSignal()
        let releaseInstallation = CompletionSignal()
        getaway.pauseBeforeTransportCallbackInstallationForTesting = {
            enteredInstallation.finish()
            await releaseInstallation.wait()
        }

        let wiringTask = Task { @MainActor in
            let outcome = await getaway.wireTransport(transport) { _ in }
            guard case .rejected = outcome else { return false }
            return true
        }
        await enteredInstallation.wait()

        await getaway.tearDown()
        releaseInstallation.finish()
        let teardownRejectedWiring = await wiringTask.value
        XCTAssertTrue(teardownRejectedWiring, "Expected teardown to reject stale transport wiring")

        guard case .unwired = getaway.transportWiring else {
            return XCTFail("Expected teardown to reject stale transport wiring, got \(getaway.transportWiring)")
        }
        XCTAssertNil(getaway.transport)
        let callbackGeneration = await muscle.callbackDeliveryGenerationForTesting
        XCTAssertNil(callbackGeneration)
        await muscle.tearDown()
    }

    func testStaleTransportWiringCannotOverwriteNewerCallbacks() async {
        let muscle = TheMuscle(sessionToken: "transport-wiring-token", sessionReleaseTimeout: 1)
        let brains = TheBrains(tripwire: TheTripwire())
        let getaway = TheGetaway(
            muscle: muscle,
            brains: brains,
            identity: .init(
                launchId: "transport-wiring-launch",
                effectiveInstanceId: "transport-wiring-instance",
                tlsActive: false
            )
        )
        let staleTransport = ServerTransport(token: "transport-wiring-token")
        let currentTransport = ServerTransport(token: "transport-wiring-token")
        let enteredStaleInstallation = CompletionSignal()
        let releaseStaleInstallation = CompletionSignal()
        getaway.pauseBeforeTransportCallbackInstallationForTesting = {
            enteredStaleInstallation.finish()
            await releaseStaleInstallation.wait()
        }

        let staleWiringTask = Task { @MainActor in
            let outcome = await getaway.wireTransport(staleTransport) { _ in }
            guard case .rejected = outcome else { return false }
            return true
        }
        await enteredStaleInstallation.wait()
        getaway.pauseBeforeTransportCallbackInstallationForTesting = nil

        let currentOutcome = await getaway.wireTransport(currentTransport) { _ in }
        guard case .admitted(let currentAdmission) = currentOutcome else {
            return XCTFail("Expected current wiring to be admitted")
        }
        let currentGeneration = await muscle.callbackDeliveryGenerationForTesting
        XCTAssertEqual(currentGeneration, currentAdmission.attempt.deliveryGeneration)

        releaseStaleInstallation.finish()
        let staleRejectedWiring = await staleWiringTask.value
        XCTAssertTrue(staleRejectedWiring, "Expected stale wiring to be rejected")

        let finalGeneration = await muscle.callbackDeliveryGenerationForTesting
        XCTAssertEqual(finalGeneration, currentAdmission.attempt.deliveryGeneration)
        guard case .wired(let wiredTransport) = getaway.transportWiring else {
            return XCTFail("Expected current transport to remain wired, got \(getaway.transportWiring)")
        }
        XCTAssertTrue(wiredTransport.attempt.transport === currentTransport)
        await getaway.tearDown()
        await muscle.tearDown()
    }

    func testRejectedTransportWiringDoesNotStartListener() async throws {
        let listeners = TestSocketListenerFactory(port: 49_153)
        let token: SessionAuthToken = "transport-wiring-token"
        let transport = ServerTransport(
            token: token,
            serverDependencies: .init(listenerFactory: listeners.listenerFactory)
        )
        let job = try TheInsideJob(
            token: token.description,
            addressFamily: .ipv4,
            transportFactory: { _, _ in transport }
        )
        let enteredInstallation = CompletionSignal()
        let releaseInstallation = CompletionSignal()
        job.getaway.pauseBeforeTransportCallbackInstallationForTesting = {
            enteredInstallation.finish()
            await releaseInstallation.wait()
        }
        let request = TheInsideJob.InsideJobTransportStartRequest(
            id: UUID(),
            phase: .startup,
            transport: transport,
            idleTimerBaseline: false
        )

        let startTask = Task { @MainActor in
            do {
                _ = try await job.startRuntimeResources(for: request)
                return false
            } catch {
                return true
            }
        }
        await enteredInstallation.wait()
        await job.getaway.tearDown()
        releaseInstallation.finish()

        let rejectedStartup = await startTask.value
        XCTAssertTrue(rejectedStartup, "Expected rejected wiring to cancel startup before listener start")
        XCTAssertEqual(listeners.invocationCount, 0)
        await job.muscle.tearDown()
    }

    func testTransportWiringAttemptIdentityIsDeliveryGeneration() {
        let generation = ClientDelivery.Generation(rawValue: 1)
        let currentAttempt = TheGetaway.TransportWiringAttempt(
            transport: ServerTransport(token: "transport-wiring-token"),
            deliveryGeneration: generation
        )
        let matchingAttempt = TheGetaway.TransportWiringAttempt(
            transport: ServerTransport(token: "transport-wiring-token"),
            deliveryGeneration: generation
        )

        XCTAssertTrue(TheGetaway.TransportWiringState.wiring(currentAttempt).admits(matchingAttempt))
    }
}
#endif // canImport(UIKit)
