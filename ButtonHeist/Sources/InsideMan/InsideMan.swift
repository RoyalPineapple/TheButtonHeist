#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import CryptoKit
import TheGoods
import Wheelman
import os.log

/// Debug logging helper - uses NSLog for maximum visibility
func serverLog(_ message: String) {
    NSLog("[InsideMan] %@", message)
}

/// Weak reference wrapper for interactive accessibility objects.
struct WeakObject {
    weak var object: NSObject?
}

/// Provides access to the parsed accessibility element cache.
/// InsideMan owns the data; TheSafecracker reads it to resolve interaction targets
/// and can trigger a refresh when it needs fresh data (e.g. after typing).
@MainActor
protocol ElementStore: AnyObject {
    var cachedElements: [AccessibilityElement] { get }
    var interactiveObjects: [Int: WeakObject] { get }
    @discardableResult func refreshElements() -> Bool
}

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class InsideMan: ElementStore {

    // MARK: - Singleton

    /// Shared instance - use `configure(port:token:instanceId:)` before first access
    public static var shared: InsideMan = InsideMan()

    /// Configure the shared instance. Must be called before start().
    public static func configure(port: UInt16, token: String? = nil, instanceId: String? = nil) {
        shared = InsideMan(port: port, token: token, instanceId: instanceId)
    }

    // MARK: - Properties

    private var socketServer: SimpleSocketServer?
    private var netService: NetService?
    var subscribedClients: Set<Int> = []
    private let port: UInt16
    private let muscle: TheMuscle
    private let instanceId: String?
    private let sessionId = UUID()
    let parser = AccessibilityHierarchyParser()
    let theSafecracker = TheSafecracker()
    var cachedElements: [AccessibilityElement] = []

    /// Weak references to interactive accessibility objects from the last parse,
    /// keyed by traversal index.
    var interactiveObjects: [Int: WeakObject] = [:]

    private var isRunning = false
    private var isSuspended = false

    // Debounce for hierarchy updates
    var updateDebounceTask: Task<Void, Never>?
    let updateDebounceInterval: UInt64 = 300_000_000 // 300ms in nanoseconds

    // Polling for automatic updates (disabled by default)
    var pollingTask: Task<Void, Never>?
    var pollingInterval: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    var isPollingEnabled = false
    var lastHierarchyHash: Int = 0

    // MARK: - Initialization

    public init(port: UInt16 = 0, token: String? = nil, instanceId: String? = nil) {
        self.port = port
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.theSafecracker.elementStore = self
    }

    // MARK: - ElementStore Conformance

    func refreshElements() -> Bool {
        refreshAccessibilityData() != nil
    }

    // MARK: - Public Methods

    // MARK: - Environment Helpers

    private var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_UDID"] != nil
    }

    private var shouldBindToLoopback: Bool {
        let bindAllOverride = ProcessInfo.processInfo.environment["INSIDEMAN_BIND_ALL"]
            .map { ["true", "1", "yes"].contains($0.lowercased()) } ?? false
        return isSimulator && !bindAllOverride
    }

    /// Simulators share localhost — use random port to avoid collisions.
    /// Fixed ports are only useful on physical devices (for USB tunneling).
    private var effectivePort: UInt16 {
        isSimulator ? 0 : port
    }

    /// Start the server
    public func start() throws {
        guard !isRunning else { return }

        serverLog("Starting InsideMan with SimpleSocketServer...")

        let server = SimpleSocketServer()
        wireServer(server)

        let actualPort = try server.start(port: effectivePort, bindToLoopback: shouldBindToLoopback)
        self.socketServer = server
        isRunning = true

        if shouldBindToLoopback {
            serverLog("Server listening on loopback port \(actualPort) (simulator)")
        } else {
            serverLog("Server listening on port \(actualPort)")
        }
        serverLog("Auth token: \(muscle.authToken)")
        if let instanceId {
            serverLog("Instance ID: \(instanceId)")
        }
        advertiseService(port: actualPort)

        startAccessibilityObservation()
        startLifecycleObservation()

        serverLog("Server started successfully")
    }

    /// Stop the server
    public func stop() {
        isRunning = false
        isSuspended = false
        stopPolling()

        socketServer?.stop()
        socketServer = nil

        netService?.stop()
        netService = nil

        subscribedClients.removeAll()
        muscle.tearDown()

        stopAccessibilityObservation()
        stopLifecycleObservation()

        serverLog("Server stopped")
    }

    /// Notify the bridge that the UI has changed and subscribers should receive an update.
    /// Call this from your app whenever state changes that affect the accessibility hierarchy.
    public func notifyChange() {
        guard isRunning else { return }
        scheduleHierarchyUpdate()
    }

    /// Enable polling for automatic hierarchy updates.
    /// - Parameter interval: Polling interval in seconds (default 1.0, minimum 0.5)
    public func startPolling(interval: TimeInterval = 1.0) {
        let clampedInterval = max(0.5, interval)
        pollingInterval = UInt64(clampedInterval * 1_000_000_000)
        isPollingEnabled = true
        startPollingLoop()
        serverLog("Polling enabled (interval: \(clampedInterval)s)")
    }

    /// Disable polling for automatic updates
    public func stopPolling() {
        isPollingEnabled = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Server Wiring

    private func wireServer(_ server: SimpleSocketServer) {
        muscle.sendToClient = { [weak server] data, clientId in server?.send(data, to: clientId) }
        muscle.markClientAuthenticated = { [weak server] clientId in server?.markAuthenticated(clientId) }
        muscle.disconnectClient = { [weak server] clientId in server?.disconnect(clientId: clientId) }
        muscle.onClientAuthenticated = { [weak self] clientId, respond in
            self?.handleClientConnected(clientId, respond: respond)
        }

        server.onClientConnected = { [weak self] clientId in
            Task { @MainActor in
                serverLog("Client \(clientId) connected, awaiting auth")
                self?.muscle.sendAuthRequired(clientId: clientId)
            }
        }

        server.onClientDisconnected = { [weak self] clientId in
            Task { @MainActor in
                serverLog("Client \(clientId) disconnected")
                self?.subscribedClients.remove(clientId)
                self?.muscle.handleClientDisconnected(clientId)
            }
        }

        server.onDataReceived = { [weak self] clientId, data, respond in
            Task { @MainActor in
                await self?.handleClientMessage(clientId, data: data, respond: respond)
            }
        }

        server.onUnauthenticatedData = { [weak self] clientId, data, respond in
            Task { @MainActor in
                self?.muscle.handleUnauthenticatedMessage(clientId, data: data, respond: respond)
            }
        }
    }

    // MARK: - Service Advertisement

    private var shortId: String {
        String(sessionId.uuidString.prefix(8)).lowercased()
    }

    private var effectiveInstanceId: String {
        instanceId ?? shortId
    }

    private func advertiseService(port: UInt16) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let serviceName = "\(appName)#\(effectiveInstanceId)"

        let service = NetService(
            domain: "local.",
            type: buttonHeistServiceType,
            name: serviceName,
            port: Int32(port)
        )

        // Publish identifiers in TXT record for pre-connection filtering
        var txtDict: [String: Data] = [:]
        if let simUDID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
           let data = simUDID.data(using: .utf8) {
            txtDict["simudid"] = data
        }

        // Token hash for pre-connection filtering (SHA256, first 8 bytes hex)
        let tokenHash = SHA256.hash(data: Data(muscle.authToken.utf8))
        let tokenHashPrefix = tokenHash.prefix(8).map { String(format: "%02x", $0) }.joined()
        if let data = tokenHashPrefix.data(using: .utf8) {
            txtDict["tokenhash"] = data
        }

        // Instance ID for human-readable identification
        if let data = effectiveInstanceId.data(using: .utf8) {
            txtDict["instanceid"] = data
        }

        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))

        netService = service
        netService?.publish()
        serverLog("Advertising as '\(serviceName)' on port \(port)")
    }

    // MARK: - Client Handling

    private func handleClientConnected(_ clientId: Int, respond: @escaping (Data) -> Void) {
        sendServerInfo(respond: respond)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleClientMessage(_ clientId: Int, data: Data, respond: @escaping (Data) -> Void) async {
        guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else {
            serverLog("Failed to decode client message")
            if String(data: data, encoding: .utf8) != nil {
                serverLog("Unparsable message: \(data.count) bytes")
            }
            return
        }

        serverLog("Received from client \(clientId): \(String(describing: message).prefix(40))")

        switch message {
        case .authenticate:
            break // Already authenticated via onUnauthenticatedData path
        case .requestInterface:
            serverLog("Interface requested by client \(clientId)")
            await sendInterface(respond: respond)
        case .subscribe:
            subscribedClients.insert(clientId)
            serverLog("Client \(clientId) subscribed (\(subscribedClients.count) subscribers)")
        case .unsubscribe:
            subscribedClients.remove(clientId)
            serverLog("Client \(clientId) unsubscribed (\(subscribedClients.count) subscribers)")
        case .ping:
            sendMessage(.pong, respond: respond)
        case .requestScreen:
            handleScreen(respond: respond)
        case .waitForIdle(let target):
            await handleWaitForIdle(target, respond: respond)

        // Interaction dispatch — TheSafecracker handles all actions, gestures, and text entry
        case .activate(let target):
            await performInteraction(respond: respond) { self.theSafecracker.executeActivate(target) }
        case .increment(let target):
            await performInteraction(respond: respond) { self.theSafecracker.executeIncrement(target) }
        case .decrement(let target):
            await performInteraction(respond: respond) { self.theSafecracker.executeDecrement(target) }
        case .performCustomAction(let target):
            await performInteraction(respond: respond) { self.theSafecracker.executeCustomAction(target) }
        case .editAction(let target):
            await performInteraction(respond: respond) { self.theSafecracker.executeEditAction(target) }
        case .resignFirstResponder:
            await performInteraction(respond: respond) { self.theSafecracker.executeResignFirstResponder() }
        case .touchTap(let target):
            await performInteraction(respond: respond) { self.theSafecracker.executeTap(target) }
        case .touchLongPress(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executeLongPress(target) }
        case .touchSwipe(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executeSwipe(target) }
        case .touchDrag(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executeDrag(target) }
        case .touchPinch(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executePinch(target) }
        case .touchRotate(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executeRotate(target) }
        case .touchTwoFingerTap(let target):
            await performInteraction(respond: respond) { self.theSafecracker.executeTwoFingerTap(target) }
        case .touchDrawPath(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executeDrawPath(target) }
        case .touchDrawBezier(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executeDrawBezier(target) }
        case .typeText(let target):
            await performInteraction(respond: respond) { await self.theSafecracker.executeTypeText(target) }
        }
    }

    // MARK: - Interaction Dispatch

    /// Standard interaction pattern: refresh → snapshot → execute → delta → respond
    /// TheSafecracker handles all interaction concerns (touch visualization, element refresh for read-back).
    private func performInteraction(
        respond: @escaping (Data) -> Void,
        interaction: () async -> TheSafecracker.InteractionResult
    ) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        let result = await interaction()

        if result.success {
            let actionResult = await actionResultWithDelta(
                success: true,
                method: result.method,
                message: result.message,
                value: result.value,
                beforeElements: beforeElements
            )
            sendMessage(.actionResult(actionResult), respond: respond)
        } else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: result.method,
                message: result.message,
                value: result.value
            )), respond: respond)
        }
    }

    private func sendServerInfo(respond: @escaping (Data) -> Void) {
        let screenBounds = UIScreen.main.bounds
        let info = ServerInfo(
            protocolVersion: protocolVersion,
            appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            deviceName: UIDevice.current.name,
            systemVersion: UIDevice.current.systemVersion,
            screenWidth: screenBounds.width,
            screenHeight: screenBounds.height,
            instanceId: sessionId.uuidString,
            instanceIdentifier: effectiveInstanceId,
            listeningPort: socketServer?.listeningPort,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            vendorIdentifier: UIDevice.current.identifierForVendor?.uuidString
        )
        sendMessage(.info(info), respond: respond)
    }

    func sendMessage(_ message: ServerMessage, respond: @escaping (Data) -> Void) {
        guard let data = try? JSONEncoder().encode(message) else {
            serverLog("Failed to encode message")
            return
        }
        serverLog("Sending \(data.count) bytes")
        respond(data)
    }

    /// Send data only to clients that have explicitly subscribed.
    func broadcastToSubscribed(_ data: Data) {
        for clientId in subscribedClients {
            socketServer?.send(data, to: clientId)
        }
    }

    // MARK: - Accessibility Observation

    private func startAccessibilityObservation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: UIAccessibility.elementFocusedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }

    private func stopAccessibilityObservation() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIAccessibility.elementFocusedNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilityDidChange() {
        scheduleHierarchyUpdate()
    }

    // MARK: - App Lifecycle

    private func startLifecycleObservation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    private func stopLifecycleObservation() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        serverLog("App entering background, suspending server")
        suspend()
    }

    @objc private func appWillEnterForeground() {
        serverLog("App entering foreground, resuming server")
        resume()
    }

    private func suspend() {
        guard isRunning, !isSuspended else { return }
        isSuspended = true

        pollingTask?.cancel()
        pollingTask = nil

        updateDebounceTask?.cancel()
        updateDebounceTask = nil

        socketServer?.stop()
        socketServer = nil

        netService?.stop()
        netService = nil

        subscribedClients.removeAll()
        muscle.tearDown()

        stopAccessibilityObservation()

        cachedElements.removeAll()
        interactiveObjects.removeAll()
        lastHierarchyHash = 0

        serverLog("Server suspended")
    }

    private func resume() {
        guard isRunning, isSuspended else { return }
        isSuspended = false

        serverLog("Resuming server...")

        do {
            let server = SimpleSocketServer()
            wireServer(server)

            let actualPort = try server.start(port: effectivePort, bindToLoopback: shouldBindToLoopback)
            self.socketServer = server

            serverLog("Server resumed on port \(actualPort)")
            advertiseService(port: actualPort)

            startAccessibilityObservation()

            if isPollingEnabled {
                startPollingLoop()
            }

            serverLog("Server resume complete")
        } catch {
            serverLog("Failed to resume server: \(error)")
            isRunning = false
            isSuspended = false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
