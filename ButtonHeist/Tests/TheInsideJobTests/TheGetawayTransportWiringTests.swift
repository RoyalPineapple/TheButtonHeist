#if canImport(UIKit)
import ButtonHeistSupport
import os
import XCTest
import TheScore
@testable import TheInsideJob

@MainActor
final class TheGetawayTransportWiringTests: XCTestCase {

    func testRequestSupersededAfterAdmissionDoesNotEnterAvailableUIQueue() async throws {
        try await assertRequestSupersededAfterAdmissionCannotSubmitUIWork(.available)
    }

    func testRequestSupersededAfterAdmissionCannotRejectAgainstCurrentClient() async throws {
        try await assertRequestSupersededAfterAdmissionCannotSubmitUIWork(.saturated)
    }

    private func assertRequestSupersededAfterAdmissionCannotSubmitUIWork(
        _ queueCapacity: UIQueueCapacity
    ) async throws {
        let clientId = 7
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
        let staleOutcome = await getaway.wireTransport(staleTransport) { _ in }
        guard case .admitted(let staleAdmission) = staleOutcome else {
            return XCTFail("Expected initial wiring to be admitted")
        }
        let staleGeneration = staleAdmission.attempt.deliveryGeneration
        await getaway.observeTransportEvent(
            .clientConnected(clientId: clientId, remoteAddress: "127.0.0.1"),
            generation: staleGeneration,
            onBacklogOverflow: { _ in }
        )
        let stalePipeline = try XCTUnwrap(getaway.clientRequestPipelines[clientId])
        try await authenticate(
            clientId: clientId,
            muscle: muscle,
            generation: staleGeneration
        )

        let staleRequestAdmitted = CompletionSignal()
        let releaseStaleRequest = CompletionSignal()
        let staleRequestCompleted = CompletionSignal()
        getaway.pauseAfterClientRequestAdmissionForTesting = { generation in
            guard generation == staleGeneration else { return }
            staleRequestAdmitted.finish()
            await releaseStaleRequest.wait()
        }
        getaway.observeClientRequestCompletionForTesting = { generation in
            guard generation == staleGeneration else { return }
            staleRequestCompleted.finish()
        }
        let staleResponses = TransportResponseSink()
        let staleUIRequest = try JSONEncoder().encode(RequestEnvelope(
            requestId: "stale-ui",
            message: .getPasteboard
        ))
        await getaway.observeTransportEvent(
            .dataReceived(clientId: clientId, data: staleUIRequest, respond: staleResponses.respond),
            generation: staleGeneration,
            onBacklogOverflow: { _ in }
        )
        await staleRequestAdmitted.wait()

        let blockingRequestEntered = CompletionSignal()
        let releaseBlockingRequest = CompletionSignal()
        XCTAssertEqual(brains.submitTransportRequest(clientId: 1_000) {
            blockingRequestEntered.finish()
            await releaseBlockingRequest.wait()
        }, .accepted)
        await blockingRequestEntered.wait()
        saturateUIQueueIfNeeded(queueCapacity, brains: brains)

        getaway.pauseAfterClientRequestAdmissionForTesting = nil
        let currentOutcome = await getaway.wireTransport(currentTransport) { _ in }
        guard case .admitted(let currentAdmission) = currentOutcome else {
            releaseBlockingRequest.finish()
            await brains.stopInteractionRequests()
            return XCTFail("Expected replacement wiring to be admitted")
        }
        let currentGeneration = currentAdmission.attempt.deliveryGeneration
        releaseStaleRequest.finish()
        await staleRequestCompleted.wait()
        getaway.observeClientRequestCompletionForTesting = nil

        XCTAssertEqual(
            brains.interactionRequestSnapshot,
            .init(
                phase: .running,
                pendingDepth: queueCapacity.expectedPendingDepth,
                capacity: InteractionRequestExecutor.maximumPendingRequests
            )
        )
        XCTAssertEqual(staleResponses.count, 0)
        let currentPipeline = getaway.clientRequestPipelines[clientId]
        XCTAssertTrue(currentPipeline === stalePipeline)

        if currentPipeline === stalePipeline {
            try await assertCurrentControlDelivery(
                clientId: clientId,
                getaway: getaway,
                generation: currentGeneration
            )
        }

        releaseBlockingRequest.finish()
        await brains.stopInteractionRequests()
        await getaway.tearDown()
        await muscle.tearDown()
    }

    private func saturateUIQueueIfNeeded(
        _ queueCapacity: UIQueueCapacity,
        brains: TheBrains
    ) {
        guard queueCapacity == .saturated else { return }
        for index in 0..<InteractionRequestExecutor.maximumPendingRequests {
            XCTAssertEqual(
                brains.submitTransportRequest(clientId: 1_001 + index) {},
                .accepted
            )
        }
    }

    private func authenticate(
        clientId: Int,
        muscle: TheMuscle,
        generation: ClientDelivery.Generation
    ) async throws {
        let respond: SocketResponseHandler = { _ in .delivered }
        let hello = try JSONEncoder().encode(RequestEnvelope(message: .clientHello))
        _ = await muscle.admitClientMessage(
            clientId,
            data: hello,
            respond: respond,
            generation: generation
        )
        let authentication = try JSONEncoder().encode(RequestEnvelope(message: .authenticate(
            AuthenticatePayload(token: "transport-wiring-token", driverId: nil)
        )))
        _ = await muscle.admitClientMessage(
            clientId,
            data: authentication,
            respond: respond,
            generation: generation
        )
    }

    private func assertCurrentControlDelivery(
        clientId: Int,
        getaway: TheGetaway,
        generation: ClientDelivery.Generation
    ) async throws {
        let responses = TransportResponseSink()
        let ping = try JSONEncoder().encode(RequestEnvelope(
            requestId: "current-ping",
            message: .ping
        ))
        await getaway.observeTransportEvent(
            .dataReceived(clientId: clientId, data: ping, respond: responses.respond),
            generation: generation,
            onBacklogOverflow: { _ in }
        )
        await responses.delivered.wait()
        XCTAssertEqual(responses.count, 1)
    }

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

private enum UIQueueCapacity {
    case available
    case saturated

    var expectedPendingDepth: Int {
        switch self {
        case .available:
            0
        case .saturated:
            InteractionRequestExecutor.maximumPendingRequests
        }
    }
}

private final class TransportResponseSink: Sendable {
    let delivered = CompletionSignal()
    private let responseCount = OSAllocatedUnfairLock(initialState: 0)

    var count: Int {
        responseCount.withLock { $0 }
    }

    var respond: SocketResponseHandler {
        { [weak self] _ in
            guard let self else { return .failed(.transportUnavailable) }
            responseCount.withLock { $0 += 1 }
            delivered.finish()
            return .delivered
        }
    }
}
#endif // canImport(UIKit)
