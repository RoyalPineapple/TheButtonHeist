#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

import AccessibilitySnapshotParser

let insideJobLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "server")

enum InsideJobStartupError: Error, LocalizedError, Equatable, Sendable {
    case tlsIdentityUnavailable(phase: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .tlsIdentityUnavailable(let phase, let reason):
            return "TLS identity unavailable during \(phase); listener was not started and Bonjour was not published. \(reason)"
        }
    }
}

/// The job itself — assembles the crew, manages the operation lifecycle.
///
/// TheInsideJob is the public API singleton. It creates every crew member,
/// wires them together, and manages server start/stop/suspend/resume.
/// All message routing and network I/O is delegated to TheGetaway.
@MainActor
public final class TheInsideJob {

    // MARK: - Singleton

    /// Pre-init configuration captured by ``configure(...)`` and consumed at
    /// the first ``shared`` access. Once `shared` resolves, the state pins to
    /// `.live` for the process lifetime and further `configure` calls are
    /// ignored with a warning.
    struct ConfigureArgs: Sendable {
        let token: String?
        let instanceId: String?
        let allowedScopes: Set<ConnectionScope>?
        let port: UInt16
        let startupConfiguration: StartupConfiguration?
    }

    enum SharedState {
        case pending(ConfigureArgs?)
        case live(TheInsideJob)
    }

    private static var sharedState: SharedState = .pending(nil)

    public static var shared: TheInsideJob {
        switch sharedState {
        case .live(let existing):
            return existing
        case .pending(let args):
            let instance = if let configuration = args?.startupConfiguration {
                TheInsideJob(startupConfiguration: configuration)
            } else {
                TheInsideJob(
                    token: args?.token,
                    instanceId: args?.instanceId,
                    allowedScopes: args?.allowedScopes,
                    port: args?.port ?? 0
                )
            }
            sharedState = .live(instance)
            return instance
        }
    }

    public static func configure(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0
    ) {
        let args = ConfigureArgs(
            token: token,
            instanceId: instanceId,
            allowedScopes: allowedScopes,
            port: port,
            startupConfiguration: nil
        )
        switch sharedState {
        case .pending:
            sharedState = .pending(args)
        case .live:
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
        }
    }

    static func configure(startupConfiguration: StartupConfiguration) {
        let args = ConfigureArgs(
            token: startupConfiguration.token.value,
            instanceId: startupConfiguration.instanceId.value,
            allowedScopes: startupConfiguration.allowedScopes.value,
            port: startupConfiguration.preferredPort.value,
            startupConfiguration: startupConfiguration
        )
        switch sharedState {
        case .pending:
            sharedState = .pending(args)
        case .live:
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
        }
    }

    // MARK: - State Machines

    enum ServerPhase {
        case stopped
        case running(transport: ServerTransport)
        case suspended
        case resuming(id: UUID, task: Task<Void, Never>)
    }

    enum PollingPhase {
        case disabled
        case active(task: Task<Void, Never>, interval: TimeInterval)
        case paused(interval: TimeInterval)
    }

    /// Idle-timer baseline state. We force `UIApplication.isIdleTimerDisabled`
    /// on while the server is running so the device doesn't sleep mid-session,
    /// and restore the prior value on suspend/stop.
    enum IdleTimerProtection {
        case unmodified
        case engaged(baseline: Bool)
    }

    /// Tracks @objc lifecycle bridge Tasks that must finish before start/resume reads `serverPhase`.
    @MainActor
    final class LifecycleBoundaryTasks {
        private var tasks: [UInt64: Task<Void, Never>] = [:]
        private var nextTaskId: UInt64 = 0

        var isEmpty: Bool { tasks.isEmpty }

        func spawn(_ body: @escaping @MainActor () async -> Void) {
            nextTaskId &+= 1
            let id = nextTaskId
            let task = Task { @MainActor [weak self] in
                await body()
                self?.tasks.removeValue(forKey: id)
            }
            tasks[id] = task
        }

        func drain() async {
            while !tasks.isEmpty {
                let snapshot = Array(tasks.values)
                tasks.removeAll()
                for task in snapshot {
                    await task.value
                }
            }
        }
    }

    // MARK: - Properties

    var serverPhase: ServerPhase = .stopped
    var pollingPhase: PollingPhase = .disabled

