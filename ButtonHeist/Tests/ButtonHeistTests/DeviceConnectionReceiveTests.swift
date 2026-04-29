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

    private func makeDummyDevice() -> DiscoveredDevice {
        DiscoveredDevice(
            id: "test-device",
            name: "TestDevice",
            endpoint: .hostPort(host: "127.0.0.1", port: 9_999),
            certFingerprint: "sha256:test"
        )
    }
}
