#if canImport(UIKit)
#if DEBUG
import Foundation
import os
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    @MainActor
    internal final class Host {
        private struct Lifetime {
            let eventSubscription: SemanticObservationSubscription
            let observationDemand: SemanticObservationDemand
            let notificationScope: AccessibilityNotificationScopeLease
        }

        private struct InstalledLifetime {
            let inbox: ObservationInbox
            let lifetime: Lifetime
            let baseline: Observation.Stream.ExecutionAdmission
        }

        private struct ActiveObservation {
            let id: RequestID
            let boundary: TheVault.State.HistoryBoundary
            let scopeSubscription: SemanticObservationSubscription
            let notificationWindow: AccessibilityNotificationScopeLease
            let deadline: SemanticObservationDeadline
            var lastTreeChangeAt: RuntimeElapsed.Instant?
            var viewportStatus: ViewportStatus
        }

        private struct Runtime {
            var machine: Machine
            var observation: ActiveObservation?
            var deadlines: DeadlineTargets
            var historyIndex: Int
        }

        private struct ObservationCloseResult {
            let evidence: Observation.Evidence
            let timing: HeistExpectationTiming
            let viewportStatus: ViewportStatus
        }

        private enum ObservationCloseCapture {
            case coverage
            case singleCycle
        }

        private enum ViewportStatus {
            case available
            case unavailable
            case failed(Navigation.ViewportExit.Failure)

            mutating func record(_ outcome: Navigation.ViewportExit.Outcome?) {
                if case .failed = self { return }
                self = switch outcome {
                case .restored?, .retained?, .superseded?: .available
                case .failed(let failure)?: .failed(failure)
                case nil: .unavailable
                }
            }
        }

        private enum DeadlineTargets {
            case whole(SemanticObservationDeadline)
            case leaf(whole: SemanticObservationDeadline, leaf: SemanticObservationDeadline)

            var whole: SemanticObservationDeadline {
                switch self {
                case .whole(let whole), .leaf(let whole, _): whole
                }
            }

            func expiration(at now: RuntimeElapsed.Instant) -> DeadlineExpiration? {
                switch self {
                case .whole(let whole):
                    whole.hasTimeRemaining(at: now) ? nil : .whole
                case .leaf(let whole, let leaf):
                    switch (leaf.hasTimeRemaining(at: now), whole.hasTimeRemaining(at: now)) {
                    case (true, true): nil
                    case (false, true): .leaf
                    case (true, false): .whole
                    case (false, false): .leafAndWhole
                    }
                }
            }

            func remainingDuration(at now: RuntimeElapsed.Instant) -> Duration {
                switch self {
                case .whole(let whole): whole.remainingDuration(at: now)
                case .leaf(let whole, let leaf): min(
                    whole.remainingDuration(at: now),
                    leaf.remainingDuration(at: now)
                )
                }
            }
        }

        private enum DeadlineExpiration {
            case leaf
            case whole
            case leafAndWhole

            var includesWhole: Bool {
                switch self {
                case .leaf: false
                case .whole, .leafAndWhole: true
                }
            }
        }

        private enum Waiting {
            case event(Observation.Event)
            case cancelled
            case deadline
        }

        private enum PerformedEffect {
            case input(Input)
            case observationBegan(ActiveObservation)
            case viewportExited(RequestID, Navigation.ViewportExit.Outcome)
            case observationClosed(
                ActiveObservation,
                source: ObservationFinishSource,
                result: ObservationCloseResult
            )
        }

        private enum EffectRace {
            case effect(PerformedEffect, completedObservationCycle: Bool)
            case deadline(
                observationClosed: PerformedEffect?,
                completedObservationCycle: Bool
            )
            case cancelled(completedObservationCycle: Bool)
        }

        private let brains: TheBrains
        private let beforeTerminalNotificationAdmission: (@MainActor () -> Void)?
        private var hasExecuted = false

        internal init(brains: TheBrains,
                      beforeTerminalNotificationAdmission: (@MainActor () -> Void)? = nil) {
            self.brains = brains
            self.beforeTerminalNotificationAdmission = beforeTerminalNotificationAdmission
        }

        internal func execute(
            _ plan: HeistPlan,
            argument: HeistArgument = .none,
            timeout: HeistTimeout,
            actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default
        ) async throws -> Completion {
            try await execute(
                try Machine(
                    plan: plan,
                    argument: argument,
                    failureCaptureMode: brains.failureEvidencePolicy.captureMode,
                    actionExpectationTimeoutPolicy: actionExpectationTimeoutPolicy
                ),
                timeout: timeout
            )
        }

        internal func execute(
            _ action: HeistActionCommand,
            timeout: HeistTimeout
        ) async throws -> Completion {
            try await execute(
                Machine(action: action, failureCaptureMode: brains.failureEvidencePolicy.captureMode),
                timeout: timeout
            )
        }

        private func execute(_ machine: Machine, timeout: HeistTimeout) async throws -> Completion {
            precondition(!hasExecuted, "A heist host executes exactly one command")
            hasExecuted = true

            guard let installation = installLifetime() else {
                try Task.checkCancellation()
                throw HeistExecution.Failure.runtimeUnavailable
            }
            let wholeDeadline = SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeout: .seconds(timeout.seconds)
            )
            var runtime = Runtime(
                machine: machine,
                observation: nil,
                deadlines: .whole(wholeDeadline),
                historyIndex: installation.baseline.retainedHistoryIndex
            )
            defer { release(installation.lifetime, historyIndex: runtime.historyIndex) }

            try Task.checkCancellation()
            var initialBaseline: Observation.Stream.ExecutionAdmission? = installation.baseline
            var decision = runtime.machine.start()
            var effectCompletedObservationCycle = false

            do {
                while true {
                    try Task.checkCancellation()
                    switch decision {
                    case .complete(let completion):
                        let terminalNotificationCursor = brains.vault.accessibilityNotifications.cursor()
                        beforeTerminalNotificationAdmission?()
                        let notificationsAdmitted = await admitTerminalNotifications(
                            installation.lifetime.notificationScope,
                            after: terminalNotificationCursor
                        )
                        try Task.checkCancellation()
                        guard notificationsAdmitted else {
                            throw HeistExecution.Failure.accessibilityTreeUnavailable
                        }
                        return completion

                    case .perform(let request):
                        decision = try await performDecision(
                            request,
                            currentDecision: decision,
                            inbox: installation.inbox,
                            runtime: &runtime,
                            initialBaseline: &initialBaseline,
                            effectCompletedObservationCycle: &effectCompletedObservationCycle
                        )

                    case .wait:
                        if let event = await installation.inbox.pop() {
                            decision = advance(event, runtime: &runtime)
                            continue
                        }
                        if let expiration = runtime.deadlines.expiration(at: RuntimeElapsed.now) {
                            decision = await terminalDeadlineDecision(
                                expiration,
                                inbox: installation.inbox,
                                currentDecision: decision,
                                runtime: &runtime
                            )
                            continue
                        }
                        switch await waitForEvent(
                            from: installation.inbox,
                            before: runtime.deadlines.remainingDuration(at: RuntimeElapsed.now)
                        ) {
                        case .event(let event):
                            decision = advance(event, runtime: &runtime)
                        case .cancelled:
                            throw CancellationError()
                        case .deadline:
                            decision = await terminalDeadlineDecision(
                                runtime.deadlines.expiration(at: RuntimeElapsed.now) ?? .whole,
                                inbox: installation.inbox,
                                currentDecision: decision,
                                runtime: &runtime
                            )
                        }
                    }
                }
            } catch is CancellationError {
                await restoreTerminalViewport(
                    runtime: &runtime,
                    effectCompletedObservationCycle: effectCompletedObservationCycle
                )
                throw CancellationError()
            }
        }

        private func installLifetime() -> InstalledLifetime? {
            let stream = brains.vault.semanticObservationStream
            let inbox = ObservationInbox()
            guard let baseline = stream.admitExecutionBoundary(
                receive: { inbox.yield($0) }
            ) else {
                return nil
            }
            return .init(
                inbox: inbox,
                lifetime: .init(
                    eventSubscription: baseline.subscription,
                    observationDemand: baseline.demand,
                    notificationScope: brains.vault.accessibilityNotifications.beginHeistScope()
                ),
                baseline: baseline
            )
        }

        private func performDecision(
            _ request: MainActorRequest,
            currentDecision: Decision,
            inbox: ObservationInbox,
            runtime: inout Runtime,
            initialBaseline: inout Observation.Stream.ExecutionAdmission?,
            effectCompletedObservationCycle: inout Bool
        ) async throws -> Decision {
            let baseline: Observation.Stream.ExecutionAdmission?
            if case .beginObservation(_, let observationRequest) = request,
               observationRequest.scope == .visible {
                baseline = initialBaseline
                initialBaseline = nil
            } else {
                baseline = nil
            }
            let race = await raceEffect(
                request,
                runtime: runtime,
                baseline: baseline
            )
            let effect: PerformedEffect
            switch race {
            case .effect(let returnedEffect, let completedObservationCycle):
                effectCompletedObservationCycle = completedObservationCycle
                effect = returnedEffect
            case .cancelled(let completedObservationCycle):
                effectCompletedObservationCycle = completedObservationCycle
                throw CancellationError()
            case .deadline(let terminalClose, let completedObservationCycle):
                effectCompletedObservationCycle = completedObservationCycle
                if completedObservationCycle,
                   let terminalClose {
                    return runtime.machine.advance(admit(
                        terminalClose,
                        expiration: runtime.deadlines.expiration(at: RuntimeElapsed.now),
                        runtime: &runtime
                    ))
                }
                if case .dispatch(let id, let command) = request {
                    return await timedOutDispatchDecision(
                        id,
                        command: command,
                        inbox: inbox,
                        runtime: &runtime
                    )
                }
                return await terminalDeadlineDecision(
                    runtime.deadlines.expiration(at: RuntimeElapsed.now) ?? .whole,
                    inbox: inbox,
                    currentDecision: currentDecision,
                    reducesStaleEffectRequest: true,
                    runtime: &runtime
                )
            }
            do {
                try Task.checkCancellation()
            } catch {
                admitCompletedCloseBeforeCancellation(effect, runtime: &runtime)
                throw error
            }
            effectCompletedObservationCycle = false
            switch effect {
            case .input(.failureScreenshotCaptured):
                return runtime.machine.advance(admit(effect, runtime: &runtime))

            case .observationClosed:
                let expiration = runtime.deadlines.expiration(at: RuntimeElapsed.now)
                let decision = runtime.machine.advance(admit(
                    effect,
                    expiration: expiration,
                    runtime: &runtime
                ))
                return decision

            case .viewportExited:
                let decision = runtime.machine.advance(admit(effect, runtime: &runtime))
                guard let expiration = runtime.deadlines.expiration(at: RuntimeElapsed.now) else {
                    return decision
                }
                return await terminalDeadlineDecision(
                    expiration,
                    inbox: inbox,
                    currentDecision: decision,
                    runtime: &runtime
                )

            case .observationBegan(let observation):
                let decision = admitObservationBegan(effect, observation: observation, runtime: &runtime)
                guard let expiration = runtime.deadlines.expiration(at: RuntimeElapsed.now) else {
                    return decision
                }
                return await terminalDeadlineDecision(
                    expiration,
                    inbox: inbox,
                    currentDecision: decision,
                    runtime: &runtime
                )

            case .input:
                guard let expiration = runtime.deadlines.expiration(at: RuntimeElapsed.now) else {
                    return runtime.machine.advance(admit(effect, runtime: &runtime))
                }
                discard(effect)
                return await terminalDeadlineDecision(
                    expiration,
                    inbox: inbox,
                    currentDecision: currentDecision,
                    reducesStaleEffectRequest: true,
                    runtime: &runtime
                )
            }
        }

        private func admitObservationBegan(
            _ effect: PerformedEffect, observation: ActiveObservation, runtime: inout Runtime
        ) -> Decision {
            let decision = runtime.machine.advance(admit(effect, runtime: &runtime))
            let stream = brains.vault.semanticObservationStream
            let historyIndex = stream.executionHistoryIndex(reusing: brains.vault.state.current)
            guard case .wait = decision,
                  observation.boundary.historyIndex == historyIndex,
                  runtime.historyIndex <= historyIndex,
                  historyIndex < brains.vault.state.history.endIndex
            else { return decision }
            if runtime.historyIndex < observation.boundary.historyIndex {
                stream.advanceHistoryProtection(
                    from: runtime.historyIndex,
                    to: observation.boundary.historyIndex
                )
                runtime.historyIndex = observation.boundary.historyIndex
            }
            return advance(.noChange, runtime: &runtime)
        }

        private func timedOutDispatchDecision(
            _ id: RequestID,
            command: ResolvedHeistActionCommand,
            inbox: ObservationInbox,
            runtime: inout Runtime
        ) async -> Decision {
            let effect = PerformedEffect.input(.dispatchCompleted(
                id,
                .failure(
                    command.actionResultPayload,
                    message: "action dispatch timed out at the action deadline",
                    failureKind: .timeout
                )
            ))
            let decision = runtime.machine.advance(admit(effect, runtime: &runtime))
            return await terminalDeadlineDecision(
                runtime.deadlines.expiration(at: RuntimeElapsed.now) ?? .whole,
                inbox: inbox,
                currentDecision: decision,
                runtime: &runtime
            )
        }

        private func perform(
            _ request: MainActorRequest,
            runtime: Runtime,
            baseline: Observation.Stream.ExecutionAdmission?
        ) async throws -> PerformedEffect {
            switch request {
            case .currentSnapshot(let id, let scope):
                let current: TheVault.State.Current?
                switch scope {
                case .visible:
                    current = await brains.vault.semanticObservationStream
                        .admittedVisibleObservation(boundary: .cancellation)
                case .discovery:
                    current = await brains.navigation.fullGraph()?.current
                }
                return .input(.currentSnapshot(id, current?.snapshot))

            case .beginObservation(let id, let request):
                return try await beginObservation(
                    id: id,
                    request: request,
                    runtime: runtime,
                    baseline: baseline
                )

            case .dispatch(let id, let command):
                guard let deadline = activeLeafDeadline(id: id, runtime: runtime) else {
                    return .input(.dispatchCompleted(id, .failure(
                        command.actionResultPayload,
                        message: "action dispatch has no active leaf deadline",
                        failureKind: .actionFailed
                    )))
                }
                return .input(.dispatchCompleted(
                    id,
                    await brains.dispatchRuntimeAction(command, deadline: deadline)
                ))

            case .explore(let id, let predicate):
                let outcome: Navigation.ViewportExit.Outcome
                if let deadline = activeLeafDeadline(id: id, runtime: runtime) {
                    outcome = await brains.navigation.exploreForWait(
                        target: predicate.resolved.watchTarget,
                        deadline: deadline,
                        stopWhen: { false }
                    )
                } else {
                    outcome = .failed(.originUnavailable)
                }
                return .viewportExited(id, outcome)

            case .finishObservation(let requestID, let observationID, let exitPosition):
                return try await finishObservation(
                    requestID: requestID,
                    observationID: observationID,
                    exitPosition: exitPosition,
                    runtime: runtime
                )

            case .captureFailureScreenshot(let id, let failedPath, let mode):
                return .input(.failureScreenshotCaptured(
                    id,
                    await failureScreenshot(failedPath: failedPath, mode: mode)
                ))
            }
        }

        private func raceEffect(
            _ request: MainActorRequest,
            runtime: Runtime,
            baseline: Observation.Stream.ExecutionAdmission?
        ) async -> EffectRace {
            let receipt = SemanticObservationCycleReceipt()
            if case .captureFailureScreenshot = request {
                let winner = await SemanticObservationCycleContext.$receipt.withValue(receipt) {
                    do {
                        return EffectRace.effect(try await perform(
                            request,
                            runtime: runtime,
                            baseline: baseline
                        ), completedObservationCycle: false)
                    } catch {
                        return .cancelled(completedObservationCycle: false)
                    }
                }
                if case .effect(let effect, _) = winner {
                    return .effect(effect, completedObservationCycle: receipt.completed)
                }
                if case .cancelled = winner {
                    return .cancelled(completedObservationCycle: receipt.completed)
                }
                return winner
            }
            let delay = runtime.deadlines.remainingDuration(at: RuntimeElapsed.now)
            let winner = await SemanticObservationCycleContext.$receipt.withValue(receipt) {
                await withTaskGroup(of: EffectRace.self) { group in
                    group.addTask { [self] in
                        do {
                            return .effect(
                                try await perform(
                                    request,
                                    runtime: runtime,
                                    baseline: baseline
                                ),
                                completedObservationCycle: false
                            )
                        } catch {
                            return .cancelled(completedObservationCycle: false)
                        }
                    }
                    group.addTask {
                        await Task.cancellableSleep(for: delay)
                            ? .deadline(observationClosed: nil, completedObservationCycle: false)
                            : .cancelled(completedObservationCycle: false)
                    }
                    let winner = await group.next()
                        ?? .cancelled(completedObservationCycle: false)
                    group.cancelAll()
                    var terminalClose: PerformedEffect?
                    while let result = await group.next() {
                        guard case .effect(let effect, _) = result else { continue }
                        if case .observationClosed = effect {
                            terminalClose = effect
                        } else {
                            discard(effect)
                        }
                    }
                    return (winner, terminalClose)
                }
            }
            switch winner.0 {
            case .effect(let effect, _):
                return .effect(effect, completedObservationCycle: receipt.completed)
            case .deadline:
                return .deadline(
                    observationClosed: winner.1,
                    completedObservationCycle: receipt.completed
                )
            case .cancelled:
                return .cancelled(completedObservationCycle: receipt.completed)
            }
        }

        private func beginObservation(
            id: RequestID,
            request: ObservationRequest,
            runtime: Runtime,
            baseline: Observation.Stream.ExecutionAdmission?
        ) async throws -> PerformedEffect {
            precondition(runtime.observation == nil, "Only one observation boundary may be active")
            let stream = brains.vault.semanticObservationStream
            let scope = stream.subscribe(scope: request.scope)
            let leafDeadline = SemanticObservationDeadline(start: RuntimeElapsed.now, timeout: request.timeout)
            let beginsAction: Bool
            if case .action(let leaf)? = runtime.machine.running.activeLeaf,
               leaf.id == id,
               case .beginningObservation = leaf.phase {
                beginsAction = true
            } else {
                beginsAction = false
            }
            let viewportOutcome: Navigation.ViewportExit.Outcome?
            let capture: TheVault.State.Current?
            let boundary: TheVault.State.HistoryBoundary
            switch request.scope {
            case .visible:
                if let baseline {
                    let initial = await stream.admitExecutionBaseline(
                        baseline,
                        deadline: leafDeadline
                    )
                    capture = initial.current
                    boundary = initial.boundary
                    if capture == nil, beginsAction {
                        stream.activateExecutionDelivery(baseline.subscription)
                    }
                } else {
                    capture = await stream.admittedVisibleObservation(
                        boundary: .externalDeadline(leafDeadline)
                    )
                    boundary = .init(
                        baseline: capture?.snapshot,
                        historyIndex: stream.executionHistoryIndex(reusing: capture)
                    )
                }
                viewportOutcome = capture == nil ? nil : .retained
            case .discovery:
                capture = nil
                viewportOutcome = await brains.navigation.fullGraph(deadline: leafDeadline)?.viewportExit
                boundary = stream.observationBoundary(scope: request.scope)
            }
            do {
                try Task.checkCancellation()
            } catch {
                scope.cancel()
                throw error
            }
            let notificationWindow = brains.vault.accessibilityNotifications.beginActionWindow()
            var viewportStatus = ViewportStatus.available
            viewportStatus.record(viewportOutcome)
            let observation = ActiveObservation(
                id: id,
                boundary: boundary,
                scopeSubscription: scope,
                notificationWindow: notificationWindow,
                deadline: leafDeadline,
                lastTreeChangeAt: nil,
                viewportStatus: viewportStatus
            )
            guard beginsAction || capture != nil || boundary.baseline != nil else {
                return .observationClosed(
                    observation,
                    source: .deadline,
                    result: .init(
                        evidence: .init(
                            baseline: nil,
                            events: [],
                            current: nil,
                            coverage: .incomplete(.captureUnavailable)
                        ),
                        timing: expectationTiming(for: observation),
                        viewportStatus: .unavailable
                    )
                )
            }
            return .observationBegan(observation)
        }

        private func finishObservation(
            requestID: RequestID,
            observationID: RequestID,
            exitPosition: Navigation.ViewportExitPosition,
            runtime: Runtime
        ) async throws -> PerformedEffect {
            guard let observation = runtime.observation, observation.id == observationID else {
                return .input(.observationFinished(
                    source: .request(requestID), observationID: observationID,
                    evidence: .init(
                        baseline: nil,
                        events: [],
                        current: nil,
                        coverage: .incomplete(.captureUnavailable)
                    ),
                    outcome: .unavailable,
                    timing: .init(budgetMs: 0, elapsedMs: 0, lastTreeChangeElapsedMs: nil)
                ))
            }
            let result = await closeObservation(
                observation,
                exitPosition: exitPosition,
                capture: .coverage,
                runtime: runtime
            )
            return .observationClosed(
                observation,
                source: .request(requestID),
                result: result
            )
        }

        private func admit(
            _ effect: PerformedEffect,
            expiration: DeadlineExpiration? = nil,
            runtime: inout Runtime
        ) -> Input {
            switch effect {
            case .input(let input):
                return input
            case .observationBegan(let observation):
                precondition(runtime.observation == nil, "Only one observation boundary may be active")
                runtime.observation = observation
                runtime.deadlines = .leaf(
                    whole: runtime.deadlines.whole,
                    leaf: observation.deadline
                )
                return .observationBegan(observation.id, baseline: observation.boundary.baseline)
            case .viewportExited(let id, let outcome):
                if var observation = runtime.observation, observation.id == id {
                    observation.viewportStatus.record(outcome)
                    runtime.observation = observation
                }
                return .viewportExited(id, outcome)
            case .observationClosed(let observation, let source, let result):
                return admitObservationCloseResult(
                    observation,
                    source: source,
                    result: result,
                    expiration: expiration,
                    runtime: &runtime
                )
            }
        }

        private func discard(_ effect: PerformedEffect) {
            guard case .observationBegan(let observation) = effect else { return }
            release(observation)
        }

        private func admitCompletedCloseBeforeCancellation(
            _ effect: PerformedEffect,
            runtime: inout Runtime
        ) {
            guard case .observationClosed = effect else {
                discard(effect)
                return
            }
            _ = admit(effect, expiration: .whole, runtime: &runtime)
        }

        private func advance(
            _ event: Observation.Event,
            runtime: inout Runtime
        ) -> Decision {
            if event.changesInterface, var observation = runtime.observation {
                observation.lastTreeChangeAt = RuntimeElapsed.now
                runtime.observation = observation
            }
            return runtime.machine.advance(.event(event))
        }

        private func deadlineDecision(
            _ expiration: DeadlineExpiration,
            runtime: inout Runtime
        ) async -> Decision {
            guard let observation = runtime.observation else {
                return runtime.machine.finishAfterHeistTimeout()
            }
            let result = await closeObservation(
                observation,
                exitPosition: .current,
                capture: .singleCycle,
                runtime: runtime
            )
            let input = admitObservationCloseResult(
                observation,
                source: .deadline,
                result: result,
                expiration: expiration,
                runtime: &runtime
            )
            return runtime.machine.advance(input)
        }

        private func terminalDeadlineDecision(
            _ expiration: DeadlineExpiration,
            inbox: ObservationInbox,
            currentDecision: Decision,
            reducesStaleEffectRequest: Bool = false,
            runtime: inout Runtime
        ) async -> Decision {
            var decision = currentDecision
            var mayReduceEvent = reducesStaleEffectRequest
            while mayReduceEvent || {
                if case .wait = decision { return true }
                return false
            }() {
                guard let event = await inbox.pop() else { break }
                decision = advance(event, runtime: &runtime)
                mayReduceEvent = false
            }
            if case .complete = decision { return decision }
            return await deadlineDecision(expiration, runtime: &runtime)
        }

        private func admitObservationCloseResult(
            _ observation: ActiveObservation,
            source: ObservationFinishSource,
            result: ObservationCloseResult,
            expiration: DeadlineExpiration? = nil,
            runtime: inout Runtime
        ) -> Input {
            release(observation)
            runtime.observation = nil
            runtime.deadlines = .whole(runtime.deadlines.whole)
            let nextHistoryIndex = brains.vault.semanticObservationStream
                .executionHistoryIndex(reusing: brains.vault.state.current)
            brains.vault.semanticObservationStream.advanceHistoryProtection(
                from: runtime.historyIndex,
                to: nextHistoryIndex
            )
            runtime.historyIndex = nextHistoryIndex
            let expectationSatisfied = runtime.machine.running.activeLeaf.map {
                $0.id == observation.id && $0.expectationIsProven(by: result.evidence)
            } ?? false
            let outcome: LeafOutcome
            if case .available = result.viewportStatus, expectationSatisfied {
                outcome = .completed
            } else {
                outcome = observationOutcome(
                    viewportStatus: result.viewportStatus,
                    expiration: expiration,
                    hasObservedState: result.evidence.baseline != nil || result.evidence.current != nil
                )
            }
            return .observationFinished(
                source: source,
                observationID: observation.id,
                evidence: result.evidence,
                outcome: outcome,
                timing: result.timing
            )
        }

        private func observationOutcome(
            viewportStatus: ViewportStatus,
            expiration: DeadlineExpiration?,
            hasObservedState: Bool
        ) -> LeafOutcome {
            switch viewportStatus {
            case .failed(let failure): .viewportExitFailed(failure)
            case .unavailable where !hasObservedState: .unavailable
            case .unavailable:
                expiration.map { $0.includesWhole ? .heistTimedOut : .timedOut } ?? .unavailable
            case .available:
                expiration.map { $0.includesWhole ? .heistTimedOut : .timedOut } ?? .completed
            }
        }

        private func closeObservation(
            _ observation: ActiveObservation,
            exitPosition: Navigation.ViewportExitPosition,
            capture: ObservationCloseCapture,
            runtime: Runtime
        ) async -> ObservationCloseResult {
            var viewportStatus = observation.viewportStatus
            if case .origin = exitPosition {
                viewportStatus.record(await brains.navigation.fullGraph(
                    deadline: activeLeafDeadline(id: observation.id, runtime: runtime)
                )?.viewportExit)
            }
            let coverageAdmitted = await observation.notificationWindow.admitCausallyCovered { [self] coverage -> Bool? in
                let stream = brains.vault.semanticObservationStream
                let coverageCaptured = switch capture {
                case .coverage where stream.hasCommittedObservation(covering: coverage):
                    true
                case .coverage:
                    await stream.visibleObservation(covering: coverage) != nil
                case .singleCycle:
                    await stream.visibleObservationAfterNextCycle(covering: coverage) != nil
                }
                guard coverageCaptured else { return nil }
                guard case .coverage = capture else {
                    guard activeLeafEvidence(for: observation, runtime: runtime).map({
                        $0.0.needsStabilityCapture(after: $0.1)
                    }) == true else {
                        return true
                    }
                    return await stream.visibleObservationAfterNextCycle(covering: coverage) != nil
                }
                while activeLeafEvidence(for: observation, runtime: runtime).map({
                    $0.0.expectationIsProven(by: $0.1)
                }) != true {
                    guard case .committed = await stream.refreshedVisibleObservation(
                        boundary: .externalDeadline(observation.deadline)
                    ) else {
                        return nil
                    }
                }
                return true
            }
            viewportStatus.record(coverageAdmitted == nil ? nil : .retained)
            return ObservationCloseResult(
                evidence: evidence(for: observation, terminalCaptureAvailable: coverageAdmitted != nil),
                timing: expectationTiming(for: observation),
                viewportStatus: viewportStatus
            )
        }

        private func activeLeafEvidence(
            for observation: ActiveObservation,
            runtime: Runtime
        ) -> (HeistExecution.ActiveLeaf, Observation.Evidence)? {
            guard let leaf = runtime.machine.running.activeLeaf,
                  leaf.id == observation.id else { return nil }
            return (leaf, brains.vault.state.evidence(after: observation.boundary))
        }

        private func restoreTerminalViewport(
            runtime: inout Runtime,
            effectCompletedObservationCycle: Bool
        ) async {
            guard let observation = runtime.observation else { return }
            guard !effectCompletedObservationCycle else {
                release(observation)
                runtime.observation = nil
                runtime.deadlines = .whole(runtime.deadlines.whole)
                return
            }
            let result = await closeObservation(
                observation,
                exitPosition: .current,
                capture: .singleCycle,
                runtime: runtime
            )
            _ = admitObservationCloseResult(
                observation,
                source: .deadline,
                result: result,
                expiration: .whole,
                runtime: &runtime
            )
        }

        private func activeLeafDeadline(id: RequestID, runtime: Runtime) -> SemanticObservationDeadline? {
            guard runtime.observation?.id == id,
                  case .leaf(_, let leaf) = runtime.deadlines else { return nil }
            return leaf
        }

        private func evidence(for observation: ActiveObservation, terminalCaptureAvailable: Bool) -> Observation.Evidence {
            let evidence = brains.vault.state.evidence(after: observation.boundary)
            if terminalCaptureAvailable || evidence.coverage != .complete {
                return evidence
            }
            return .init(
                baseline: evidence.baseline,
                events: evidence.events,
                current: evidence.current,
                coverage: .incomplete(.captureUnavailable)
            )
        }

        private func expectationTiming(for observation: ActiveObservation) -> HeistExpectationTiming {
            .init(
                budgetMs: RuntimeElapsed.admit(milliseconds: observation.deadline.budgetMilliseconds),
                elapsedMs: RuntimeElapsed.milliseconds(since: observation.deadline.start, endedAt: RuntimeElapsed.now),
                lastTreeChangeElapsedMs: observation.lastTreeChangeAt.map {
                    RuntimeElapsed.milliseconds(since: observation.deadline.start, endedAt: $0)
                }
            )
        }

        private func failureScreenshot(failedPath _: HeistExecutionPath, mode: ScreenCaptureMode) async -> HeistFailureCapture {
            switch await brains.captureScreenPayload(mode: mode, observationBoundary: .observationCycle) {
            case .success(let payload): .captured(payload)
            case .failure(let failure): .unavailable(kind: failure.actionFailureKind, message: failure.message)
            }
        }
        private func waitForEvent(from inbox: ObservationInbox, before delay: Duration) async -> Waiting {
            await withTaskGroup(of: Waiting.self) { group in
                group.addTask {
                    guard let event = await inbox.next() else { return .cancelled }
                    return .event(event)
                }
                group.addTask {
                    await Task.cancellableSleep(for: delay) ? .deadline : .cancelled
                }
                let first = await group.next() ?? .deadline
                group.cancelAll()
                var queuedEvent: Observation.Event?
                while let result = await group.next() {
                    if case .event(let event) = result {
                        queuedEvent = event
                    }
                }
                if case .event = first { return first }
                return queuedEvent.map(Waiting.event) ?? first
            }
        }

        private func release(_ observation: ActiveObservation) {
            observation.scopeSubscription.cancel()
            observation.notificationWindow.cancel()
        }

        private func release(_ lifetime: Lifetime, historyIndex: Int) {
            lifetime.eventSubscription.cancel()
            lifetime.observationDemand.cancel()
            lifetime.notificationScope.cancel()
            brains.vault.semanticObservationStream.releaseHistory(
                from: historyIndex
            )
        }

        private func admitTerminalNotifications(
            _ scope: AccessibilityNotificationScopeLease,
            after cursor: AccessibilityNotificationCursor
        ) async -> Bool {
            guard let admitted = await scope.admitCausallyCovered({ [self] coverage in
                let terminalCoverage = AccessibilityNotificationCoverage(
                    after: cursor,
                    through: coverage.through,
                    scopedScreenChangedThrough: coverage.scopedScreenChangedThrough > cursor.sequence
                        ? coverage.scopedScreenChangedThrough
                        : 0
                )
                guard terminalCoverage.requiresObservation else {
                    return true
                }
                return await brains.vault.semanticObservationStream
                    .visibleObservationThroughCausalCycles(covering: terminalCoverage) != nil
            }), admitted else {
                scope.cancel()
                return false
            }
            return true
        }

    }
}

private actor ObservationInbox {
    private let stream: AsyncStream<Observation.Event>
    nonisolated private let emit: AsyncStream<Observation.Event>.Continuation
    nonisolated private let count = OSAllocatedUnfairLock(initialState: 0)

    init() {
        var capturedEmit: AsyncStream<Observation.Event>.Continuation?
        stream = AsyncStream { capturedEmit = $0 }
        guard let capturedEmit else {
            preconditionFailure("An observation inbox requires an event stream")
        }
        emit = capturedEmit
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
