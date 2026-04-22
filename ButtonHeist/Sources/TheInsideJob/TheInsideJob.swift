#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

import AccessibilitySnapshotParser

let insideJobLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "server")

/// The job itself — assembles the crew, manages the operation lifecycle.
///
/// TheInsideJob is the public API singleton. It creates every crew member,
/// wires them together, and manages server start/stop/suspend/resume.
/// All message routing and network I/O is delegated to TheGetaway.
@MainActor
public final class TheInsideJob {

    // MARK: - Singleton

    private static var _shared: TheInsideJob?

    public static var shared: TheInsideJob {
        if let existing = _shared { return existing }
        let instance = TheInsideJob()
        _shared = instance
        return instance
    }

    public static func configure(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        forceSwipeScrolling: Bool? = nil
    ) {
        if _shared != nil {
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
            return
        }
        _shared = TheInsideJob(
            token: token,
            instanceId: instanceId,
            allowedScopes: allowedScopes,
            port: port,
            forceSwipeScrolling: forceSwipeScrolling
        )
    }

    // MARK: - State Machines

    enum ServerPhase {
        case stopped
        case running(transport: ServerTransport)
        case suspended
        case resuming(task: Task<Void, Never>)
    }

    enum PollingPhase {
        case disabled
        case active(task: Task<Void, Never>, interval: TimeInterval)
        case paused(interval: TimeInterval)
    }

    // MARK: - Properties

    var serverPhase: ServerPhase = .stopped
    var pollingPhase: PollingPhase = .disabled
    private var tlsActive = false

    // The crew
    let muscle: TheMuscle
    let tripwire = TheTripwire()
    let brains: TheBrains
    let getaway: TheGetaway

    private let instanceId: String?
    private let preferredPort: UInt16
    private let installationId: String
    private let sessionId = UUID()
    private let allowedScopes: Set<ConnectionScope>
    private let forceSwipeScrolling: Bool

    // MARK: - Computed State

    private var isRunning: Bool {
        switch serverPhase {
        case .running, .suspended, .resuming: return true
        case .stopped: return false
        }
    }

    private var transport: ServerTransport? {
        if case .running(let transport) = serverPhase { return transport }
        return nil
    }

    var isPollingEnabled: Bool {
        switch pollingPhase {
        case .active, .paused: return true
        case .disabled: return false
        }
    }

    var pollingTimeoutSeconds: TimeInterval {
        switch pollingPhase {
        case .active(_, let interval), .paused(let interval): return interval
        case .disabled: return Self.defaultPollingTimeout
        }
    }

    /// Recording phase lives on TheGetaway — convenience accessors for tests.
    var recordingPhase: TheGetaway.RecordingPhase {
        get { getaway.recordingPhase }
        set { getaway.recordingPhase = newValue }
    }

    var stakeout: TheStakeout? { getaway.stakeout }

    private static let defaultPollingTimeout: TimeInterval = 2.0

    // MARK: - Initialization

