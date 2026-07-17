#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import ButtonHeistSupport
import TheScore

let insideJobLogger = ButtonHeistLog.logger(.insideJob(.server))

public enum InsideJobStopOutcome: Sendable, Equatable {
    case stopped
    case teardownTimedOut
}

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
        addressFamily: ListenerAddressFamily = .dualStack,
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
                    addressFamily: addressFamily,
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

    private var lifecycle = StateDriver(
        initial: ServerPhase.stopped,
        machine: InsideJobLifecycleMachine()
    )
    private var lifecycleObserversInstalled = false

    var serverPhase: ServerPhase {
        lifecycle.state
    }

    let muscle: TheMuscle
    let tripwire = TheTripwire()
    let brains: TheBrains
    let getaway: TheGetaway

    let runtimeConfiguration: InsideJobRuntimeConfiguration
    let transportFactory: @MainActor (SessionAuthToken, Set<ConnectionScope>) -> ServerTransport
    let lifecycleBoundaryTasks = LifecycleBoundaryTasks()

    // MARK: - Computed State

    var isRunning: Bool {
        switch serverPhase {
        case .starting, .running, .suspending, .suspended, .resuming, .stopping: return true
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
        case .starting, .stopping, .stopped, .suspended, .resuming:
            return nil
        }
    }

    var lifecycleObservationIsInstalled: Bool {
        lifecycleObserversInstalled
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
        case .starting, .stopped, .stopping:
            return nil
        }
    }

    /// Port currently bound by the InsideJob TCP listener, if the runtime is
    /// running or suspending. This is primarily useful for app-hosted XCTest
    /// live-driving probes that start the server manually because auto-start is
    /// disabled under XCTest.
    public var listeningPort: UInt16? {
        switch serverPhase {
        case .running(let resources):
            return resources.actualPort
        case .suspending(let suspension):
            return suspension.resources.actualPort
        case .starting, .stopped, .suspended, .resuming, .stopping:
            return nil
        }
    }

    @discardableResult
    func applyLifecycleEvent(
        _ event: InsideJobLifecycleMachine.Event
    ) -> StateChange<ServerPhase, InsideJobLifecycleMachine.Effect, InsideJobLifecycleMachine.Rejection> {
        lifecycle.send(event)
    }

    func setLifecycleObservationInstalled(_ installed: Bool) {
        lifecycleObserversInstalled = installed
    }

    // MARK: - Initialization

    public convenience init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        addressFamily: ListenerAddressFamily = .dualStack,
        fingerprintsEnabled: Bool? = nil
    ) {
        self.init(
            token: token,
            instanceId: instanceId,
            allowedScopes: allowedScopes,
            port: port,
            addressFamily: addressFamily,
            fingerprintsEnabled: fingerprintsEnabled,
            transportFactory: { ServerTransport(token: $0, allowedScopes: $1) }
        )
    }

    convenience init(
        token: String? = nil,
        instanceId: String? = nil,
        allowedScopes: Set<ConnectionScope>? = nil,
        port: UInt16 = 0,
        addressFamily: ListenerAddressFamily = .dualStack,
        fingerprintsEnabled: Bool? = nil,
        transportFactory: @escaping @MainActor (SessionAuthToken, Set<ConnectionScope>) -> ServerTransport = {
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
                addressFamily: addressFamily,
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
        transportFactory: @escaping @MainActor (SessionAuthToken, Set<ConnectionScope>) -> ServerTransport = {
            ServerTransport(token: $0, allowedScopes: $1)
        }
    ) {
        self.runtimeConfiguration = runtimeConfiguration
        self.transportFactory = transportFactory
        self.muscle = TheMuscle(
            explicitToken: runtimeConfiguration.token.value,
            sessionReleaseTimeout: runtimeConfiguration.sessionReleaseTimeout.value
        )
        self.brains = TheBrains(
            tripwire: self.tripwire,
            fingerprintsEnabled: runtimeConfiguration.fingerprintsEnabled.value,
            failureEvidencePolicy: runtimeConfiguration.failureEvidencePolicy.value
        )
        self.getaway = TheGetaway(
            muscle: self.muscle,
            brains: self.brains,
            identity: TheGetaway.ServerIdentity(
                launchId: runtimeConfiguration.sessionIdentity.launchId,
                effectiveInstanceId: runtimeConfiguration.sessionIdentity.effectiveInstanceId.value,
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

        let attemptID = UUID()
        let attempt = makeRuntimeStartAttempt(id: attemptID)
        let startChange = applyLifecycleEvent(
            .startRequested(
                attempt,
                idleTimerBaseline: UIApplication.shared.isIdleTimerDisabled
            )
        )
        guard case .changed = startChange else {
            insideJobLogger.info("start() called while already running — ignoring")
            return
        }

        do {
            let resources = try await startRuntimeResources(from: startChange.effects)
            let finishChange = applyLifecycleEvent(.startSucceeded(attemptID, resources))
            guard case .running = finishChange.state else {
                await performLifecycleEffect(.cleanupTransport(resources.transport))
                throw CancellationError()
            }
            await performLifecycleEffects(finishChange.effects)
        } catch {
            let failureChange = applyLifecycleEvent(.startFailed(attemptID))
            switch failureChange {
            case .changed:
                await performLifecycleEffects(failureChange.effects)
            case .rejected:
                await performLifecycleEffect(.cleanupTransport(attempt.transport))
            }
            throw error
        }

        guard case .running = serverPhase else {
            throw CancellationError()
        }

        insideJobLogger.info("Server started successfully")
    }

    @discardableResult
    public func stop() async -> InsideJobStopOutcome {
        let outcome = await stopRuntime()
        switch outcome {
        case .stopped:
            insideJobLogger.info("Server stopped")
        case .teardownTimedOut:
            insideJobLogger.error("Server teardown timed out")
        }
        return outcome
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
