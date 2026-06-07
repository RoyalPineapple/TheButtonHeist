import XCTest
import Network
import Security
import CryptoKit
import os
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
        let identity = try makeEphemeralIdentityOrSkip()
        let generatedTLSParams = await identity.makeTLSParameters()
        let tlsParams = try XCTUnwrap(generatedTLSParams, "TLS parameters must be created")

        let connected = expectation(description: "client connected to server")
        let callbacks = SocketServerCallbacks(
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
        let identity = try makeEphemeralIdentityOrSkip()
        let tlsParams = await identity.makeTLSParameters()!

        let echoMessage = Data("hello-tls\n".utf8)
        let echoReceived = expectation(description: "server received message")

        let callbacks = SocketServerCallbacks(
            onDataReceived: { _, data, respond in
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
        let identity = try makeEphemeralIdentityOrSkip()
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

    func testPassiveReachabilityDoesNotSendUnauthenticatedStatusOverTLS() async throws {
        let identity = try makeEphemeralIdentityOrSkip()
        let tlsParams = await identity.makeTLSParameters()!

        // Use the instance server directly (cleaned up by tearDown) instead of
        // ServerTransport, which uses fire-and-forget Task cleanup that can
        // leave lingering state between test runner invocations.
        let clientConnected = expectation(description: "client connected")
        let unexpectedPreAuthData = expectation(description: "no unauthenticated status probe")
        unexpectedPreAuthData.isInverted = true

        let callbacks = SocketServerCallbacks(
            onClientConnected: { _, _ in
                clientConnected.fulfill()
            },
            onDataReceived: { _, _, _ in
                unexpectedPreAuthData.fulfill()
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
        await fulfillment(of: [clientReady, clientConnected], timeout: 5.0)
        await fulfillment(of: [unexpectedPreAuthData], timeout: 0.2)

        connection.cancel()
    }

    func testNetworkFrameworkTLSHandshakeWithPreSharedKey() async throws {
        let secret = Self.testPreSharedKey
        let identity = Self.testPreSharedKeyIdentity
        let tlsParams = Self.makePreSharedKeyTLSParameters(secret: secret, identity: identity)

        let connected = expectation(description: "client connected with PSK TLS")
        let callbacks = SocketServerCallbacks(
            onClientConnected: { _, _ in connected.fulfill() }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams, callbacks: callbacks)

        let clientParams = Self.makePreSharedKeyTLSParameters(secret: secret, identity: identity)
        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: clientParams
        )

        let clientReady = expectation(description: "client PSK TLS handshake complete")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, connected], timeout: 5.0)
        connection.cancel()
    }

    func testNetworkFrameworkTLSRejectsWrongPreSharedKey() async throws {
        let tlsParams = Self.makePreSharedKeyTLSParameters(
            secret: Self.testPreSharedKey,
            identity: Self.testPreSharedKeyIdentity
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams)

        var wrongSecret = Self.testPreSharedKey
        wrongSecret[0] ^= 0xff
        let clientParams = Self.makePreSharedKeyTLSParameters(
            secret: wrongSecret,
            identity: Self.testPreSharedKeyIdentity
        )
        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: clientParams
        )

        let connectionFailed = expectation(description: "wrong PSK should fail TLS handshake")
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

    // MARK: - Helpers

    private static let testPreSharedKey = Data([
        0x7d, 0x32, 0x34, 0xef, 0x98, 0x8b, 0x2b, 0xf4,
        0xf9, 0xe9, 0xac, 0x95, 0x50, 0xdb, 0x51, 0xd2,
        0x36, 0x15, 0x36, 0xae, 0x28, 0x79, 0x3f, 0x26,
        0x71, 0xa3, 0x54, 0x6e, 0xa3, 0x35, 0x82, 0x23,
    ])

    private static let testPreSharedKeyIdentity = Data("buttonheist-test-psk".utf8)

    private static func makePreSharedKeyTLSParameters(secret: Data, identity: Data) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!
        )
        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            dispatchData(secret),
            dispatchData(identity)
        )
        sec_protocol_options_set_tls_pre_shared_key_identity_hint(
            tlsOptions.securityProtocolOptions,
            dispatchData(identity)
        )

        return NWParameters(tls: tlsOptions)
    }

    private static func dispatchData(_ data: Data) -> dispatch_data_t {
        data.withUnsafeBytes { rawBuffer -> dispatch_data_t in
            DispatchData(bytes: rawBuffer) as dispatch_data_t
        }
    }

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
                // Group-race timeout against a real network read; needs wall-clock.
                // swiftlint:disable:next agent_test_task_sleep
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
}
