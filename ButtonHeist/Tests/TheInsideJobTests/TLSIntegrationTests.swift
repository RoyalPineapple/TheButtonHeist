import XCTest
import Network
import Security
import Crypto
@testable import TheGetaway

/// Integration tests for TLS transport over real TCP connections.
/// Verifies end-to-end TLS handshake, fingerprint pinning, and data exchange.
final class TLSIntegrationTests: XCTestCase {

    private var server: SimpleSocketServer!

    override func setUp() {
        super.setUp()
        server = SimpleSocketServer()
    }

    override func tearDown() {
        server.stop()
        server = nil
        super.tearDown()
    }

    // MARK: - TLS Handshake

    func testTLSHandshakeWithFingerprintPinning() async throws {
        let identity = try TLSIdentity.createEphemeral()
        let tlsParams = await identity.makeTLSParameters()
        XCTAssertNotNil(tlsParams, "TLS parameters must be created")

        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams)
        XCTAssertGreaterThan(port, 0)

        let connected = expectation(description: "client connected to server")
        server.onClientConnected = { _ in
            connected.fulfill()
        }

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

        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams)

        let echoMessage = Data("hello-tls\n".utf8)
        let echoReceived = expectation(description: "server received message")

        server.onClientConnected = { clientId in
            self.server.markAuthenticated(clientId)
        }
        server.onDataReceived = { _, data, respond in
            respond(data)
            echoReceived.fulfill()
        }

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

    func testPlainTCPFallbackWhenNoTLS() async throws {
        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: nil)
        XCTAssertGreaterThan(port, 0)

        let connected = expectation(description: "plain TCP client connected")
        server.onClientConnected = { _ in
            connected.fulfill()
        }

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, connected], timeout: 5.0)
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
}
