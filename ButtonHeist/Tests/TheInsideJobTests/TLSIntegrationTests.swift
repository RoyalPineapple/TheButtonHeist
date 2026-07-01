import Foundation
import XCTest

@testable import ButtonHeistTesting
import TheScore
@testable import TheInsideJob

/// Integration tests for token-derived Network.framework TLS-PSK transport.
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

    func testTLSHandshakeWithPreSharedKey() async throws {
        let token = "correct horse battery staple"
        let connected = expectation(description: "client connected to server")
        let callbacks = SocketServerCallbacks(
            onClientConnected: { _, _ in connected.fulfill() }
        )
        let port = try await server.startAsync(
            port: 0,
            bindToLoopback: true,
            tlsParameters: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token),
            callbacks: callbacks
        )
        let client = ButtonHeistNetworkTestClient.tls(port: port, token: token)
        defer { client.cancel() }

        try await client.connect()

        await fulfillment(of: [connected], timeout: 5.0)
    }

    func testDataExchangeOverTLSPreSharedKey() async throws {
        let token = "shared-token"
        let echoReceived = expectation(description: "server received message")
        let callbacks = SocketServerCallbacks(
            onDataReceived: { _, data, respond in
                respond(data)
                echoReceived.fulfill()
            }
        )
        let port = try await server.startAsync(
            port: 0,
            bindToLoopback: true,
            tlsParameters: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token),
            callbacks: callbacks
        )
        let client = ButtonHeistNetworkTestClient.tls(port: port, token: token)
        defer { client.cancel() }
        try await client.connect()

        try await client.sendLine("hello-tls")

        await fulfillment(of: [echoReceived], timeout: 5.0)
        let received = String(data: try await client.receiveLine(), encoding: .utf8)
        XCTAssertEqual(received, "hello-tls")
    }

    func testWrongPreSharedKeyRejectsConnection() async throws {
        let port = try await server.startAsync(
            port: 0,
            bindToLoopback: true,
            tlsParameters: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: "server-token")
        )
        let client = ButtonHeistNetworkTestClient.tls(port: port, token: "client-token")
        defer { client.cancel() }

        try await client.connectExpectingRejection()
    }

    func testPassiveReachabilityDoesNotSendUnauthenticatedStatusOverTLS() async throws {
        let token = "probe-token"
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
        let port = try await server.startAsync(
            port: 0,
            bindToLoopback: true,
            tlsParameters: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token),
            callbacks: callbacks
        )
        let client = ButtonHeistNetworkTestClient.tls(port: port, token: token)
        defer { client.cancel() }

        try await client.connect()

        await fulfillment(of: [clientConnected], timeout: 5.0)
        await fulfillment(of: [unexpectedPreAuthData], timeout: 0.2)
    }
}

final class JoinHeistIntegrationTests: XCTestCase {

    func testJoinHeistSessionAcceptsWireClientAndReturnsInterface() throws {
        let token = "join-heist-\(UUID().uuidString)"
        let session = try XCTUnwrap(startJoinedHeistSession(
            token: token,
            port: 0,
            allowedScopes: [.simulator],
            file: #filePath,
            line: #line
        ))
        let client = ButtonHeistWireTestClient(
            token: token,
            port: session.listeningPort
        )
        defer {
            client.cancel()
            stopJoinedHeistSession(session)
        }

        let completed = expectation(description: "wire client completed joinHeist probe")
        let completedFulfillment = SendableXCTestFulfillment(completed)
        let result = SyncResultBox<JoinHeistProbe>()
        let probeTask = Task {
            do {
                try await client.connect()
                let info = try await client.authenticate(driverId: "join-heist-integration-test")
                let interface = try await client.requestInterface()
                result.finish(.success(JoinHeistProbe(
                    reportedPort: info.listeningPort,
                    labels: interface.projectedElements.compactMap(\.label)
                )))
            } catch {
                result.finish(.failure(error))
            }
            completedFulfillment.fulfill()
        }
        defer { probeTask.cancel() }

        wait(for: [completed], timeout: 10.0)

        let probe = try result.value()
        XCTAssertEqual(probe.reportedPort, session.listeningPort)
        XCTAssertTrue(
            probe.labels.contains("ButtonHeist Demo"),
            "Expected joined session to return the live demo app interface, got labels: \(probe.labels)"
        )
    }

    private func stopJoinedHeistSession(_ session: JoinedHeistSession) {
        let stopped = expectation(description: "joined heist session stopped")
        let stoppedFulfillment = SendableXCTestFulfillment(stopped)
        Task { @MainActor in
            await session.stop()
            stoppedFulfillment.fulfill()
        }
        wait(for: [stopped], timeout: 5.0)
    }
}

private struct JoinHeistProbe: Sendable {
    let reportedPort: UInt16
    let labels: [String]
}

/// `@unchecked Sendable` justification: `storage` is written from an async test
/// task and read by the synchronous XCTest body; every access is serialized by
/// `lock`.
private final class SyncResultBox<Value: Sendable>: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let lock = NSLock()
    private var storage: Result<Value, Error>?

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard storage == nil else { return }
        storage = result
    }

    func value() throws -> Value {
        lock.lock()
        defer { lock.unlock() }
        guard let storage else {
            throw ButtonHeistNetworkTestFailure("Async test task did not report a result")
        }
        return try storage.get()
    }
}

/// `@unchecked Sendable` justification: XCTest expectations are fulfilled from
/// async callbacks in this file, and this wrapper only forwards `fulfill()`.
private final class SendableXCTestFulfillment: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let expectation: XCTestExpectation

    init(_ expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func fulfill() {
        expectation.fulfill()
    }
}
