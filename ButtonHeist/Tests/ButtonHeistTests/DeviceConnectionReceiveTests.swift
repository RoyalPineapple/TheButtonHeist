import XCTest
import Network
@testable import ButtonHeist
import TheScore

final class DeviceConnectionReceiveTests: XCTestCase {

    // The NWConnections here are intentionally never started. handleReceive
    // only uses them for identity comparison (`===`), so no real I/O is needed.

    @ButtonHeistActor
    func testHandleReceiveIgnoresIsCompleteFromStaleConnection() async {
        let activeConnection = NWConnection(host: "127.0.0.1", port: 1111, using: .tcp)
        let staleConnection = NWConnection(host: "127.0.0.1", port: 2222, using: .tcp)
        let connection = DeviceConnection(device: makeDummyDevice())
        connection.connectionState = .connected(.init(connection: activeConnection))

        connection.handleReceive(content: nil, isComplete: true, error: nil, connection: staleConnection)

        guard case .connected(let active) = connection.connectionState else {
            XCTFail("Expected active connection to remain connected after stale callback")
            return
        }
        XCTAssertTrue(active.connection === activeConnection)
    }

    @ButtonHeistActor
    func testHandleReceiveIgnoresErrorFromStaleConnection() async {
        let activeConnection = NWConnection(host: "127.0.0.1", port: 1111, using: .tcp)
        let staleConnection = NWConnection(host: "127.0.0.1", port: 2222, using: .tcp)
        let connection = DeviceConnection(device: makeDummyDevice())
        connection.connectionState = .connected(.init(connection: activeConnection))

        connection.handleReceive(
            content: nil,
            isComplete: false,
            error: .posix(.ECONNRESET),
            connection: staleConnection
        )

        guard case .connected(let active) = connection.connectionState else {
            XCTFail("Expected active connection to remain connected after stale callback")
            return
        }
        XCTAssertTrue(active.connection === activeConnection)
    }

    /// Regression: pong responses from the server must reach `onEvent` so
    /// TheHandoff can reset its missed-pong counter. The previous code
    /// silently swallowed `.pong` inside DeviceConnection's switch, which
    /// meant the keepalive incremented every 5s but never decremented and
    /// every connection that stayed idle for 30s was force-disconnected.
    /// The recording-during-finalize bug surfaced this — the symptom was
    /// "Disconnected by client" mid-recording.
    @ButtonHeistActor
    func testHandleReceiveForwardsPongToOnEvent() async throws {
        let activeConnection = NWConnection(host: "127.0.0.1", port: 1111, using: .tcp)
        let connection = DeviceConnection(device: makeDummyDevice())
        connection.connectionState = .connected(.init(connection: activeConnection))

        var envelope = try ResponseEnvelope(requestId: nil, message: .pong).encoded()
        envelope.append(0x0A)

        var receivedPong = false
        connection.onEvent = { event in
            if case .message(.pong, _, _) = event {
                receivedPong = true
            }
        }

        connection.handleReceive(content: envelope, isComplete: false, error: nil, connection: activeConnection)

        XCTAssertTrue(receivedPong, "DeviceConnection must forward .pong messages to TheHandoff so the keepalive counter resets")
    }

    /// Regression: `.recordingStopped` must reach TheHandoff so TheFence can
    /// clear its recording phase. Dropping it left the client believing a
    /// recording was still in progress after the server had already torn it down.
    @ButtonHeistActor
    func testHandleReceiveForwardsRecordingStoppedToOnEvent() async throws {
        let activeConnection = NWConnection(host: "127.0.0.1", port: 1111, using: .tcp)
        let connection = DeviceConnection(device: makeDummyDevice())
        connection.connectionState = .connected(.init(connection: activeConnection))

        var envelope = try ResponseEnvelope(requestId: nil, message: .recordingStopped).encoded()
        envelope.append(0x0A)

        var receivedRecordingStopped = false
        connection.onEvent = { event in
            if case .message(.recordingStopped, _, _) = event {
                receivedRecordingStopped = true
            }
        }

        connection.handleReceive(content: envelope, isComplete: false, error: nil, connection: activeConnection)

        XCTAssertTrue(receivedRecordingStopped, "DeviceConnection must forward .recordingStopped so TheFence can clear its recording phase")
    }

    @ButtonHeistActor
    func testHandleReceiveForwardsEnvelopeAccessibilityTrace() async throws {
        let activeConnection = NWConnection(host: "127.0.0.1", port: 1111, using: .tcp)
        let connection = DeviceConnection(device: makeDummyDevice())
        connection.connectionState = .connected(.init(connection: activeConnection))

        let before = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "status", label: "Status", value: "Old"),
        ])
        let after = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "status", label: "Status", value: "New"),
        ])
        let trace = makeReceiptTestTrace(before: before, after: after)
        var envelope = try ResponseEnvelope(
            requestId: "action-1",
            message: .actionResult(ActionResult(success: true, method: .activate)),
            accessibilityTrace: trace
        ).encoded()
        envelope.append(0x0A)

        var receivedTrace: AccessibilityTrace?
        var receivedRequestId: String?
        connection.onEvent = { event in
            if case .message(.actionResult, let requestId, let trace?) = event {
                receivedRequestId = requestId
                receivedTrace = trace
            }
        }

        connection.handleReceive(content: envelope, isComplete: false, error: nil, connection: activeConnection)

        XCTAssertEqual(receivedRequestId, "action-1")
        XCTAssertEqual(receivedTrace, trace)
    }

    @ButtonHeistActor
    func testHandleReceiveAcceptsLargeScreenResponse() async throws {
        let activeConnection = NWConnection(host: "127.0.0.1", port: 1111, using: .tcp)
        let connection = DeviceConnection(device: makeDummyDevice())
        connection.connectionState = .connected(.init(connection: activeConnection))

        let oversizedForOldLimit = String(repeating: "A", count: 10_100_000)
        let screen = ScreenPayload(pngData: oversizedForOldLimit, width: 1366, height: 1024)
        var envelope = try ResponseEnvelope(requestId: "screen-1", message: .screen(screen)).encoded()
        envelope.append(0x0A)

        var receivedScreen: ScreenPayload?
        connection.onEvent = { event in
            if case .message(.screen(let payload), _, _) = event {
                receivedScreen = payload
            }
        }

        connection.handleReceive(content: envelope, isComplete: false, error: nil, connection: activeConnection)

        XCTAssertEqual(receivedScreen?.width, 1366)
        XCTAssertEqual(receivedScreen?.pngData.count, oversizedForOldLimit.count)
        XCTAssertTrue(connection.isConnected)
    }

    @ButtonHeistActor
    func testSendWhileDisconnectedFailsTyped() async {
        let connection = DeviceConnection(device: makeDummyDevice())

        let outcome = connection.send(.ping, requestId: "late")

        guard case .failed(.notConnected) = outcome else {
            return XCTFail("Expected notConnected send failure, got \(outcome)")
        }
    }

    private func makeDummyDevice() -> DiscoveredDevice {
        DiscoveredDevice(
            id: "test-device",
            name: "TestDevice",
            endpoint: .hostPort(host: "127.0.0.1", port: 9_999),
            certFingerprint: "sha256:test"
        )
    }
}
