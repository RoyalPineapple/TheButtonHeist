import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class TheHandoffHandshakeStateTests: XCTestCase {

    @ButtonHeistActor
    func testServerHelloSendsClientHelloFromHandoff() async {
        let handoff = TheHandoff()
        let mock = connectMockHandoff(handoff)

        handoff.handleServerMessage(.serverHello, requestId: nil)

        XCTAssertEqual(mock.sent.map { $0.0.wireType }, [.clientHello])
    }

    @ButtonHeistActor
    func testServerHelloSendsClientHelloBeforeHandoffIsConnected() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        handoff.handleServerMessage(.serverHello, requestId: nil)

        assertConnecting(handoff.connectionPhase, device: device)
        XCTAssertEqual(mock.sent.map { $0.0.wireType }, [.clientHello])
    }

    @ButtonHeistActor
    func testAuthRequiredSendsConfiguredTokenAndDriverFromHandoff() async {
        let handoff = TheHandoff()
        handoff.authToken = "test-token"
        handoff.driverID = "test-driver"
        let mock = connectMockHandoff(handoff)

        handoff.handleServerMessage(.authRequired, requestId: nil)

        guard case .authenticate(let payload) = mock.sent.first?.0 else {
            return XCTFail("Expected Handoff to send authenticate, got \(String(describing: mock.sent.first?.0))")
        }
        XCTAssertEqual(payload.token, "test-token")
        XCTAssertEqual(payload.driverId, "test-driver")
        XCTAssertEqual(mock.sent.count, 1)
    }

    @ButtonHeistActor
    func testAuthRequiredSendsAuthenticateBeforeHandoffIsConnected() async {
        let handoff = TheHandoff()
        handoff.authToken = "test-token"
        handoff.driverID = "test-driver"
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        handoff.handleServerMessage(.authRequired, requestId: nil)

        assertConnecting(handoff.connectionPhase, device: device)
        guard case .authenticate(let payload) = mock.sent.first?.0 else {
            return XCTFail("Expected Handoff to send authenticate, got \(String(describing: mock.sent.first?.0))")
        }
        XCTAssertEqual(payload.token, "test-token")
        XCTAssertEqual(payload.driverId, "test-driver")
        XCTAssertEqual(mock.sent.count, 1)
    }

    @ButtonHeistActor
    func testAuthRequiredWithoutTokenFailsWithoutSendingAuthenticate() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        handoff.handleServerMessage(.authRequired, requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .disconnected(.missingToken))
        XCTAssertTrue(mock.sent.isEmpty)
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testAuthFailureMessageFailsHandoffAndClosesTransport() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        handoff.handleServerMessage(
            .error(ServerError(kind: .authFailure, message: "bad token")),
            requestId: nil
        )

        assertFailed(handoff.connectionPhase, failure: .disconnected(.authFailed("bad token")))
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testSessionLockedFailsHandoffAndClosesTransport() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)
        let payload = SessionLockedPayload(message: "locked by another driver", activeConnections: 1)

        handoff.handleServerMessage(.sessionLocked(payload), requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .disconnected(.sessionLocked(payload.message)))
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testProtocolMismatchFailsHandoffAndClosesTransport() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        handoff.handleServerMessage(
            .protocolMismatch(ProtocolMismatchPayload(
                serverButtonHeistVersion: "0.0.0",
                clientButtonHeistVersion: buttonHeistVersion
            )),
            requestId: nil
        )

        assertFailed(handoff.connectionPhase, failure: .disconnected(.buttonHeistVersionMismatch(
            serverVersion: "0.0.0",
            clientVersion: buttonHeistVersion
        )))
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testObservedTransportDisconnectDoesNotCloseTransportAgain() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        mock.onEvent?(.disconnected(.serverClosed))

        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(mock.disconnectCount, 0)
    }
}
