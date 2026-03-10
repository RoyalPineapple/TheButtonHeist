import XCTest
import Network
@testable import ButtonHeist

final class DeviceConnectionTLSTests: XCTestCase {

    // MARK: - DisconnectReason

    func testCertificateMismatchDisconnectReason() {
        let reason = DisconnectReason.certificateMismatch
        XCTAssertTrue(reason.errorDescription?.contains("fingerprint") ?? false)
    }

    func testAllDisconnectReasonsHaveDescriptions() {
        let reasons: [DisconnectReason] = [
            .networkError(NSError(domain: "test", code: 1)),
            .bufferOverflow,
            .serverClosed,
            .authFailed("bad token"),
            .sessionLocked("locked"),
            .localDisconnect,
            .certificateMismatch,
        ]

        for reason in reasons {
            XCTAssertNotNil(reason.errorDescription, "Missing description for \(reason)")
            XCTAssertFalse(reason.errorDescription!.isEmpty, "Empty description for \(reason)")
        }
    }

    // MARK: - DeviceConnection Init (actor-isolated)

    @ButtonHeistActor
    func testDeviceConnectionStoresFingerprintFromDevice() {
        let fingerprint = "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
        let device = DiscoveredDevice(
            id: "test",
            name: "TestApp#abc",
            endpoint: NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil),
            certFingerprint: fingerprint
        )

        let connection = DeviceConnection(device: device)
        XCTAssertNotNil(connection)
    }

    @ButtonHeistActor
    func testDeviceConnectionWithoutFingerprint() {
        let device = DiscoveredDevice(
            id: "test",
            name: "TestApp#abc",
            endpoint: NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        )

        let connection = DeviceConnection(device: device)
        XCTAssertNotNil(connection)
    }

    @ButtonHeistActor
    func testDeviceConnectionWithToken() {
        let fingerprint = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        let device = DiscoveredDevice(
            id: "test",
            name: "TestApp#abc",
            endpoint: NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil),
            certFingerprint: fingerprint
        )

        let connection = DeviceConnection(device: device, token: "my-token", driverId: "driver-1")
        XCTAssertEqual(connection.token, "my-token")
    }
}
