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

    /// Pre-init configuration captured by ``configure(...)`` and consumed at
    /// the first ``shared`` access. Once `shared` resolves, the state pins to
    /// `.live` for the process lifetime and further `configure` calls are
    /// ignored with a warning.
    struct ConfigureArgs: Sendable {
        let token: String?
        let instanceId: String?
        let allowedScopes: Set<ConnectionScope>?
        let port: UInt16
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
            let instance = TheInsideJob(
                token: args?.token,
                instanceId: args?.instanceId,
                allowedScopes: args?.allowedScopes,
                port: args?.port ?? 0
            )
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
            port: port
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
        case resuming(task: Task<Void, Never>)
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

    /// Mutable holder for a `Task` handle that the Task's own body needs to
    /// reference (for self-removal from `pendingLifecycleTasks`). The
    /// create-then-assign dance is unavoidable: the closure captures the
    /// holder, but the Task that owns the closure must exist before its
    /// handle can be stored. Inherits @MainActor isolation from the
    /// enclosing type so reads/writes serialize naturally.
    final class TaskHolder {
        var task: Task<Void, Never>?
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
    private var pendingTransportStopTask: Task<Void, Never>?
    /// Tracks Tasks that wrap `await stop()` / `await suspend()` for callers
    /// that must stay synchronous (notably the @objc UIApplication lifecycle
    /// observers). Cancelled and drained inside `start()` / `resume()` so a
    /// fresh start cannot interleave with a still-running shutdown.
    private var pendingLifecycleTasks: Set<Task<Void, Never>> = []
    /// The Task spawned from `appWillEnterForeground` to bridge `@objc` ->
    /// `async resume()`. Kept out of `pendingLifecycleTasks` so `resume()`'s
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
        get { getaway.recordingPhase }
        set { getaway.recordingPhase = newValue }
    }

    var stakeout: TheStakeout? { getaway.stakeout }

    /// Test hook: `pendingLifecycleTasks` is private state but tests assert
    /// it drains after completed Tasks self-remove. Exposed as a Bool so
    /// the underlying Set stays encapsulated.
    var pendingLifecycleTasksIsEmpty: Bool { pendingLifecycleTasks.isEmpty }

    private static let defaultPollingTimeout: TimeInterval = 2.0

    // MARK: - Initialization

    public init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0
    ) {
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.preferredPort = port
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

        if let scopes = allowedScopes {
            self.allowedScopes = scopes
        } else if let envValue = EnvironmentKey.insideJobScope.value,
                  let parsed = ConnectionScope.parse(envValue) {
            self.allowedScopes = parsed
        } else {
            self.allowedScopes = ConnectionScope.default
        }
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
        insideJobLogger.info("Server listening on port \(actualPort)")
        let token = await muscle.sessionToken
        insideJobLogger.info("Connect with session token: \(token, privacy: .public)")
        insideJobLogger.info("Instance ID: \(self.effectiveInstanceId)")
        advertiseService(port: actualPort)

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
        if case .resuming(let task) = serverPhase {
            task.cancel()
        }

        pendingForegroundResumeTask?.cancel()
        pendingForegroundResumeTask = nil

        if case .running(let activeTransport) = serverPhase {
            pendingTransportStopTask = activeTransport.stop()
        }

        serverPhase = .stopped
        stopPolling()

        tripwire.stopPulse()
        tripwire.onTransition = nil
        brains.stopKeyboardObservation()

        await muscle.tearDown()
        getaway.tearDown()

        stopAccessibilityObservation()
        stopLifecycleObservation()
        restoreIdleTimerProtection(clearBaseline: true)

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
            let getaway = self.getaway
            Task { await getaway.broadcastIfChanged() }
        }
    }

    func makePollingTask(interval: TimeInterval) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isPollingEnabled && !Task.isCancelled {
                let settled = await self.tripwire.waitForAllClear(timeout: interval)
                guard !Task.isCancelled, self.isPollingEnabled else { break }
                if settled {
                    await self.getaway.broadcastIfChanged()
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
        spawnLifecycleTask { [weak self] in
            await self?.suspend()
        }
    }

    @objc private func appWillEnterForeground() {
        // resume() drains pendingLifecycleTasks itself before checking phase,
        // so the foreground bridge Task is NOT enrolled in that tracker —
        // enrolling it would force resume()'s drain to await its own handle
        // and deadlock. Tracked entries are reserved for shutdown wrappers
        // (suspend/stop) that start()/resume() observe before re-arming. We
        // store the handle in a dedicated field so tests can observe it.
        pendingForegroundResumeTask?.cancel()
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
    /// retained in `pendingLifecycleTasks` so callers that resume the server
    /// (`start()` / `resume()`) can await prior shutdowns before they begin.
    ///
    /// Each Task removes itself from the set on completion so handles do not
    /// accumulate across many lifecycle transitions. The self-removal runs
    /// after `body()` returns, on the same `@MainActor` isolation as the set,
    /// so `awaitPendingLifecycleTasks()` callers either see the live handle
    /// (and await it) or see it already gone (because it finished).
    func spawnLifecycleTask(_ body: @escaping @MainActor () async -> Void) {
        // The handle removes itself from the set after `body()` returns so
        // the set does not grow without bound across many lifecycle cycles.
        // We rely on the same `@MainActor` isolation for the outer
        // assignment to `holder.task` and the closure's read of it — both
        // run on the main actor, so the box is single-threaded by
        // construction even though it bridges the create/run-then-self-
        // remove sequence.
        let holder = TaskHolder()
        let created = Task { @MainActor [weak self] in
            await body()
            guard let self, let handle = holder.task else { return }
            self.pendingLifecycleTasks.remove(handle)
        }
        holder.task = created
        pendingLifecycleTasks.insert(created)
    }

    /// Wait for any in-flight lifecycle tasks (suspend/stop wrappers spawned
    /// from @objc handlers) to finish before mutating server phase. Loops so
    /// observer-spawned Tasks that arrive during the drain are also awaited.
    private func awaitPendingLifecycleTasks() async {
        while !pendingLifecycleTasks.isEmpty {
            let tasks = pendingLifecycleTasks
            pendingLifecycleTasks.removeAll()
            for task in tasks {
                await task.value
            }
        }
    }

    // MARK: - Suspend / Resume

    func suspend() async {
        switch serverPhase {
        case .running(let activeTransport):
            pendingTransportStopTask = activeTransport.stop()
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

        await muscle.tearDown()
        getaway.tearDown()

        stopAccessibilityObservation()

        brains.clearCache()
        restoreIdleTimerProtection(clearBaseline: false)

        serverPhase = .suspended

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

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var startedTransport: ServerTransport?
            do {
                try Task.checkCancellation()

                if let pendingTransportStopTask {
                    await pendingTransportStopTask.value
                    self.pendingTransportStopTask = nil
                }

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
                if let startedTransport {
                    self.pendingTransportStopTask = startedTransport.stop()
                }
                insideJobLogger.info("Server resume cancelled")
            } catch {
                if let startedTransport {
                    self.pendingTransportStopTask = startedTransport.stop()
                }
                insideJobLogger.error("Failed to resume server: \(error)")
                if case .resuming = self.serverPhase {
                    self.serverPhase = .suspended
                }
            }
        }
        serverPhase = .resuming(task: task)
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
