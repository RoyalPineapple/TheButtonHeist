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
            .protocolMismatch("server=old, client=new"),
            .localDisconnect,
            .certificateMismatch,
            .missingFingerprint,
        ]

        for reason in reasons {
            XCTAssertNotNil(reason.errorDescription, "Missing description for \(reason)")
            XCTAssertFalse(reason.errorDescription!.isEmpty, "Empty description for \(reason)")
        }
    }

    func testDisconnectReasonTaxonomy() {
        let cases: [(DisconnectReason, String, FailurePhase, Bool)] = [
            (.networkError(NSError(domain: "test", code: 1)), "transport.network_error", .transport, true),
            (.bufferOverflow, "transport.buffer_overflow", .transport, false),
            (.serverClosed, "transport.server_closed", .transport, true),
            (.authFailed("bad token"), "auth.failed", .authentication, false),
            (.sessionLocked("busy"), "session.locked", .session, true),
            (.protocolMismatch("server=old, client=new"), "protocol.mismatch", .protocolNegotiation, false),
            (.localDisconnect, "client.local_disconnect", .client, false),
            (.certificateMismatch, "tls.certificate_mismatch", .tls, false),
            (.missingFingerprint, "tls.missing_fingerprint", .tls, false),
        ]

        for (reason, code, phase, retryable) in cases {
            XCTAssertEqual(reason.failureCode, code)
            XCTAssertEqual(reason.phase, phase)
            XCTAssertEqual(reason.retryable, retryable)
            if code != "client.local_disconnect" {
                XCTAssertNotNil(reason.hint, "Expected hint for \(reason)")
            }
        }
    }

    // MARK: - DeviceConnection Init (actor-isolated)

    @ButtonHeistActor
    func testDeviceConnectionStoresFingerprintFromDevice() async {
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
    func testDeviceConnectionWithoutFingerprint() async {
        let device = DiscoveredDevice(
            id: "test",
            name: "TestApp#abc",
            endpoint: NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        )

        let connection = DeviceConnection(device: device)
        XCTAssertNotNil(connection)
    }

    @ButtonHeistActor
    func testDeviceConnectionWithToken() async {
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

    // MARK: - Loopback Detection

    func testIPv4LoopbackDetected() {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 8080)
        XCTAssertTrue(DeviceConnection.isLoopbackEndpoint(endpoint))
    }

    func testIPv6LoopbackDetected() {
        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: 8080)
        XCTAssertTrue(DeviceConnection.isLoopbackEndpoint(endpoint))
    }

    func testHostnameLocalhostNotTreatedAsLoopback() {
        let endpoint = NWEndpoint.hostPort(host: .name("localhost", nil), port: 8080)
        XCTAssertFalse(DeviceConnection.isLoopbackEndpoint(endpoint), "Hostname 'localhost' must not be treated as loopback")
    }

    func testRemoteIPNotLoopback() {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.init("192.168.1.1")!), port: 8080)
        XCTAssertFalse(DeviceConnection.isLoopbackEndpoint(endpoint))
    }

    func testServiceEndpointNotLoopback() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        XCTAssertFalse(DeviceConnection.isLoopbackEndpoint(endpoint))
    }
}
