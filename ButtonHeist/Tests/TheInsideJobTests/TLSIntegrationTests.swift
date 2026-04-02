import XCTest
import Network
import Security
import CryptoKit
import TheScore
@testable import TheInsideJob

/// Integration tests for TLS transport over real TCP connections.
/// Verifies end-to-end TLS handshake, fingerprint pinning, and data exchange.
final class TLSIntegrationTests: XCTestCase {

    private var server: SimpleSocketServer!

    override func setUp() {
        super.setUp()
        server = SimpleSocketServer()
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
        try await super.tearDown()
    }

    // MARK: - TLS Handshake

    func testTLSHandshakeWithFingerprintPinning() async throws {
        let identity = try TLSIdentity.createEphemeral()
        let tlsParams = await identity.makeTLSParameters()
        XCTAssertNotNil(tlsParams, "TLS parameters must be created")

        let connected = expectation(description: "client connected to server")
        let callbacks = SimpleSocketServer.Callbacks(
            onClientConnected: { _, _ in connected.fulfill() }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams, callbacks: callbacks)
        XCTAssertGreaterThan(port, 0)

        let clientParams = Self.makeClientTLSParameters(expectedFingerprint: identity.fingerprint)
        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: clientParams
        )

        let clientReady = expectation(description: "client TLS handshake complete")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, connected], timeout: 5.0)
        connection.cancel()
    }

    func testDataExchangeOverTLS() async throws {
        let identity = try TLSIdentity.createEphemeral()
        let tlsParams = await identity.makeTLSParameters()!

        let echoMessage = Data("hello-tls\n".utf8)
        let echoReceived = expectation(description: "server received message")

        let callbacks = SimpleSocketServer.Callbacks(
            onUnauthenticatedData: { _, data, respond in
                respond(data)
                echoReceived.fulfill()
            }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams, callbacks: callbacks)

        let clientParams = Self.makeClientTLSParameters(expectedFingerprint: identity.fingerprint)
        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: clientParams
        )

        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())
        await fulfillment(of: [clientReady], timeout: 5.0)

        connection.send(content: echoMessage, completion: .contentProcessed { error in
            XCTAssertNil(error, "Send should succeed over TLS")
        })

        await fulfillment(of: [echoReceived], timeout: 5.0)

        let receivedData = try await receiveData(from: connection)
        let received = String(data: receivedData, encoding: .utf8) ?? ""
        XCTAssertTrue(received.contains("hello-tls"), "Should receive echoed data over TLS")

        connection.cancel()
    }

    func testWrongFingerprintRejectsConnection() async throws {
        let identity = try TLSIdentity.createEphemeral()
        let tlsParams = await identity.makeTLSParameters()!

        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams)

        let wrongFingerprint = "sha256:" + String(repeating: "ab", count: 32)
        let clientParams = Self.makeClientTLSParameters(expectedFingerprint: wrongFingerprint)
        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: clientParams
        )

        let connectionFailed = expectation(description: "connection should fail or not reach ready")
        connectionFailed.assertForOverFulfill = false
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled, .waiting:
                connectionFailed.fulfill()
            default:
                break
            }
        }
        connection.start(queue: .global())

        await fulfillment(of: [connectionFailed], timeout: 5.0)
        connection.cancel()
    }

    func testUnauthenticatedStatusProbeRoundTripsOverTLS() async throws {
        let identity = try TLSIdentity.createEphemeral()
        let transport = ServerTransport(tlsIdentity: identity)
        let server = transport.server
        defer { transport.stop() }

        transport.onClientConnected = { clientId, _ in
            guard let authRequired = try? JSONEncoder().encode(ResponseEnvelope(message: .authRequired)) else {
                XCTFail("Failed to encode authRequired response")
                return
            }
            Task { await server.send(authRequired, to: clientId) }
        }

        transport.onUnauthenticatedData = { _, data, respond in
            let decoder = JSONDecoder()
            guard let envelope = try? decoder.decode(RequestEnvelope.self, from: data) else {
                XCTFail("Expected RequestEnvelope for unauthenticated status probe")
                return
            }
            guard case .status = envelope.message else {
                XCTFail("Expected unauthenticated status probe, got \(envelope.message)")
                return
            }

            let payload = StatusPayload(
                identity: StatusIdentity(
                    appName: "ReachableApp",
                    bundleIdentifier: "com.test.reachable",
                    appBuild: "42",
                    deviceName: "Loopback Simulator",
                    systemVersion: "18.0",
                    buttonHeistVersion: protocolVersion
                ),
                session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
            )
            guard let response = try? JSONEncoder().encode(
                ResponseEnvelope(requestId: envelope.requestId, message: .status(payload))
            ) else {
                XCTFail("Failed to encode status response")
                return
            }
            respond(response)
        }

        let port = try await transport.start(port: 0, bindToLoopback: true)

        let clientParams = Self.makeClientTLSParameters(expectedFingerprint: identity.fingerprint)
        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: clientParams
        )

        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())
        await fulfillment(of: [clientReady], timeout: 5.0)

        let authRequiredData = try await receiveData(from: connection)
        let authRequired = try decodeResponseEnvelope(from: authRequiredData)
        if case .authRequired = authRequired.message {
            // Expected
        } else {
            XCTFail("Expected authRequired before status probe")
        }

        let requestId = UUID().uuidString
        var request = try JSONEncoder().encode(RequestEnvelope(requestId: requestId, message: .status))
        request.append(0x0A)
        connection.send(content: request, completion: .contentProcessed { error in
            XCTAssertNil(error, "Unauthenticated status probe should send successfully")
        })

        let statusData = try await receiveData(from: connection)
        let statusResponse = try decodeResponseEnvelope(from: statusData)
        XCTAssertEqual(statusResponse.requestId, requestId)

        if case .status(let payload) = statusResponse.message {
            XCTAssertEqual(payload.identity.appName, "ReachableApp")
            XCTAssertEqual(payload.identity.bundleIdentifier, "com.test.reachable")
            XCTAssertEqual(payload.session.active, false)
            XCTAssertEqual(payload.session.activeConnections, 0)
        } else {
            XCTFail("Expected status payload in unauthenticated probe response")
        }

        connection.cancel()
    }

    // MARK: - Helpers

    private static func makeClientTLSParameters(expectedFingerprint: String) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let expected = expectedFingerprint
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trust, completionHandler in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                      let leaf = chain.first else {
                    completionHandler(false)
                    return
                }
                let derData = SecCertificateCopyData(leaf) as Data
                let hash = SHA256.hash(data: derData)
                let actual = "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
                completionHandler(actual == expected)
            },
            DispatchQueue(label: "com.buttonheist.tls.test.verify")
        )

        return NWParameters(tls: tlsOptions)
    }

    private func receiveData(from connection: NWConnection, timeout: TimeInterval = 5.0) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let content {
                            continuation.resume(returning: content)
                        } else {
                            continuation.resume(
                                throwing: NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])
                            )
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw NSError(domain: "test", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "receiveData timed out after \(timeout)s"
                ])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func decodeResponseEnvelope(from data: Data) throws -> ResponseEnvelope {
        let trimmed = data.last == 0x0A ? Data(data.dropLast()) : data
        return try JSONDecoder().decode(ResponseEnvelope.self, from: trimmed)
    }
}
