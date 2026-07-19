#if canImport(UIKit)
#if DEBUG
import UIKit

@MainActor
extension TheInsideJob {
    // MARK: - App Lifecycle

    func installLifecycleObservationIfNeeded() {
        guard !lifecycleObservationIsInstalled else { return }
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
        setLifecycleObservationInstalled(true)
    }

    func stopLifecycleObservationIfNeeded() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        setLifecycleObservationInstalled(false)
    }

    @objc private func appWillResignActive() {
        beginLifecycleSuspension()
    }

    @objc private func appDidEnterBackground() {
        beginLifecycleSuspension()
    }

    private func beginLifecycleSuspension() {
        let change = applyLifecycleEvent(.lifecycleSuspensionNotification)
        performLifecycleSchedulingEffects(change.effects)
    }

    @objc private func appWillEnterForeground() {
        // resume() drains lifecycleBoundaryTasks itself before checking phase,
        // so the foreground bridge Task is NOT enrolled in that tracker.
        scheduleForegroundResume(replacingExisting: true)
    }

    @objc private func appDidBecomeActive() {
        scheduleForegroundResume(replacingExisting: false)
    }

    private func scheduleForegroundResume(replacingExisting: Bool) {
        let change = applyLifecycleEvent(.foregroundNotification(replacingExisting: replacingExisting))
        performLifecycleSchedulingEffects(change.effects)
    }

    @objc private func appWillTerminate() {
        insideJobLogger.info("App will terminate, stopping server")
        let change = applyLifecycleEvent(.terminationNotification)
        performLifecycleSchedulingEffects(change.effects)
    }

    /// Spawn a Task that wraps an async lifecycle transition. The handle is
    /// retained in `lifecycleBoundaryTasks` so callers that resume the server
    /// (`start()` / `resume()`) can await prior shutdowns before they begin.
    func spawnLifecycleTask(_ body: @escaping @MainActor @Sendable () async -> Void) {
        lifecycleBoundaryTasks.spawn(body)
    }

    /// Wait for any in-flight lifecycle tasks (suspend/stop wrappers spawned
    /// from @objc handlers) to finish before mutating server phase. Loops so
    /// observer-spawned Tasks that arrive during the drain are also awaited.
    func awaitPendingLifecycleTasks() async {
        await lifecycleBoundaryTasks.drain()
    }

    // MARK: - Suspend / Resume

    func suspend() async {
        let suspension: InsideJobSuspension?
        if case .running(let resources) = serverPhase {
            brains.vault.resetInterfaceForLifecycle()
            suspension = InsideJobSuspension(id: UUID(), resources: resources)
        } else {
            suspension = nil
        }

        let change = applyLifecycleEvent(.suspendRequested(suspension))
        await performLifecycleEffects(change.effects)

        guard let suspension else { return }
        let finishChange = applyLifecycleEvent(.suspendFinished(suspension.id))
        await performLifecycleEffects(finishChange.effects)

        insideJobLogger.info("Server suspended")
    }

    func resume() async {
        await awaitPendingLifecycleTasks()
        await resumeAfterLifecycleBoundary()
    }

    func resumeAfterLifecycleBoundary() async {
        guard case .suspended(let suspendedRuntime) = serverPhase else { return }

        insideJobLogger.info("Resuming server...")

        let resumeID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var startedTransport: ServerTransport?
            do {
                try Task.checkCancellation()

                let transport = self.makeRuntimeTransport()
                startedTransport = transport

                let request = InsideJobTransportStartRequest(
                    id: resumeID,
                    phase: .resume,
                    transport: transport,
                    idleTimerBaseline: suspendedRuntime.idleTimerBaseline
                )
                let startChange = self.applyLifecycleEvent(.resumeTransportRequested(request))
                guard case .changed = startChange else {
                    await self.cleanupFailedTransportStartup(startedTransport)
                    return
                }

                let resources = try await self.startRuntimeResources(for: request)
                startedTransport = resources.transport

                try Task.checkCancellation()

                let finishChange = self.applyLifecycleEvent(.resumeSucceeded(resumeID, resources))
                guard case .running = finishChange.state else {
                    await self.cleanupFailedTransportStartup(startedTransport)
                    return
                }

                startedTransport = nil
                await self.performLifecycleEffects(finishChange.effects)

                insideJobLogger.info("Server resumed on port \(resources.actualPort)")

                insideJobLogger.info("Server resume complete")
            } catch is CancellationError {
                await self.cleanupFailedTransportStartup(startedTransport)
                startedTransport = nil
                let failureChange = self.applyLifecycleEvent(.resumeFailed(resumeID))
                await self.performLifecycleEffects(failureChange.effects)
                insideJobLogger.info("Server resume cancelled")
            } catch {
                insideJobLogger.error("Failed to resume server: \(error)")
                await self.cleanupFailedTransportStartup(startedTransport)
                startedTransport = nil
                let failureChange = self.applyLifecycleEvent(.resumeFailed(resumeID))
                await self.performLifecycleEffects(failureChange.effects)
            }
        }
        let change = applyLifecycleEvent(
            .resumeRequested(
                InsideJobResumeAttempt(
                    id: resumeID,
                    suspendedRuntime: suspendedRuntime,
                    task: task
                )
            )
        )
        guard case .resuming = change.state else {
            task.cancel()
            return
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
