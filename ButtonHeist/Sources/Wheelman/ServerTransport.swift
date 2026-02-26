import Foundation
import Network
import TheScore
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thewheelman", category: "transport")

/// Server-side transport layer for InsideJob.
///
/// Combines `SimpleSocketServer` (TCP) with Bonjour `NetService` advertisement
/// into a single type that InsideJob can delegate to for all networking concerns.
/// This is the API that InsideJob will consume in Batch 3.
///
/// Usage:
/// ```
/// let transport = ServerTransport()
/// transport.onClientConnected = { clientId in ... }
/// transport.onDataReceived = { clientId, data, respond in ... }
/// let port = try transport.start()
/// transport.advertise(serviceName: "MyApp#abc", tokenHash: "deadbeef")
/// ```
public final class ServerTransport {

    /// The underlying TCP server (actor-isolated).
    public let server: SimpleSocketServer

    /// The Bonjour service, if advertising.
    private var netService: NetService?

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

    public init() {
        self.server = SimpleSocketServer()
    }

    // MARK: - Lifecycle

    /// Start the TCP server on the specified port.
    /// - Parameters:
    ///   - port: Port to listen on (0 = any available)
    ///   - bindToLoopback: If true, bind to loopback only
    /// - Returns: Actual port number bound
    @discardableResult
    public func start(port: UInt16 = 0, bindToLoopback: Bool = false) throws -> UInt16 {
        try server.start(port: port, bindToLoopback: bindToLoopback)
    }

    /// Stop the TCP server and any Bonjour advertisement.
    public func stop() {
        server.stop()
        netService?.stop()
        netService = nil
    }

    // MARK: - Bonjour Advertisement

    /// Advertise the server via Bonjour.
    ///
    /// - Parameters:
    ///   - serviceName: The Bonjour service name (e.g. "MyApp#instanceId")
    ///   - simulatorUDID: Simulator UDID to include in TXT record (optional)
    ///   - tokenHash: Token hash prefix for pre-connection filtering (optional)
    ///   - instanceId: Human-readable instance identifier (optional)
    ///   - additionalTXT: Extra TXT record key-value pairs (optional)
    public func advertise(
        serviceName: String,
        simulatorUDID: String? = nil,
        tokenHash: String? = nil,
        instanceId: String? = nil,
        additionalTXT: [String: String] = [:]
    ) {
        let port = server.listeningPort
        guard port > 0 else {
            logger.error("Cannot advertise: server not started")
            return
        }

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
        if let hash = tokenHash, let data = hash.data(using: .utf8) {
            txtDict["tokenhash"] = data
        }
        if let id = instanceId, let data = id.data(using: .utf8) {
            txtDict["instanceid"] = data
        }
        for (key, value) in additionalTXT {
            if let data = value.data(using: .utf8) {
                txtDict[key] = data
            }
        }

        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))

        netService = service
        netService?.publish()
        logger.info("Advertising as '\(serviceName)' on port \(port)")
    }

    /// Update the TXT record of the currently advertised service.
    /// - Parameter entries: Key-value pairs to set in the TXT record.
    public func updateTXTRecord(_ entries: [String: String]) {
        guard let service = netService else {
            logger.warning("Cannot update TXT record: not advertising")
            return
        }

        var txtDict: [String: Data] = [:]
        for (key, value) in entries {
            if let data = value.data(using: .utf8) {
                txtDict[key] = data
            }
        }
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
    }

    /// Stop Bonjour advertisement without stopping the TCP server.
    public func stopAdvertising() {
        netService?.stop()
        netService = nil
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
