#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

let insideJobLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "server")

/// The job itself: resolves startup/runtime configuration, assembles the crew,
/// and coordinates transport start/stop with the app lifecycle.
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
        let runtimeConfiguration: InsideJobRuntimeConfiguration?
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
            let instance = if let configuration = args?.runtimeConfiguration {
                TheInsideJob(
                    runtimeConfiguration: configuration,
                    tlsIdentityProvider: Self.defaultTLSIdentityProvider
                )
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
            runtimeConfiguration: nil
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
            token: nil,
            instanceId: nil,
            allowedScopes: nil,
            port: 0,
            runtimeConfiguration: InsideJobRuntimeConfiguration.resolve(startupConfiguration: startupConfiguration)
        )
        switch sharedState {
        case .pending:
            sharedState = .pending(args)
        case .live:
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
        }
    }

    // MARK: - Properties

    var serverPhase: ServerPhase = .stopped
    let pollingRuntime = InsideJobPollingRuntime()

    let muscle: TheMuscle
    let tripwire = TheTripwire()
    let brains: TheBrains
    let getaway: TheGetaway

    let runtimeConfiguration: InsideJobRuntimeConfiguration
    let tlsIdentityProvider: @MainActor () throws -> TLSIdentity
    let transportFactory: @MainActor (TLSIdentity, Set<ConnectionScope>) -> ServerTransport
    var pendingTransportStopTask: Task<Void, Never>?
    let lifecycleBoundaryTasks = LifecycleBoundaryTasks()
    /// The Task spawned from `appWillEnterForeground` to bridge `@objc` ->
    /// `async resume()`. Kept out of `lifecycleBoundaryTasks` so `resume()`'s
    /// own drain cannot deadlock by awaiting its own handle. Tests observe
    /// it to wait on a foreground resume cycle synchronously.
    var pendingForegroundResumeTask: Task<Void, Never>?
    var idleTimerProtection: IdleTimerProtection = .unmodified
    var accessibilityObservationActive = false
    var lifecycleObservationActive = false

    // MARK: - Computed State

    var isRunning: Bool {
        switch serverPhase {
        case .running, .suspended, .resuming: return true
        case .stopped: return false
        }
    }

    var transport: ServerTransport? {
        if case .running(let lease) = serverPhase { return lease.transport }
        return nil
    }

    var isPollingEnabled: Bool {
        pollingRuntime.isEnabled
    }

    var pollingTimeoutSeconds: TimeInterval {
        pollingRuntime.timeoutSeconds(default: Self.defaultPollingTimeout)
    }

    var pollingPhase: PollingPhase {
        get { pollingRuntime.phase }
        set { pollingRuntime.phase = newValue }
    }

    static let defaultPollingTimeout: TimeInterval = 2.0

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
        self.init(
            runtimeConfiguration: InsideJobRuntimeConfiguration.resolve(
                token: token,
                instanceId: instanceId,
                allowedScopes: allowedScopes,
                port: port
            ),
            tlsIdentityProvider: tlsIdentityProvider,
            transportFactory: transportFactory
        )
    }

    convenience init(startupConfiguration: StartupConfiguration) {
        self.init(
            runtimeConfiguration: InsideJobRuntimeConfiguration.resolve(startupConfiguration: startupConfiguration),
            tlsIdentityProvider: Self.defaultTLSIdentityProvider
        )
    }

    init(
        runtimeConfiguration: InsideJobRuntimeConfiguration,
        tlsIdentityProvider: @escaping @MainActor () throws -> TLSIdentity,
        transportFactory: @escaping @MainActor (TLSIdentity, Set<ConnectionScope>) -> ServerTransport = {
            ServerTransport(tlsIdentity: $0, allowedScopes: $1)
        }
    ) {
        self.runtimeConfiguration = runtimeConfiguration
        self.tlsIdentityProvider = tlsIdentityProvider
        self.transportFactory = transportFactory
        self.muscle = TheMuscle(
            explicitToken: runtimeConfiguration.token,
            sessionReleaseTimeout: runtimeConfiguration.sessionReleaseTimeout.value
        )
        self.brains = TheBrains(tripwire: self.tripwire)
        self.getaway = TheGetaway(
            muscle: self.muscle,
            brains: self.brains,
            identity: TheGetaway.ServerIdentity(
                sessionId: runtimeConfiguration.sessionIdentity.sessionId,
                effectiveInstanceId: runtimeConfiguration.sessionIdentity.effectiveInstanceId,
                tlsActive: false
            )
        )
    }

    // MARK: - Public API

    public func start() async throws {
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

        let lease = try await startRuntimeLeaseForStartup()
        lease.activate(on: self)

        insideJobLogger.info("Server started successfully")
    }

    public func stop() async {
        await stopRuntime()

        await muscle.tearDown()
        await getaway.tearDown()

        insideJobLogger.info("Server stopped")
    }

    public func notifyChange() {
        guard isRunning else { return }
    }

    public func startPolling(interval timeout: TimeInterval = 2.0) {
        pollingRuntime.enableIntent(interval: timeout, runtimeActive: transport != nil, makeTask: makePollingTask(interval:))
        insideJobLogger.info("Polling enabled (settle timeout: \(self.pollingTimeoutSeconds)s)")
    }

    public func stopPolling() {
        pollingRuntime.stop()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
