import Foundation
import Network
import TheScore
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thewheelman", category: "transport")

/// Server-side transport layer for TheInsideJob.
///
/// Combines `SimpleSocketServer` (TCP) with Bonjour `NetService` advertisement
/// into a single type that TheInsideJob can delegate to for all networking concerns.
/// This is the API that TheInsideJob will consume in Batch 3.
///
/// Usage:
/// ```
/// let transport = ServerTransport()
/// transport.onClientConnected = { clientId in ... }
/// transport.onDataReceived = { clientId, data, respond in ... }
/// let port = try transport.start()
/// transport.advertise(serviceName: "MyApp#abc")
/// ```
public final class ServerTransport {

    /// The underlying TCP server (actor-isolated).
    public let server: SimpleSocketServer

    /// TLS identity for encrypted transport (nil = plain TCP).
    private let tlsIdentity: TLSIdentity?

    /// The Bonjour service, if advertising.
    private var netService: NetService?

    /// Current TXT record entries (preserved across updates).
    private var currentTXT: [String: Data] = [:]

    // MARK: - Callbacks (set before start)

    /// Called when a new client connects.
    public var onClientConnected: (@Sendable (Int) -> Void)? {
        get { server.onClientConnected }
        set { server.onClientConnected = newValue }
    }

    /// Called when a client disconnects.
    public var onClientDisconnected: (@Sendable (Int) -> Void)? {
        get { server.onClientDisconnected }
        set { server.onClientDisconnected = newValue }
    }

    /// Called when an authenticated client sends data.
    public var onDataReceived: SimpleSocketServer.DataHandler? {
        get { server.onDataReceived }
        set { server.onDataReceived = newValue }
    }

    /// Called when an unauthenticated client sends data (before auth succeeds).
    public var onUnauthenticatedData: (@Sendable (_ clientId: Int, _ data: Data, _ respond: @escaping @Sendable (Data) -> Void) -> Void)? {
        get { server.onUnauthenticatedData }
        set { server.onUnauthenticatedData = newValue }
    }

    /// The port the server is listening on (0 if not started).
    public var listeningPort: UInt16 {
        server.listeningPort
    }

    // MARK: - Init

    public init(tlsIdentity: TLSIdentity? = nil) {
        self.server = SimpleSocketServer()
        self.tlsIdentity = tlsIdentity
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Start the TCP server on the specified port.
    /// - Parameters:
    ///   - port: Port to listen on (0 = any available)
    ///   - bindToLoopback: If true, bind to loopback only
    /// - Returns: Actual port number bound
    @discardableResult
    public func start(port: UInt16 = 0, bindToLoopback: Bool = false) async throws -> UInt16 {
        let params = await tlsIdentity?.makeTLSParameters()
        return try await server.startAsync(port: port, bindToLoopback: bindToLoopback, tlsParameters: params)
    }

    /// Stop the TCP server and any Bonjour advertisement.
    public func stop() {
        stopAdvertising()
        server.stop()
    }

    // MARK: - Bonjour Advertisement

    /// Advertise the server via Bonjour.
    ///
    /// - Parameters:
    ///   - serviceName: The Bonjour service name (e.g. "MyApp#instanceId")
    ///   - simulatorUDID: Simulator UDID to include in TXT record (optional)
    ///   - installationId: Stable installation identifier (optional)
    ///   - instanceId: Human-readable instance identifier (optional)
    ///   - additionalTXT: Extra TXT record key-value pairs (optional)
    public func advertise(
        serviceName: String,
        simulatorUDID: String? = nil,
        installationId: String? = nil,
        instanceId: String? = nil,
        additionalTXT: [String: String] = [:]
    ) {
        let port = server.listeningPort
        guard port > 0 else {
            logger.error("Cannot advertise: server not started")
            return
        }

        stopAdvertising()

        let service = NetService(
            domain: "local.",
            type: buttonHeistServiceType,
            name: serviceName,
            port: Int32(port)
        )

        // Build TXT record
        var txtDict: [String: Data] = [:]
        if let simUDID = simulatorUDID, let data = simUDID.data(using: .utf8) {
            txtDict["simudid"] = data
        }
        if let installationId, let data = installationId.data(using: .utf8) {
            txtDict["installationid"] = data
        }
        if let id = instanceId, let data = id.data(using: .utf8) {
            txtDict["instanceid"] = data
        }
        for (key, value) in additionalTXT {
            if let data = value.data(using: .utf8) {
                txtDict[key] = data
            }
        }
        if let fp = tlsIdentity?.fingerprint, let data = fp.data(using: .utf8) {
            txtDict["certfp"] = data
        }
        if tlsIdentity != nil {
            txtDict["transport"] = Data("tls".utf8)
        }

        currentTXT = txtDict
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))

        netService = service
        netService?.publish()
        logger.info("Advertising as '\(serviceName)' on port \(port)")
    }

    /// Update the TXT record of the currently advertised service.
    /// Merges entries into the existing TXT record (preserving keys not in `entries`).
    /// - Parameter entries: Key-value pairs to set in the TXT record.
    public func updateTXTRecord(_ entries: [String: String]) {
        guard let service = netService else {
            logger.warning("Cannot update TXT record: not advertising")
            return
        }

        for (key, value) in entries {
            if let data = value.data(using: .utf8) {
                currentTXT[key] = data
            }
        }
        service.setTXTRecord(NetService.data(fromTXTRecord: currentTXT))
    }

    /// Stop Bonjour advertisement without stopping the TCP server.
    public func stopAdvertising() {
        netService?.stop()
        netService = nil
        currentTXT.removeAll()
    }

    // MARK: - Message Sending

    /// Send data to a specific client.
    public func send(_ data: Data, to clientId: Int) {
        server.send(data, to: clientId)
    }

    /// Broadcast data to all authenticated clients.
    public func broadcastToAll(_ data: Data) {
        server.broadcastToAll(data)
    }

    /// Mark a client as authenticated.
    public func markAuthenticated(_ clientId: Int) {
        server.markAuthenticated(clientId)
    }

    /// Disconnect a specific client.
    public func disconnect(clientId: Int) {
        server.disconnect(clientId: clientId)
    }
}
