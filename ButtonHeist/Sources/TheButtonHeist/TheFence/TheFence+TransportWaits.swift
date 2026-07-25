import Foundation

import ThePlans
import TheScore

extension TheFence {

    // MARK: - Send Action

    func sendAndAwaitAction(_ message: ClientMessage, timeout: TimeInterval) async throws -> ActionResult {
        try await sendAndAwait(message, expecting: .action, timeout: timeout)
    }

    func sendAndAwaitPong(timeout: TimeInterval) async throws -> PongPayload {
        try await sendAndAwait(.ping, expecting: .pong, timeout: timeout)
    }

    func sendAndAwaitInterface(_ message: ClientMessage, timeout: TimeInterval) async throws -> Interface {
        try await sendAndAwait(message, expecting: .interface, timeout: timeout)
    }

    func sendAndAwaitScreen(
        _ message: ClientMessage,
        timeout: TimeInterval
    ) async throws -> ScreenPayload {
        try await sendAndAwait(message, expecting: .screen, timeout: timeout)
    }

    func sendAndAwaitAnnouncements(timeout: TimeInterval) async throws -> AnnouncementListPayload {
        try await sendAndAwait(.getAnnouncements, expecting: .announcements, timeout: timeout)
    }

    func sendAndAwaitHeistExecution(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: TimeInterval
    ) async throws -> HeistResult {
        let message = ClientMessage.heistPlan(HeistPlanRun(plan: plan, argument: argument))
        return try await sendAndAwait(message, expecting: .heistExecution, timeout: timeout)
    }

    func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        pendingRequests.cancelAll(error: error)
    }

    private func sendAndAwait<Response: Sendable>(
        _ message: ClientMessage,
        expecting expectation: PendingResponseExpectation<Response>,
        timeout: TimeInterval
    ) async throws -> Response {
        guard handoff.connectionLifecycle.isConnected else { throw FenceError.notConnected }
        let requestId = try RequestID(validating: UUID().uuidString)
        var watchdog: Task<Void, Never>?
        let result: Result<Response, Error>
        do {
            result = .success(try await pendingRequests.waitForResponse(
                expectation,
                requestId: requestId,
                timeout: timeout
            ) {
                self.sendClientMessage(message, requestId: requestId)
                watchdog = self.mainThreadWatchdog(for: message, requestId: requestId)
            })
        } catch {
            result = .failure(error)
        }
        watchdog?.cancel()
        await watchdog?.value
        return try result.get()
    }

    private func mainThreadWatchdog(
        for message: ClientMessage,
        requestId: RequestID
    ) -> Task<Void, Never>? {
        guard message.requiresMainThread,
              case .enabled(let settings) = config.mainThreadWatchdog
        else { return nil }
        return Task { [weak self] in
            guard let self else { return }
            await self.watchMainThread(for: requestId, settings: settings)
        }
    }

    private func watchMainThread(
        for requestId: RequestID,
        settings: MainThreadWatchdogSettings
    ) async {
        var delay = settings.initialDelayDuration
        while await sleepForMainThreadWatchdog(delay) {
            guard !Task.isCancelled else { return }
            do {
                let response: MainThreadProbeResponse = try await sendAndAwait(
                    .mainThreadProbe(MainThreadProbeRequest(
                        responsivenessTimeoutMilliseconds: settings.responsivenessTimeoutMilliseconds,
                        workTimeoutMilliseconds: settings.workTimeoutMilliseconds
                    )),
                    expecting: .mainThreadProbe,
                    timeout: settings.probeResponseTimeout
                )
                switch response.outcome {
                case .responsive:
                    delay = settings.cadenceDuration
                case .mainThreadUnresponsive:
                    pendingRequests.resolveTransientFailure(
                        FenceError.mainThreadUnresponsive,
                        requestId: requestId
                    )
                    return
                case .workTimedOut:
                    pendingRequests.resolveTransientFailure(
                        FenceError.mainThreadWorkTimedOut,
                        requestId: requestId
                    )
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                delay = settings.cadenceDuration
            }
        }
    }

    private func sendClientMessage(
        _ message: ClientMessage,
        requestId: RequestID
    ) {
        let outcome = handoff.send(
            message,
            requestId: requestId
        )
        if case .failed(let failure) = outcome {
            pendingRequests.resolveTransientFailure(FenceError(failure), requestId: requestId)
        }
    }
}

extension ClientMessage {
    var requiresMainThread: Bool {
        switch self {
        case .requestInterface,
             .getPasteboard,
             .getAnnouncements,
             .requestScreen,
             .runtimeAction,
             .heistPlan,
             .status:
            return true
        case .clientHello,
             .authenticate,
             .ping,
             .mainThreadProbe:
            return false
        }
    }
}
