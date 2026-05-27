#if canImport(UIKit)
#if DEBUG
import UIKit

@MainActor
extension TheInsideJob {
    // MARK: - Pulse Handling

    func handlePulseTransition(_ transition: TheTripwire.PulseTransition) {
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

    var canRunSettledBackgroundParse: Bool {
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

    // MARK: - Accessibility Observation

    func startAccessibilityObservation() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessibilityDidChange),
            name: UIAccessibility.elementFocusedNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessibilityDidChange),
            name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil
        )
    }

    func stopAccessibilityObservation() {
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

    func startLifecycleObservation() {
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

    func stopLifecycleObservation() {
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
        // so the foreground bridge Task is NOT enrolled in that tracker.
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
        guard beginSuspension() else { return }
        await finishSuspension()
    }

    @discardableResult
    private func beginSuspension() -> Bool {
        switch serverPhase {
        case .running(let lease):
            pendingTransportStopTask = lease.transport.stop()
        case .resuming(_, let task):
            task.cancel()
        case .stopped, .suspended:
            return false
        }

        pollingRuntime.pauseIfActive()

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

                let lease = try await self.startRuntimeLeaseForResume()
                startedTransport = lease.transport

                try Task.checkCancellation()

                guard self.isCurrentResumeAttempt(resumeID) else {
                    if let startedTransport {
                        await self.cleanupFailedTransportStartup(startedTransport)
                    }
                    return
                }

                self.activateRuntimeLease(lease, resumePolling: true)
                startedTransport = nil

                insideJobLogger.info("Server resumed on port \(lease.actualPort)")

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

    func engageIdleTimerProtection() {
        if case .unmodified = idleTimerProtection {
            idleTimerProtection = .engaged(baseline: UIApplication.shared.isIdleTimerDisabled)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func restoreIdleTimerProtection(clearBaseline: Bool) {
        guard case .engaged(let baseline) = idleTimerProtection else { return }
        UIApplication.shared.isIdleTimerDisabled = baseline
        if clearBaseline {
            idleTimerProtection = .unmodified
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