    // The crew
    let muscle: TheMuscle
    let tripwire = TheTripwire()
    let brains: TheBrains
    let getaway: TheGetaway

    private let instanceId: String?
    private let preferredPort: UInt16
    private let tokenSource: StartupConfigurationSource
    private let instanceIdSource: StartupConfigurationSource
    private let preferredPortSource: StartupConfigurationSource
    private let allowedScopesSource: StartupConfigurationSource
    private let pollingInterval: ResolvedStartupValue<TimeInterval>?
    private let sessionReleaseTimeout: ResolvedStartupValue<TimeInterval>
    private let tlsIdentityProvider: @MainActor () throws -> TLSIdentity
    private let transportFactory: @MainActor (TLSIdentity, Set<ConnectionScope>) -> ServerTransport
    private let installationId: String
    private let sessionId = UUID()
    private let allowedScopes: Set<ConnectionScope>
    private var pendingTransportStopTask: Task<Void, Never>?
    private let lifecycleBoundaryTasks = LifecycleBoundaryTasks()
    /// The Task spawned from `appWillEnterForeground` to bridge `@objc` ->
    /// `async resume()`. Kept out of `lifecycleBoundaryTasks` so `resume()`'s
    /// own drain cannot deadlock by awaiting its own handle. Tests observe
    /// it to wait on a foreground resume cycle synchronously.
    var pendingForegroundResumeTask: Task<Void, Never>?
    private var idleTimerProtection: IdleTimerProtection = .unmodified

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
        getaway.recordingPhase
    }

    var stakeout: TheStakeout? { getaway.stakeout }

    /// Test hook: exposes whether lifecycle bridge Tasks have self-removed
    /// without exposing the underlying tracker.
    var pendingLifecycleTasksIsEmpty: Bool { lifecycleBoundaryTasks.isEmpty }
    var pendingTransportStopTaskIsEmpty: Bool { pendingTransportStopTask == nil }

    private static let defaultPollingTimeout: TimeInterval = 2.0

    // MARK: - Initialization

    public convenience init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0
    ) {
        self.init(
            token: token,
            instanceId: instanceId,
            allowedScopes: allowedScopes,
            port: port,
            tlsIdentityProvider: Self.defaultTLSIdentityProvider
        )
    }

    convenience init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        tlsIdentityProvider: @escaping @MainActor () throws -> TLSIdentity,
        transportFactory: @escaping @MainActor (TLSIdentity, Set<ConnectionScope>) -> ServerTransport = {
            ServerTransport(tlsIdentity: $0, allowedScopes: $1)
        }
    ) {
        let startupConfiguration = StartupConfiguration.resolve()
        self.init(
            token: token,
            tokenSource: token == nil ? .generated : .api,
            instanceId: instanceId,
            instanceIdSource: instanceId == nil ? .generated : .api,
            allowedScopes: allowedScopes ?? startupConfiguration.allowedScopes.value,
            allowedScopesSource: allowedScopes == nil ? startupConfiguration.allowedScopes.source : .api,
            port: port,
            preferredPortSource: port == 0 ? .defaultValue : .api,
            pollingInterval: nil,
            sessionReleaseTimeout: startupConfiguration.sessionTimeout,
            tlsIdentityProvider: tlsIdentityProvider,
            transportFactory: transportFactory
        )
    }

    convenience init(startupConfiguration: StartupConfiguration) {
        self.init(
            token: startupConfiguration.token.value,
            tokenSource: startupConfiguration.token.source,
            instanceId: startupConfiguration.instanceId.value,
            instanceIdSource: startupConfiguration.instanceId.source,
            allowedScopes: startupConfiguration.allowedScopes.value,
            allowedScopesSource: startupConfiguration.allowedScopes.source,
            port: startupConfiguration.preferredPort.value,
            preferredPortSource: startupConfiguration.preferredPort.source,
            pollingInterval: startupConfiguration.pollingInterval,
            sessionReleaseTimeout: startupConfiguration.sessionTimeout,
            tlsIdentityProvider: Self.defaultTLSIdentityProvider
        )
    }

    private init(
        token: String?,
        tokenSource: StartupConfigurationSource,
        instanceId: String?,
        instanceIdSource: StartupConfigurationSource,
        allowedScopes: Set<ConnectionScope>,
        allowedScopesSource: StartupConfigurationSource,
        port: UInt16,
        preferredPortSource: StartupConfigurationSource,
        pollingInterval: ResolvedStartupValue<TimeInterval>?,
        sessionReleaseTimeout: ResolvedStartupValue<TimeInterval>,
        tlsIdentityProvider: @escaping @MainActor () throws -> TLSIdentity,
        transportFactory: @escaping @MainActor (TLSIdentity, Set<ConnectionScope>) -> ServerTransport = {
            ServerTransport(tlsIdentity: $0, allowedScopes: $1)
        }
    ) {
        self.muscle = TheMuscle(
            explicitToken: token,
            sessionReleaseTimeout: sessionReleaseTimeout.value
        )
        self.instanceId = instanceId
        self.preferredPort = port
        self.tokenSource = tokenSource
        self.instanceIdSource = instanceIdSource
        self.preferredPortSource = preferredPortSource
        self.allowedScopesSource = allowedScopesSource
        self.pollingInterval = pollingInterval
        self.sessionReleaseTimeout = sessionReleaseTimeout
        self.tlsIdentityProvider = tlsIdentityProvider
        self.transportFactory = transportFactory
        self.installationId = Self.loadInstallationId()
        self.brains = TheBrains(tripwire: self.tripwire)
        self.getaway = TheGetaway(
            muscle: self.muscle, brains: self.brains, tripwire: self.tripwire,
            identity: TheGetaway.ServerIdentity(
                sessionId: self.sessionId,
                effectiveInstanceId: instanceId ?? String(self.sessionId.uuidString.prefix(8)).lowercased(),
                tlsActive: false
            )
        )
        self.allowedScopes = allowedScopes
    }

    // MARK: - Public API

    public func start() async throws {
        // Drain any in-flight stop/suspend Tasks spawned by @objc lifecycle
        // observers before we re-check serverPhase — a terminate-then-launch
        // race must observe the post-stop state.
        await awaitPendingLifecycleTasks()

        guard case .stopped = serverPhase else {
            insideJobLogger.info("start() called while already running — ignoring")
            return
        }

        if let pendingTransportStopTask {
            await pendingTransportStopTask.value
            self.pendingTransportStopTask = nil
        }

        insideJobLogger.info("Starting TheInsideJob with ServerTransport...")

        let identity = try makeTLSIdentity(phase: "startup")
        insideJobLogger.info("TLS identity ready: \(identity.fingerprint)")
        let transport = transportFactory(identity, allowedScopes)
        installTransportOverflowHandler(transport)
        await getaway.wireTransport(transport)

        let exposure = ServerExposure(allowedScopes: allowedScopes)
        let actualPort: UInt16
        do {
            actualPort = try await transport.start(port: preferredPort, bindToLoopback: exposure.bindsToLoopbackOnly)
        } catch {
            await cleanupFailedTransportStartup(transport)
            serverPhase = .stopped
            throw error
        }
        getaway.identity.tlsActive = true
        serverPhase = .running(transport: transport)

        let serviceName = advertiseService(port: actualPort, exposure: exposure)
        logStartupSummary(
            actualPort: actualPort,
            tlsFingerprint: identity.fingerprint,
            bonjourServiceName: serviceName
        )

        engageIdleTimerProtection()

        startAccessibilityObservation()
        startLifecycleObservation()

        tripwire.onTransition = { [weak self] transition in
            self?.handlePulseTransition(transition)
        }
        tripwire.startPulse()
        brains.startKeyboardObservation()

        insideJobLogger.info("Server started successfully")
    }

    public func stop() async {
        if case .resuming(_, let task) = serverPhase {
            task.cancel()
        }

        let bridge = pendingForegroundResumeTask
        pendingForegroundResumeTask = nil
        bridge?.cancel()
        await bridge?.value

        if case .running(let activeTransport) = serverPhase {
            pendingTransportStopTask = activeTransport.stop()
        }

        serverPhase = .stopped
        stopPolling()

        tripwire.stopPulse()
        tripwire.onTransition = nil
        brains.stopKeyboardObservation()

        await muscle.tearDown()
        await getaway.tearDown()

        stopAccessibilityObservation()
        stopLifecycleObservation()
        restoreIdleTimerProtection(clearBaseline: true)

        insideJobLogger.info("Server stopped")
    }

    public func notifyChange() {
        guard isRunning else { return }
        getaway.noteBackgroundChange()
        if canRunSettledBackgroundParse, tripwire.latestReading?.isSettled == true {
            let getaway = self.getaway
            Task { await getaway.noteSettledChangeIfNeeded() }
        }
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
        switch transition {
        case .tripwireTriggered:
            getaway.noteBackgroundChange()
            if canRunSettledBackgroundParse, tripwire.latestReading?.isSettled == true {
                let getaway = self.getaway
                Task { await getaway.noteSettledChangeIfNeeded() }
            }
        case .unsettled:
            getaway.noteBackgroundChange()
        case .settled where getaway.hasPendingBackgroundChange && canRunSettledBackgroundParse:
            let getaway = self.getaway
            Task { await getaway.noteSettledChangeIfNeeded() }
        case .settled:
            break
        }
    }

    func makePollingTask(interval: TimeInterval) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isPollingEnabled && !Task.isCancelled {
                let settled = await self.tripwire.waitForAllClear(timeout: interval)
                guard !Task.isCancelled, self.isPollingEnabled else { break }
                if settled && self.canRunSettledBackgroundParse {
                    await self.getaway.noteSettledChangeIfNeeded()
                }
            }
        }
    }

    private var canRunSettledBackgroundParse: Bool {
        Self.canRunSettledBackgroundParse(
            isRunning: isRunning,
            applicationState: UIApplication.shared.applicationState,
            backgroundChangeState: getaway.backgroundChangeState
        )
    }

    static func canRunSettledBackgroundParse(
        isRunning: Bool,
        applicationState: UIApplication.State,
        backgroundChangeState: BackgroundChangeState
    ) -> Bool {
        isRunning
            && applicationState == .active
            && backgroundChangeState.canBeginSettledParse
    }

    // MARK: - Service Advertisement

    private var shortId: String {
        String(sessionId.uuidString.prefix(8)).lowercased()
    }

    var effectiveInstanceId: String {
        instanceId ?? shortId
    }

    private static func defaultTLSIdentityProvider() throws -> TLSIdentity {
        do {
            return try TLSIdentity.getOrCreate()
        } catch {
            insideJobLogger.warning("Stored TLS identity failed, trying ephemeral identity: \(error.localizedDescription, privacy: .public)")
            do {
                return try TLSIdentity.createEphemeral()
            } catch {
                throw InsideJobStartupError.tlsIdentityUnavailable(
                    phase: "identity-creation",
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func makeTLSIdentity(phase: String) throws -> TLSIdentity {
        do {
            return try tlsIdentityProvider()
        } catch let error as InsideJobStartupError {
            getaway.identity.tlsActive = false
            throw error
        } catch {
            getaway.identity.tlsActive = false
            throw InsideJobStartupError.tlsIdentityUnavailable(
                phase: phase,
                reason: error.localizedDescription
            )
        }
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

    @discardableResult
    private func advertiseService(port: UInt16, exposure: ServerExposure) -> String? {
        guard exposure.publishesBonjour else {
            insideJobLogger.info("Bonjour advertisement disabled: \(exposure.bonjourDisabledReason ?? "unknown", privacy: .public)")
            return nil
        }

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

        return serviceName
    }

    private func logStartupSummary(
        actualPort: UInt16,
        tlsFingerprint: String,
        bonjourServiceName: String?
    ) {
        let scopeNames = allowedScopes.map(\.rawValue).sorted().joined(separator: ",")
        let pollingDescription = pollingInterval.map {
            "\($0.value)s(\($0.source.label))"
        } ?? "not-started"
        let bonjourDescription = if let bonjourServiceName {
            "bonjour=advertising service=\(bonjourServiceName)"
        } else {
            "bonjour=disabled reason=network-scope-not-enabled"
        }
        let fields = [
            "actualPort=\(actualPort)",
            "preferredPort=\(preferredPort)(\(preferredPortSource.label))",
            "tokenSource=\(tokenSource.label)",
            "sessionId=\(sessionId.uuidString)",
            "instanceIdentifier=\(effectiveInstanceId)(\(instanceIdSource.label))",
            "allowedScopes=\(scopeNames)(\(allowedScopesSource.label))",
            "pollingInterval=\(pollingDescription)",
            "sessionTimeout=\(sessionReleaseTimeout.value)s(\(sessionReleaseTimeout.source.label))",
            "tls=enabled fingerprint=\(tlsFingerprint)",
            bonjourDescription
        ].joined(separator: " ")
        if tokenSource == .generated {
            insideJobLogger.info("Startup summary: \(fields, privacy: .public) token=<redacted>")
        } else {
            insideJobLogger.info("Startup summary: \(fields, privacy: .public)")
        }
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
        getaway.noteBackgroundChange()
        if canRunSettledBackgroundParse, tripwire.latestReading?.isSettled == true {
            let getaway = self.getaway
            Task { await getaway.noteSettledChangeIfNeeded() }
        }
    }

    // MARK: - App Lifecycle

    private func startLifecycleObservation() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification, object: nil
        )
    }

    private func stopLifecycleObservation() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
    }

    @objc private func appWillResignActive() {
        beginLifecycleSuspension()
    }

    @objc private func appDidEnterBackground() {
        beginLifecycleSuspension()
    }

    private func beginLifecycleSuspension() {
        guard beginSuspension() else { return }
        spawnLifecycleTask { [weak self] in
            await self?.finishSuspension()
        }
    }

    @objc private func appWillEnterForeground() {
        // resume() drains lifecycleBoundaryTasks itself before checking phase,
        // so the foreground bridge Task is NOT enrolled in that tracker —
        // enrolling it would force resume()'s drain to await its own handle
        // and deadlock. Tracked entries are reserved for shutdown wrappers
        // (suspend/stop) that start()/resume() observe before re-arming. We
        // store the handle in a dedicated field so tests can observe it.
        scheduleForegroundResume(replacingExisting: true)
    }

    @objc private func appDidBecomeActive() {
        scheduleForegroundResume(replacingExisting: false)
    }

    private func scheduleForegroundResume(replacingExisting: Bool) {
        if replacingExisting {
            pendingForegroundResumeTask?.cancel()
        } else if pendingForegroundResumeTask != nil {
            return
        }
        pendingForegroundResumeTask = Task { @MainActor [weak self] in
            await self?.resume()
            self?.pendingForegroundResumeTask = nil
        }
    }

    @objc private func appWillTerminate() {
        insideJobLogger.info("App will terminate, stopping server")
        spawnLifecycleTask { [weak self] in
            await self?.stop()
        }
    }

    /// Spawn a Task that wraps an async lifecycle transition. The handle is
    /// retained in `lifecycleBoundaryTasks` so callers that resume the server
    /// (`start()` / `resume()`) can await prior shutdowns before they begin.
    ///
    /// Each Task removes itself from the set on completion so handles do not
    /// accumulate across many lifecycle transitions. The self-removal runs
    /// after `body()` returns, on the same `@MainActor` isolation as the set,
    /// so `awaitPendingLifecycleTasks()` callers either see the live handle
    /// (and await it) or see it already gone (because it finished).
    func spawnLifecycleTask(_ body: @escaping @MainActor () async -> Void) {
        lifecycleBoundaryTasks.spawn(body)
    }

    /// Wait for any in-flight lifecycle tasks (suspend/stop wrappers spawned
    /// from @objc handlers) to finish before mutating server phase. Loops so
    /// observer-spawned Tasks that arrive during the drain are also awaited.
    private func awaitPendingLifecycleTasks() async {
        await lifecycleBoundaryTasks.drain()
    }

    // MARK: - Suspend / Resume

    func suspend() async {
        guard beginSuspension() else { return }
        await finishSuspension()
    }

    @discardableResult
    private func beginSuspension() -> Bool {
        switch serverPhase {
        case .running(let activeTransport):
            pendingTransportStopTask = activeTransport.stop()
        case .resuming(_, let task):
            task.cancel()
        case .stopped, .suspended:
            return false
        }

        if case .active(let pollingTask, let interval) = pollingPhase {
            pollingTask.cancel()
            pollingPhase = .paused(interval: interval)
        }

        tripwire.stopPulse()
        brains.stopKeyboardObservation()

        stopAccessibilityObservation()

        brains.clearCache()
        restoreIdleTimerProtection(clearBaseline: false)

        serverPhase = .suspended

        return true
    }

    private func finishSuspension() async {
        await muscle.tearDown()
        await getaway.tearDown()

        insideJobLogger.info("Server suspended")
    }

    func resume() async {
        // Drain any in-flight suspend Task spawned from @objc background
        // observers BEFORE checking serverPhase. A rapid background→foreground
        // cycle delivers `appDidEnterBackground` and `appWillEnterForeground`
        // back-to-back on the @MainActor; the suspend wrapper Task may not have
        // run its body yet, so `serverPhase` is still `.running` when resume
        // arrives. Without this drain we'd fall through the `.suspended` guard
        // and silently no-op, leaving the server dead after foreground.
        await awaitPendingLifecycleTasks()

        guard case .suspended = serverPhase else { return }

        insideJobLogger.info("Resuming server...")

        let resumeID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var startedTransport: ServerTransport?
            do {
                try Task.checkCancellation()

                if let pendingTransportStopTask {
                    await pendingTransportStopTask.value
                    self.pendingTransportStopTask = nil
                }

                let identity = try self.makeTLSIdentity(phase: "resume")

                try Task.checkCancellation()

                let transport = self.transportFactory(identity, self.allowedScopes)
                self.installTransportOverflowHandler(transport)
                await self.getaway.wireTransport(transport)
                startedTransport = transport

                let exposure = ServerExposure(allowedScopes: self.allowedScopes)
                let actualPort = try await transport.start(
                    port: preferredPort,
                    bindToLoopback: exposure.bindsToLoopbackOnly
                )

                try Task.checkCancellation()

                guard self.isCurrentResumeAttempt(resumeID) else {
                    if let startedTransport {
                        await self.cleanupFailedTransportStartup(startedTransport)
                    }
                    return
                }

                self.getaway.identity.tlsActive = true
                self.serverPhase = .running(transport: transport)
                startedTransport = nil

                insideJobLogger.info("Server resumed on port \(actualPort)")
                self.advertiseService(port: actualPort, exposure: exposure)

                self.startAccessibilityObservation()
                self.engageIdleTimerProtection()

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
                await self.cleanupFailedTransportStartup(startedTransport)
                startedTransport = nil
                self.finishFailedResumeAttempt(resumeID, startedTransport: startedTransport)
                insideJobLogger.info("Server resume cancelled")
            } catch {
                insideJobLogger.error("Failed to resume server: \(error)")
                await self.cleanupFailedTransportStartup(startedTransport)
                startedTransport = nil
                self.finishFailedResumeAttempt(resumeID, startedTransport: startedTransport)
            }
        }
        serverPhase = .resuming(id: resumeID, task: task)
    }

    private func installTransportOverflowHandler(_ transport: ServerTransport) {
        transport.setEventBacklogOverflowHandler { [weak self] maxEvents in
            await self?.handleTransportEventBacklogOverflow(maxEvents: maxEvents)
        }
    }

    func handleTransportEventBacklogOverflow(maxEvents: Int) async {
        insideJobLogger.error("Transport event backlog exceeded \(maxEvents), stopping server")
        await stop()
    }

    private func cleanupFailedTransportStartup(_ transport: ServerTransport?) async {
        if let transport {
            let stopTask = transport.stop()
            await stopTask.value
            await getaway.tearDownIfWired(to: transport)
        }
        getaway.identity.tlsActive = false
    }

    func isCurrentResumeAttempt(_ resumeID: UUID) -> Bool {
        guard case .resuming(let currentID, _) = serverPhase else { return false }
        return currentID == resumeID
    }

    func finishFailedResumeAttempt(_ resumeID: UUID, startedTransport: ServerTransport?) {
        let stopTask = startedTransport?.stop()
        if let stopTask {
            if let existingStopTask = pendingTransportStopTask {
                pendingTransportStopTask = Task {
                    await existingStopTask.value
                    await stopTask.value
                }
            } else {
                pendingTransportStopTask = stopTask
            }
        }
        guard isCurrentResumeAttempt(resumeID) else { return }
        serverPhase = .suspended
    }

    private func engageIdleTimerProtection() {
        if case .unmodified = idleTimerProtection {
            idleTimerProtection = .engaged(baseline: UIApplication.shared.isIdleTimerDisabled)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func restoreIdleTimerProtection(clearBaseline: Bool) {
        guard case .engaged(let baseline) = idleTimerProtection else { return }
        UIApplication.shared.isIdleTimerDisabled = baseline
        if clearBaseline {
            idleTimerProtection = .unmodified
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
