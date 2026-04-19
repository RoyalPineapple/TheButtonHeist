import XCTest
import Network
@testable import ButtonHeist

final class DeviceConnectionReceiveTests: XCTestCase {

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

    private func makeDummyDevice() -> DiscoveredDevice {
        DiscoveredDevice(
            id: "test-device",
            name: "TestDevice",
            endpoint: .hostPort(host: "127.0.0.1", port: 9_999),
            certFingerprint: "sha256:test"
        )
    }
}
