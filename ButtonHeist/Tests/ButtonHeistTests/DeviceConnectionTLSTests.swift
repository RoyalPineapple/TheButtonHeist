import XCTest
import Network
@testable import ButtonHeist

final class DeviceConnectionTLSTests: XCTestCase {

    // MARK: - DisconnectReason

    func testCertificateMismatchDisconnectReason() {
        let reason = DisconnectReason.certificateMismatch
        XCTAssertTrue(reason.errorDescription?.contains("Legacy TLS certificate fingerprint") ?? false)
    }

    func testAllDisconnectReasonsHaveDescriptions() {
        let reasons: [DisconnectReason] = [
            .networkError(NSError(domain: "test", code: 1)),
            .bufferOverflow,
            .eventBacklogOverflow(maxEvents: 512),
            .serverClosed,
            .authFailed("bad token"),
            .sessionLocked("locked"),
            .buttonHeistVersionMismatch(serverVersion: "old", clientVersion: "new"),
            .localDisconnect,
            .certificateMismatch,
            .missingFingerprint,
            .missingToken,
        ]

        for reason in reasons {
            XCTAssertNotNil(reason.errorDescription, "Missing description for \(reason)")
            XCTAssertFalse(reason.errorDescription!.isEmpty, "Empty description for \(reason)")
        }
    }

    func testDisconnectReasonTaxonomy() {
        let cases: [(DisconnectReason, KnownFailureCode, FailurePhase, Bool)] = [
            (.networkError(NSError(domain: "test", code: 1)), .transportNetworkError, .transport, true),
            (.bufferOverflow, .transportBufferOverflow, .transport, false),
            (.eventBacklogOverflow(maxEvents: 512), .transportEventBacklogOverflow, .transport, true),
            (.serverClosed, .transportServerClosed, .transport, true),
            (.authFailed("bad token"), .authFailed, .authentication, false),
            (.sessionLocked("busy"), .sessionLocked, .session, true),
            (
                .buttonHeistVersionMismatch(serverVersion: "old", clientVersion: "new"),
                .protocolMismatch, .protocolNegotiation, false
            ),
            (.localDisconnect, .clientLocalDisconnect, .client, false),
            (.certificateMismatch, .tlsCertificateMismatch, .tls, false),
            (.missingFingerprint, .tlsMissingFingerprint, .tls, false),
            (.missingToken, .tlsMissingToken, .tls, false),
        ]

        for (reason, knownCode, phase, retryable) in cases {
            XCTAssertEqual(reason.diagnostic.details.code.knownCode, knownCode)
            XCTAssertEqual(reason.failureCode, knownCode.rawValue)
            XCTAssertEqual(reason.phase, phase)
            XCTAssertEqual(reason.retryable, retryable)
            if knownCode != .clientLocalDisconnect, knownCode != .authFailed {
                XCTAssertNotNil(reason.hint, "Expected hint for \(reason)")
            }
        }
    }

    func testDisconnectReasonConnectionFailureMessagePreservesCause() {
        let message = DisconnectReason.missingFingerprint.connectionFailureMessage

        XCTAssertTrue(message.contains("connection failed in tls"))
        XCTAssertTrue(message.contains("observed Legacy TLS certificate fingerprint is unavailable"))
        XCTAssertTrue(message.contains("Current clients use token-derived TLS PSK"))
    }

    func testLegacyCertificateDiagnosticsIdentifyLegacyTransport() {
        let reasons: [DisconnectReason] = [.certificateMismatch, .missingFingerprint]

        for reason in reasons {
            XCTAssertTrue(reason.errorDescription?.contains("Legacy TLS certificate fingerprint") ?? false)
            XCTAssertEqual(
                reason.hint,
                "Current clients use token-derived TLS PSK. Rebuild or reinstall, then retry with the configured token."
            )
        }
    }

    func testExplicitTokenAuthFailureHintDoesNotSuggestUIApproval() {
        let reason = DisconnectReason.authFailed(
            "Invalid token. Retry with the configured token.",
            hint: "Retry with the configured token."
        )

        XCTAssertEqual(reason.hint, "Retry with the configured token.")
        XCTAssertTrue(reason.connectionFailureMessage.contains("Retry with the configured token."))
        XCTAssertFalse(reason.connectionFailureMessage.contains("Retry without a token"))
    }

    func testDeviceTransportSendFailurePreservesNetworkDiagnosticReason() {
        let diagnostic = DeviceTransportFailure(.posix(.ECONNRESET))
        let failure = DeviceSendFailure.transportFailed(diagnostic)

        guard case .transportFailed(let capturedDiagnostic) = failure else {
            return XCTFail("Expected typed transport failure, got \(failure)")
        }
        XCTAssertEqual(capturedDiagnostic.reason, .posix(code: Int(POSIXErrorCode.ECONNRESET.rawValue)))
        XCTAssertTrue(capturedDiagnostic.description.contains("posix"))
        XCTAssertTrue(failure.localizedDescription.contains("posix"))
    }

    // MARK: - DeviceConnection Init (actor-isolated)

    @ButtonHeistActor
    func testDeviceConnectionStoresTokenFromInitializer() async {
        let device = DiscoveredDevice(
            id: "test",
            name: "TestApp#abc",
            endpoint: NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        )

        let connection = DeviceConnection(device: device, token: "token")
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
    func testConnectWithoutTokenEmitsMissingToken() async {
        let device = DiscoveredDevice(
            id: "test",
            name: "TestApp#abc",
            endpoint: NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        )
        let connection = DeviceConnection(device: device)
        var disconnectReason: DisconnectReason?
        connection.onEvent = { event in
            if case .disconnected(let reason) = event {
                disconnectReason = reason
            }
        }

        connection.connect()

        XCTAssertEqual(disconnectReason, .missingToken)
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
