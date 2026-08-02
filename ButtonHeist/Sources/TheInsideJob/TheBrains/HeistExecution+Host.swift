#if canImport(UIKit)
#if DEBUG
import Foundation
import os
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    @MainActor
    internal final class Host {
        internal struct RuntimeBoundary {
            let now: @MainActor () -> RuntimeElapsed.Instant
            let wait: @MainActor (Duration) async -> Bool
            let dispatch: @MainActor (ResolvedHeistActionCommand, SemanticObservationDeadline) async -> TheSafecracker.ActionDispatchResult
            let explore: @MainActor (ResolvedAccessibilityTarget?, SemanticObservationDeadline) async -> Navigation.ViewportExit.Outcome
            let captureFailure: @MainActor (HeistExecutionPath, ScreenCaptureMode) async -> HeistFailureCapture

            static func live(brains: TheBrains) -> Self {
                .init(
                    now: { RuntimeElapsed.now },
                    wait: { await Task.cancellableSleep(for: $0) },
                    dispatch: { await brains.dispatchRuntimeAction($0, deadline: $1) },
                    explore: { target, deadline in
                        await brains.navigation.exploreForWait(target: target, deadline: deadline, stopWhen: { false })
                    },
                    captureFailure: { path, mode in
                        switch await brains.captureScreenPayload(mode: mode, observationBoundary: .observationCycle) {
                        case .success(let payload): .captured(payload)
                        case .failure(let failure): .unavailable(kind: failure.actionFailureKind, message: failure.message)
                        }
                    }
                )
            }
        }

        private struct Lifetime {
            let subscription: SemanticObservationSubscription
            let demand: SemanticObservationDemand
            let notifications: AccessibilityNotificationScopeLease
        }

        private struct ObservationResource {
            let boundary: TheVault.State.HistoryBoundary
            let subscription: SemanticObservationSubscription
            let notifications: AccessibilityNotificationScopeLease
            let deadline: SemanticObservationDeadline
            var lastTreeChangeAt: RuntimeElapsed.Instant?
        }

        private struct Runtime {
            var execution: HeistExecution
            var observations: [RequestID: ObservationResource]
            var historyIndex: Int
        }

        private enum WaitResult {
            case event(Observation.Event)
            case deadline
            case cancelled
        }

        private let brains: TheBrains
        private let runtimeBoundary: RuntimeBoundary

        internal init(brains: TheBrains, runtimeBoundary: RuntimeBoundary? = nil) {
            self.brains = brains
            self.runtimeBoundary = runtimeBoundary ?? .live(brains: brains)
        }

        internal func execute(
            _ plan: HeistPlan,
            argument: HeistArgument = .none,
            timeout: HeistTimeout,
            actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default
        ) async throws -> Completion {
            try await execute(
                try HeistExecution(
                    plan: plan,
                    argument: argument,
                    failureCaptureMode: brains.failureEvidencePolicy.captureMode,
                    actionExpectationTimeoutPolicy: actionExpectationTimeoutPolicy
                ),
                timeout: timeout
            )
        }

        internal func execute(_ action: HeistActionCommand, timeout: HeistTimeout) async throws -> Completion {
            try await execute(
                HeistExecution(action: action, failureCaptureMode: brains.failureEvidencePolicy.captureMode),
                timeout: timeout
            )
        }

        private func execute(_ execution: HeistExecution, timeout: HeistTimeout) async throws -> Completion {
            let stream = brains.vault.semanticObservationStream
            let inbox = ObservationInbox()
            guard let admission = stream.admitExecutionBoundary(receive: { inbox.yield($0) }) else {
                try Task.checkCancellation()
                throw Failure.runtimeUnavailable
            }
            let lifetime = Lifetime(
                subscription: admission.subscription,
                demand: admission.demand,
                notifications: brains.vault.accessibilityNotifications.beginHeistScope()
            )
            var runtime = Runtime(execution: execution, observations: [:], historyIndex: admission.retainedHistoryIndex)
            defer { release(lifetime, runtime: &runtime) }

            var baseline: Observation.Stream.ExecutionAdmission? = admission
            var decision = runtime.execution.start(at: runtimeBoundary.now(), timeout: timeout)
            while true {
                switch decision {
                case .complete(let completion):
                    if completion.outcome == .cancelled || Task.isCancelled {
                        throw CancellationError()
                    }
                    let cursor = brains.vault.accessibilityNotifications.cursor()
                    guard await admitTerminalNotifications(lifetime.notifications, after: cursor) else {
                        throw Failure.accessibilityTreeUnavailable
                    }
                    return completion

                case .perform(let effect):
                    guard !Task.isCancelled || isCancellationCleanup(effect) else {
                        decision = runtime.execution.reduce(.cancellationRequested(at: runtimeBoundary.now()))
                        continue
                    }
                    let event = await execute(effect, runtime: &runtime, baseline: &baseline)
                    decision = Task.isCancelled && !isCancellationCleanup(effect)
                        ? runtime.execution.reduce(.cancellationRequested(at: runtimeBoundary.now()))
                        : runtime.execution.reduce(event)

                case .wait(let request):
                    let event: Event
                    if Task.isCancelled {
                        event = .cancellationRequested(at: runtimeBoundary.now())
                    } else if let queued = await inbox.pop() {
                        event = .observation(request.id, queued, at: runtimeBoundary.now())
                    } else {
                        switch await wait(for: request, inbox: inbox) {
                        case .event(let observation): event = .observation(request.id, observation, at: runtimeBoundary.now())
                        case .deadline: event = .deadlineElapsed(request.id, at: runtimeBoundary.now())
                        case .cancelled:
                            event = .cancellationRequested(at: runtimeBoundary.now())
                        }
                    }
                    record(event, runtime: &runtime)
                    decision = runtime.execution.reduce(event)
                }
            }
        }

        private func execute(
            _ effect: Effect,
            runtime: inout Runtime,
            baseline: inout Observation.Stream.ExecutionAdmission?
        ) async -> Event {
            switch effect {
            case .currentSnapshot(let id, let scope, let deadline):
                let current: TheVault.State.Current? = switch scope {
                case .visible:
                    await brains.vault.semanticObservationStream
                        .admittedVisibleObservation(boundary: .externalDeadline(deadline))
                case .discovery: await brains.navigation.fullGraph(deadline: deadline)?.current
                }
                return .currentSnapshot(id, current?.snapshot, at: runtimeBoundary.now())

            case .beginObservation(let id, let request, let deadline):
                return await beginObservation(id: id, request: request, deadline: deadline, runtime: &runtime, baseline: &baseline)

            case .dispatch(let id, let command, let deadline):
                return .dispatchCompleted(id, await runtimeBoundary.dispatch(command, deadline), at: runtimeBoundary.now())

            case .explore(let id, let predicate, let deadline):
                let outcome = await runtimeBoundary.explore(predicate.resolved.watchTarget, deadline)
                return .viewportExited(id, outcome, at: runtimeBoundary.now())

            case .sampleObservationClose(let requestID, let observationID, let exitPosition, let capture, let source):
                return await sampleObservationClose(
                    requestID: requestID,
                    observationID: observationID,
                    exitPosition: exitPosition,
                    capture: capture,
                    source: source,
                    runtime: &runtime
                )

            case .commitObservationClose(let id, let observationID):
                return await commitObservation(id: id, observationID: observationID, runtime: &runtime)

            case .captureFailureScreenshot(let id, let path, let mode):
                return .failureScreenshotCaptured(id, await runtimeBoundary.captureFailure(path, mode), at: runtimeBoundary.now())

            case .cancelObservation(let id, let observationID):
                if let observationID,
                   let resource = runtime.observations.removeValue(forKey: observationID) {
                    release(resource, runtime: &runtime)
                }
                return .cancellationCompleted(id, at: runtimeBoundary.now())
            }
        }

        private func isCancellationCleanup(_ effect: Effect) -> Bool {
            if case .cancelObservation = effect { return true }
            return false
        }

        private func beginObservation(
            id: RequestID,
            request: ObservationRequest,
            deadline: SemanticObservationDeadline,
            runtime: inout Runtime,
            baseline: inout Observation.Stream.ExecutionAdmission?
        ) async -> Event {
            let stream = brains.vault.semanticObservationStream
            let subscription = stream.subscribe(scope: request.scope)
            let boundary: TheVault.State.HistoryBoundary
            let captured: TheVault.State.Current?
            switch request.scope {
            case .visible:
                if let initial = baseline {
                    baseline = nil
                    let admitted = await stream.admitExecutionBaseline(initial, deadline: deadline)
                    captured = admitted.current
                    boundary = admitted.boundary
                } else {
                    captured = await stream.admittedVisibleObservation(boundary: .externalDeadline(deadline))
                    boundary = .init(baseline: captured?.snapshot, historyIndex: stream.executionHistoryIndex(reusing: captured))
                }
            case .discovery:
                captured = nil
                _ = await brains.navigation.fullGraph(deadline: deadline)
                boundary = stream.observationBoundary(scope: request.scope)
            }
            let resource = ObservationResource(
                boundary: boundary,
                subscription: subscription,
                notifications: brains.vault.accessibilityNotifications.beginActionWindow(),
                deadline: deadline,
                lastTreeChangeAt: nil
            )
            runtime.observations[id] = resource
            if runtime.historyIndex < boundary.historyIndex {
                stream.advanceHistoryProtection(from: runtime.historyIndex, to: boundary.historyIndex)
                runtime.historyIndex = boundary.historyIndex
            }
            return .observationBegan(id, baseline: captured?.snapshot, at: runtimeBoundary.now())
        }

        private func sampleObservationClose(
            requestID: RequestID,
            observationID: RequestID,
            exitPosition: Navigation.ViewportExitPosition,
            capture: ObservationCloseCapture,
            source: ObservationCloseSource,
            runtime: inout Runtime
        ) async -> Event {
            guard let resource = runtime.observations[observationID] else {
                return .observationCloseSampled(
                    requestID, source: source, observationID: observationID,
                    evidence: .init(baseline: nil, events: [], current: nil, coverage: .incomplete(.captureUnavailable)),
                    close: .init(captureAvailable: false, viewportExit: nil, lastTreeChangeAt: nil), at: runtimeBoundary.now()
                )
            }
            let viewportExit: Navigation.ViewportExit.Outcome? = if case .origin = exitPosition {
                await brains.navigation.fullGraph(deadline: resource.deadline)?.viewportExit
            } else { nil }
            var captureAvailable = false
            _ = await resource.notifications.admitCausallyCovered { coverage -> Void? in
                captureAvailable = switch capture {
                case .coverage:
                    await self.brains.vault.semanticObservationStream
                        .visibleObservation(covering: coverage) != nil
                case .refresh:
                    if case .committed = await self.brains.vault.semanticObservationStream
                        .refreshedVisibleObservation(boundary: .externalDeadline(resource.deadline)) {
                        true
                    } else {
                        false
                    }
                case .nextCycle:
                    await self.brains.vault.semanticObservationStream
                        .visibleObservationAfterNextCycle(covering: coverage) != nil
                }
                return nil
            }
            let evidence = evidence(after: resource.boundary, captureAvailable: captureAvailable)
            let endedAt = runtimeBoundary.now()
            return .observationCloseSampled(
                requestID, source: source, observationID: observationID, evidence: evidence,
                close: .init(
                    captureAvailable: captureAvailable,
                    viewportExit: viewportExit,
                    lastTreeChangeAt: resource.lastTreeChangeAt
                ), at: endedAt
            )
        }

        private func record(_ event: Event, runtime: inout Runtime) {
            guard case .observation(_, let observation, let at) = event,
                  observation.changesInterface else { return }
            let ids = Array(runtime.observations.keys)
            for id in ids {
                runtime.observations[id]?.lastTreeChangeAt = at
            }
        }

        private func commitObservation(
            id: RequestID,
            observationID: RequestID,
            runtime: inout Runtime
        ) async -> Event {
            guard let resource = runtime.observations.removeValue(forKey: observationID) else {
                return .observationCloseCommitted(id, at: runtimeBoundary.now())
            }
            _ = await resource.notifications.admitCausallyCovered { _ in true }
            release(resource, runtime: &runtime)
            return .observationCloseCommitted(id, at: runtimeBoundary.now())
        }

        private func wait(for request: WaitRequest, inbox: ObservationInbox) async -> WaitResult {
            await withTaskGroup(of: WaitResult.self) { group in
                group.addTask { await inbox.next().map(WaitResult.event) ?? .cancelled }
                group.addTask { [runtimeBoundary] in
                    await runtimeBoundary.wait(request.deadline.remainingDuration(at: runtimeBoundary.now())) ? .deadline : .cancelled
                }
                let first = await group.next() ?? .cancelled
                if case .event = first {
                    group.cancelAll()
                    return first
                }
                if let queued = await inbox.pop() {
                    group.cancelAll()
                    return .event(queued)
                }
                group.cancelAll()
                var queued: Observation.Event?
                while let result = await group.next() {
                    if case .event(let event) = result {
                        queued = event
                    }
                }
                return queued.map(WaitResult.event) ?? first
            }
        }

        private func evidence(after boundary: TheVault.State.HistoryBoundary, captureAvailable: Bool) -> Observation.Evidence {
            let evidence = brains.vault.state.evidence(after: boundary)
            guard !captureAvailable, evidence.coverage == .complete else { return evidence }
            return .init(baseline: evidence.baseline, events: evidence.events, current: evidence.current, coverage: .incomplete(.captureUnavailable))
        }

        private func release(_ resource: ObservationResource, runtime: inout Runtime) {
            resource.subscription.cancel()
            resource.notifications.cancel()
            let nextHistoryIndex = brains.vault.semanticObservationStream
                .executionHistoryIndex(reusing: brains.vault.state.current)
            brains.vault.semanticObservationStream.advanceHistoryProtection(
                from: runtime.historyIndex,
                to: nextHistoryIndex
            )
            runtime.historyIndex = nextHistoryIndex
        }

        private func release(_ lifetime: Lifetime, runtime: inout Runtime) {
            for resource in runtime.observations.values {
                release(resource, runtime: &runtime)
            }
            lifetime.subscription.cancel()
            lifetime.demand.cancel()
            lifetime.notifications.cancel()
            brains.vault.semanticObservationStream.releaseHistory(from: runtime.historyIndex)
        }

        private func admitTerminalNotifications(_ lease: AccessibilityNotificationScopeLease, after cursor: AccessibilityNotificationCursor) async -> Bool {
            await lease.admitCausallyCovered { [brains] coverage in
                let terminal = AccessibilityNotificationCoverage(
                    after: cursor,
                    through: coverage.through,
                    scopedScreenChangedThrough: coverage.scopedScreenChangedThrough > cursor.sequence ? coverage.scopedScreenChangedThrough : 0
                )
                guard terminal.requiresObservation else { return true }
                return await brains.vault.semanticObservationStream.visibleObservationThroughCausalCycles(covering: terminal) != nil
            } != nil
        }
    }
}

private actor ObservationInbox {
    private let stream: AsyncStream<Observation.Event>
    nonisolated private let emit: AsyncStream<Observation.Event>.Continuation
    nonisolated private let count = OSAllocatedUnfairLock(initialState: 0)

    init() {
        let stream = AsyncStream<Observation.Event>.makeStream()
        self.stream = stream.stream
        emit = stream.continuation
    }

    nonisolated func yield(_ event: Observation.Event) {
        count.withLock { $0 += 1 }
        emit.yield(event)
    }

    func pop() async -> Observation.Event? {
        guard count.withLock({ $0 > 0 }) else { return nil }
        return await next()
    }

    func next() async -> Observation.Event? {
        for await event in stream {
            count.withLock { $0 -= 1 }
            return event
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