    public init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        forceSwipeScrolling: Bool? = nil
    ) {
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.preferredPort = port
        self.installationId = Self.loadInstallationId()
        self.forceSwipeScrolling = Self.resolveForceSwipeScrolling(explicit: forceSwipeScrolling)
        self.brains = TheBrains(
            tripwire: self.tripwire,
            forceSwipeScrolling: self.forceSwipeScrolling
        )
        self.getaway = TheGetaway(
            muscle: self.muscle, brains: self.brains, tripwire: self.tripwire,
            identity: TheGetaway.ServerIdentity(
                sessionId: self.sessionId,
                effectiveInstanceId: instanceId ?? String(self.sessionId.uuidString.prefix(8)).lowercased(),
                tlsActive: false
            )
        )

        if let scopes = allowedScopes {
            self.allowedScopes = scopes
        } else if let envValue = EnvironmentKey.insideJobScope.value,
                  let parsed = ConnectionScope.parse(envValue) {
            self.allowedScopes = parsed
        } else {
            self.allowedScopes = ConnectionScope.default
        }
    }

    private static func resolveForceSwipeScrolling(explicit: Bool?) -> Bool {
        if let explicit { return explicit }
        let envKey = EnvironmentKey.insideJobForceSwipeScrolling
        if envKey.value != nil { return envKey.boolValue }
        if let plist = Bundle.main.object(
            forInfoDictionaryKey: "InsideJobForceSwipeScrolling"
        ) as? Bool {
            return plist
        }
        return false
    }

    // MARK: - Public API

    public func start() async throws {
        guard case .stopped = serverPhase else {
            insideJobLogger.info("start() called while already running — ignoring")
            return
        }

        insideJobLogger.info("Starting TheInsideJob with ServerTransport...")

        let identity: TLSIdentity
        do {
            identity = try TLSIdentity.getOrCreate()
            insideJobLogger.info("TLS identity ready: \(identity.fingerprint)")
        } catch {
            insideJobLogger.warning("Keychain identity failed, using ephemeral: \(error)")
            identity = try TLSIdentity.createEphemeral()
        }
        self.tlsActive = true
        getaway.identity.tlsActive = true
        let transport = ServerTransport(tlsIdentity: identity, allowedScopes: allowedScopes)
        getaway.wireTransport(transport)

        let useLoopback = allowedScopes == [.simulator]
        let actualPort = try await transport.start(port: preferredPort, bindToLoopback: useLoopback)
        serverPhase = .running(transport: transport)

        let scopeNames = allowedScopes.map(\.rawValue).sorted().joined(separator: ", ")
        insideJobLogger.info("Connection scopes: \(scopeNames)")
        if forceSwipeScrolling {
            insideJobLogger.info("Scroll strategy override: force swipe scrolling")
        }
        insideJobLogger.info("Server listening on port \(actualPort)")
        insideJobLogger.info("Connect with session token: \(self.muscle.sessionToken, privacy: .public)")
        insideJobLogger.info("Instance ID: \(self.effectiveInstanceId)")
        advertiseService(port: actualPort)

        UIApplication.shared.isIdleTimerDisabled = true

        startAccessibilityObservation()
        startLifecycleObservation()

        tripwire.onTransition = { [weak self] transition in
            self?.handlePulseTransition(transition)
        }
        tripwire.startPulse()
        brains.startKeyboardObservation()

        insideJobLogger.info("Server started successfully")
    }

    public func stop() {
        if case .resuming(let task) = serverPhase {
            task.cancel()
        }

        if case .running(let activeTransport) = serverPhase {
            activeTransport.stopAdvertising()
            activeTransport.stop()
        }

        serverPhase = .stopped
        stopPolling()

        tripwire.stopPulse()
        tripwire.onTransition = nil
        brains.stopKeyboardObservation()

        muscle.tearDown()
        getaway.tearDown()

        stopAccessibilityObservation()
        stopLifecycleObservation()

        insideJobLogger.info("Server stopped")
    }

    public func notifyChange() {
        guard isRunning else { return }
        getaway.hierarchyInvalidated = true
    }

    public func startPolling(interval timeout: TimeInterval = 2.0) {
        if case .active(let existingTask, _) = pollingPhase {
            existingTask.cancel()
        }
        let interval = max(0.5, timeout)
        let task = makePollingTask(interval: interval)
        pollingPhase = .active(task: task, interval: interval)
        insideJobLogger.info("Polling enabled (settle timeout: \(interval)s)")
    }

    public func stopPolling() {
        if case .active(let task, _) = pollingPhase {
            task.cancel()
        }
        pollingPhase = .disabled
    }

    // MARK: - Pulse Handling

    private func handlePulseTransition(_ transition: TheTripwire.PulseTransition) {
        if case .settled = transition, getaway.hierarchyInvalidated {
            getaway.broadcastIfChanged()
        }
    }

    func makePollingTask(interval: TimeInterval) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isPollingEnabled && !Task.isCancelled {
                let settled = await self.tripwire.waitForAllClear(timeout: interval)
                guard !Task.isCancelled, self.isPollingEnabled else { break }
                if settled {
                    self.getaway.broadcastIfChanged()
                }
            }
        }
    }

    // MARK: - Service Advertisement

    private var shortId: String {
        String(sessionId.uuidString.prefix(8)).lowercased()
    }

    var effectiveInstanceId: String {
        instanceId ?? shortId
    }

    private static func loadInstallationId() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.buttonheist.theinsidejob"
        let defaultsKey = "\(bundleId).installation-id"

        if let existing = UserDefaults.standard.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: defaultsKey)
        return generated
    }

    private func advertiseService(port: UInt16) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let serviceName = "\(appName)#\(effectiveInstanceId)"

        transport?.advertise(
            serviceName: serviceName,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            installationId: installationId,
            instanceId: effectiveInstanceId,
            additionalTXT: [
                "devicename": UIDevice.current.name
            ]
        )
    }

    // MARK: - Accessibility Observation

    private func startAccessibilityObservation() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessibilityDidChange),
            name: UIAccessibility.elementFocusedNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessibilityDidChange),
            name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil
        )
    }

    private func stopAccessibilityObservation() {
        NotificationCenter.default.removeObserver(self, name: UIAccessibility.elementFocusedNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
    }

    @objc private func accessibilityDidChange() {
        getaway.hierarchyInvalidated = true
    }

    // MARK: - App Lifecycle

    private func startLifecycleObservation() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification, object: nil
        )
    }

    private func stopLifecycleObservation() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        insideJobLogger.info("App entering background, suspending server")
        suspend()
    }

    @objc private func appWillEnterForeground() {
        insideJobLogger.info("App entering foreground, resuming server")
        resume()
    }

    @objc private func appWillTerminate() {
        insideJobLogger.info("App will terminate, stopping server")
        stop()
    }

    // MARK: - Suspend / Resume

    func suspend() {
        switch serverPhase {
        case .running(let activeTransport):
            activeTransport.stopAdvertising()
            activeTransport.stop()
        case .resuming(let task):
            task.cancel()
        case .stopped, .suspended:
            return
        }

        if case .active(let pollingTask, let interval) = pollingPhase {
            pollingTask.cancel()
            pollingPhase = .paused(interval: interval)
        }

        tripwire.stopPulse()
        brains.stopKeyboardObservation()

        muscle.tearDown()
        getaway.tearDown()

        stopAccessibilityObservation()

        brains.clearCache()

        serverPhase = .suspended

        insideJobLogger.info("Server suspended")
    }

    private func resume() {
        guard case .suspended = serverPhase else { return }

        insideJobLogger.info("Resuming server...")

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var startedTransport: ServerTransport?
            do {
                try Task.checkCancellation()

                let identity: TLSIdentity
                do {
                    identity = try TLSIdentity.getOrCreate()
                } catch {
                    insideJobLogger.warning("Keychain identity failed on resume, using ephemeral: \(error)")
                    identity = try TLSIdentity.createEphemeral()
                }

                try Task.checkCancellation()

                self.tlsActive = true
                self.getaway.identity.tlsActive = true

                let transport = ServerTransport(tlsIdentity: identity, allowedScopes: self.allowedScopes)
                self.getaway.wireTransport(transport)
                startedTransport = transport

                let useLoopback = self.allowedScopes == [.simulator]
                let actualPort = try await transport.start(port: preferredPort, bindToLoopback: useLoopback)

                try Task.checkCancellation()

                self.serverPhase = .running(transport: transport)
                startedTransport = nil

                insideJobLogger.info("Server resumed on port \(actualPort)")
                self.advertiseService(port: actualPort)

                self.startAccessibilityObservation()

                self.tripwire.onTransition = { [weak self] transition in
                    self?.handlePulseTransition(transition)
                }
                self.tripwire.startPulse()
                self.brains.startKeyboardObservation()

                if case .paused(let interval) = self.pollingPhase {
                    let pollingTask = self.makePollingTask(interval: interval)
                    self.pollingPhase = .active(task: pollingTask, interval: interval)
                }

                insideJobLogger.info("Server resume complete")
            } catch is CancellationError {
                startedTransport?.stop()
                insideJobLogger.info("Server resume cancelled")
            } catch {
                startedTransport?.stop()
                insideJobLogger.error("Failed to resume server: \(error)")
                if case .resuming = self.serverPhase {
                    self.serverPhase = .suspended
                }
            }
        }
        serverPhase = .resuming(task: task)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
