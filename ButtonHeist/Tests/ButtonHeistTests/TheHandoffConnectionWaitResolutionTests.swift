import ButtonHeistTestSupport
import Foundation
import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class TheHandoffConnectionWaitResolutionTests: XCTestCase {

    // MARK: - waitForConnectionResult continuation

    @ButtonHeistActor
    func testWaitForConnectionResultReturnsImmediatelyWhenAlreadyConnected() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.serverInfo = ServerInfo(
            appName: "TestApp",
            bundleIdentifier: "com.test",
            deviceName: "Simulator",
            systemVersion: "26.1",
            screenWidth: 402,
            screenHeight: 874,
            instanceId: "test-session",
            instanceIdentifier: "test",
            listeningPort: 49152,
            tlsActive: true
        )
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        XCTAssertTrue(handoff.connectionLifecycle.isConnected)

        // Already connected — should return immediately without throwing.
        try await handoff.waitForConnectionResult(timeout: 5)
    }

    @ButtonHeistActor
    func testWaitForConnectionResultThrowsWhenAlreadyFailed() async {
        let handoff = TheHandoff()
        let serverError = ServerError(kind: .general, message: "boom")
        // Drive into .failed state via a server error.
        handoff.handleServerMessage(
            .error(serverError),
            requestId: nil
        )
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))

        do {
            try await handoff.waitForConnectionResult(timeout: 5)
            XCTFail("Expected HandoffConnectionError to be thrown")
        } catch let error as HandoffConnectionError {
            guard case .serverFailure(let failure) = error else {
                return XCTFail("Expected .serverFailure, got \(error)")
            }
            XCTAssertEqual(failure, serverError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @ButtonHeistActor
    func testWaitForConnectionResultResumesOnConnectedTransition() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        // Don't auto-connect — caller will trigger the .connected event manually
        // so we can verify the continuation wakes on the transition.
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        // Phase is now .connecting; waiter should suspend.
        let waitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 5)
        }

        // Yield once so the waiter registers its continuation before we fire
        // the .connected event.
        await Task.yield()

        // Fire the connected transition.
        mock.onEvent?(.connected)
        XCTAssertTrue(handoff.connectionLifecycle.isConnected)

        try await waitTask.value
    }
}
