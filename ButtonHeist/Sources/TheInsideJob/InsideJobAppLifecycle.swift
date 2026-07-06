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
    }

    func stopLifecycleObservationIfNeeded() {
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
        spawnLifecycleTask { [weak self] in
            await self?.suspend()
        }
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
        if case .resuming(let attempt) = serverPhase {
            guard replacingExisting else { return }
            attempt.task.cancel()
            spawnLifecycleTask { [weak self] in
                await attempt.task.value
                await self?.resumeAfterLifecycleBoundary()
            }
            return
        }

        guard case .suspended = serverPhase else {
            return
        }

        spawnLifecycleTask { [weak self] in
            await self?.resumeAfterLifecycleBoundary()
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
    func spawnLifecycleTask(_ body: @escaping @MainActor () async -> Void) {
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
        let resources: InsideJobRuntimeResources
        switch serverPhase {
        case .running(let runningResources):
            resources = runningResources
        case .resuming(let attempt):
            attempt.task.cancel()
            await attempt.task.value
            guard case .suspended = serverPhase else { return }
            return
        case .starting, .stopped, .suspended, .suspending, .stopping:
            return
        }

        brains.clearCache()
        let suspension = InsideJobSuspension(id: UUID(), resources: resources)
        serverPhase = .suspending(suspension)
        releaseRuntimeOwnedResources(policy: .suspend, idleTimerBaseline: resources.idleTimerBaseline)

        await resources.transport.stop()
        await muscle.tearDown()
        await getaway.tearDown()

        guard case .suspending(let currentSuspension) = serverPhase,
              currentSuspension.id == suspension.id
        else { return }
        serverPhase = .suspended(InsideJobSuspendedRuntime(idleTimerBaseline: resources.idleTimerBaseline))

        insideJobLogger.info("Server suspended")
    }

    func resume() async {
        await awaitPendingLifecycleTasks()
        await resumeAfterLifecycleBoundary()
    }

    private func resumeAfterLifecycleBoundary() async {
        guard case .suspended(let suspendedRuntime) = serverPhase else { return }

        insideJobLogger.info("Resuming server...")

        let resumeID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var startedTransport: ServerTransport?
            do {
                try Task.checkCancellation()

                let resources = try await self.startRuntimeResourcesForResume(
                    idleTimerBaseline: suspendedRuntime.idleTimerBaseline
                )
                startedTransport = resources.transport

                try Task.checkCancellation()

                guard self.isCurrentResumeAttempt(resumeID) else {
                    if let startedTransport {
                        await self.cleanupFailedTransportStartup(startedTransport)
                    }
                    return
                }

                self.activateRuntime(resources)
                startedTransport = nil

                insideJobLogger.info("Server resumed on port \(resources.actualPort)")

                insideJobLogger.info("Server resume complete")
            } catch is CancellationError {
                await self.cleanupFailedTransportStartup(startedTransport)
                startedTransport = nil
                self.finishFailedResumeAttempt(resumeID)
                insideJobLogger.info("Server resume cancelled")
            } catch {
                insideJobLogger.error("Failed to resume server: \(error)")
                await self.cleanupFailedTransportStartup(startedTransport)
                startedTransport = nil
                self.finishFailedResumeAttempt(resumeID)
            }
        }
        serverPhase = .resuming(
            InsideJobResumeAttempt(
                id: resumeID,
                suspendedRuntime: suspendedRuntime,
                task: task
            )
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
