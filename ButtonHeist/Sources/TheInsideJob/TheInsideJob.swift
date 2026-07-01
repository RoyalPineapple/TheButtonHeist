#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

let insideJobLogger = ButtonHeistLog.logger(.insideJob(.server))

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
        let runtimeConfiguration: InsideJobRuntimeConfiguration
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
            let runtimeConfiguration = args?.runtimeConfiguration
                ?? InsideJobRuntimeConfiguration.resolve(startupConfiguration: StartupConfiguration.resolve())
            let instance = TheInsideJob(
                runtimeConfiguration: runtimeConfiguration
            )
            sharedState = .live(instance)
            return instance
        }
    }

    public static func configure(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        fingerprintsEnabled: Bool? = nil
    ) {
        switch sharedState {
        case .pending:
            let startupConfiguration = StartupConfiguration.resolve()
            let args = ConfigureArgs(
                runtimeConfiguration: InsideJobRuntimeConfiguration.resolve(
                    startupConfiguration: startupConfiguration,
                    token: token,
                    instanceId: instanceId,
                    allowedScopes: allowedScopes,
                    port: port,
                    fingerprintsEnabled: fingerprintsEnabled
                )
            )
            sharedState = .pending(args)
        case .live:
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
        }
    }

    static func configure(startupConfiguration: StartupConfiguration) {
        switch sharedState {
        case .pending:
            let args = ConfigureArgs(
                runtimeConfiguration: InsideJobRuntimeConfiguration.resolve(startupConfiguration: startupConfiguration)
            )
            sharedState = .pending(args)
        case .live:
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
        }
    }

    // MARK: - Properties

    var serverPhase: ServerPhase = .stopped

    let muscle: TheMuscle
    let tripwire = TheTripwire()
    let brains: TheBrains
    let getaway: TheGetaway

    let runtimeConfiguration: InsideJobRuntimeConfiguration
    let transportFactory: @MainActor (String, Set<ConnectionScope>) -> ServerTransport
    let lifecycleBoundaryTasks = LifecycleBoundaryTasks()

    // MARK: - Computed State

    var isRunning: Bool {
        switch serverPhase {
        case .running, .suspending, .suspended, .resuming, .stopping: return true
        case .stopped:
            return false
        }
    }

    var transport: ServerTransport? {
        switch serverPhase {
        case .running(let resources):
            return resources.transport
        case .suspending(let suspension):
            return suspension.resources.transport
        case .stopping, .stopped, .suspended, .resuming:
            return nil
        }
    }

    var lifecycleObservationIsInstalled: Bool {
        switch serverPhase {
        case .running, .suspending, .suspended, .resuming:
            return true
        case .stopped, .stopping:
            return false
        }
    }

    var retainedIdleTimerBaseline: Bool? {
        switch serverPhase {
        case .running(let resources):
            return resources.idleTimerBaseline
        case .suspending(let suspension):
            return suspension.resources.idleTimerBaseline
        case .suspended(let suspended):
            return suspended.idleTimerBaseline
        case .resuming(let attempt):
            return attempt.suspendedRuntime.idleTimerBaseline
        case .stopped, .stopping:
            return nil
        }
    }

    // MARK: - Initialization

    public convenience init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        fingerprintsEnabled: Bool? = nil
    ) {
        self.init(
            token: token,
            instanceId: instanceId,
            allowedScopes: allowedScopes,
            port: port,
            fingerprintsEnabled: fingerprintsEnabled,
            transportFactory: { ServerTransport(token: $0, allowedScopes: $1) }
        )
    }

    convenience init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        fingerprintsEnabled: Bool? = nil,
        transportFactory: @escaping @MainActor (String, Set<ConnectionScope>) -> ServerTransport = {
            ServerTransport(token: $0, allowedScopes: $1)
        }
    ) {
        self.init(
            runtimeConfiguration: InsideJobRuntimeConfiguration.resolve(
                startupConfiguration: StartupConfiguration.resolve(),
                token: token,
                instanceId: instanceId,
                allowedScopes: allowedScopes,
                port: port,
                fingerprintsEnabled: fingerprintsEnabled
            ),
            transportFactory: transportFactory
        )
    }

    convenience init(startupConfiguration: StartupConfiguration) {
        self.init(
            runtimeConfiguration: InsideJobRuntimeConfiguration.resolve(startupConfiguration: startupConfiguration)
        )
    }

    init(
        runtimeConfiguration: InsideJobRuntimeConfiguration,
        transportFactory: @escaping @MainActor (String, Set<ConnectionScope>) -> ServerTransport = {
            ServerTransport(token: $0, allowedScopes: $1)
        }
    ) {
        self.runtimeConfiguration = runtimeConfiguration
        self.transportFactory = transportFactory
        self.muscle = TheMuscle(
            explicitToken: runtimeConfiguration.token,
            sessionReleaseTimeout: runtimeConfiguration.sessionReleaseTimeout.value
        )
        self.brains = TheBrains(
            tripwire: self.tripwire,
            fingerprintsEnabled: runtimeConfiguration.fingerprintsEnabled
        )
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

        insideJobLogger.info("Starting TheInsideJob with ServerTransport...")

        let resources = try await startRuntimeResourcesForStartup()
        activateRuntime(resources)

        insideJobLogger.info("Server started successfully")
    }

    public func stop() async {
        await stopRuntime()

        await muscle.tearDown()
        await getaway.tearDown()

        insideJobLogger.info("Server stopped")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
