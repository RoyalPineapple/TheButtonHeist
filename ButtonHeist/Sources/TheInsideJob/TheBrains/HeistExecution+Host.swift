#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    @MainActor
    internal final class Host {
        private enum Phase {
            case idle
            case running(Session)
            case cleaning
            case finished
        }

        private struct Session {
            var machine: Machine
            let continuation: CheckedContinuation<Completion, any Error>
            var protectedHistoryIndex: Int
            let eventSubscription: SemanticObservationSubscription
            let observationDemand: SemanticObservationDemand
            let notificationScope: AccessibilityNotificationScopeLease
            var observation: ObservationPhase
            var interaction: Interaction
            var deadlines: DeadlineState
        }

        private struct ActiveObservation {
            let id: RequestID
            var boundary: TheVault.State.HistoryBoundary
            let scopeSubscription: SemanticObservationSubscription
            let notificationWindow: AccessibilityNotificationScopeLease
            let deadline: SemanticObservationDeadline
            var lastTreeChangeAt: RuntimeElapsed.Instant?
            var viewportStatus: ViewportStatus
        }

        private enum ObservationPhase {
            case idle
            case establishing
            case active(ActiveObservation)

            var active: ActiveObservation? {
                guard case .active(let observation) = self else { return nil }
                return observation
            }
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
                case .restored?, .retained?, .superseded?:
                    .available
                case .failed(let failure)?:
                    .failed(failure)
                case nil:
                    .unavailable
                }
            }
        }

        private enum Interaction {
            case idle
            case running(
                InteractionID,
                task: Task<Void, Never>,
                deferred: MainActorRequest?,
                completesAfterDeadline: Bool
            )
        }

        private struct InteractionID: Equatable {
            let sequence: UInt64
        }

        private enum DeadlineTargets {
            case whole(SemanticObservationDeadline)
            case leaf(
                whole: SemanticObservationDeadline,
                leaf: SemanticObservationDeadline
            )

            var whole: SemanticObservationDeadline {
                switch self {
                case .whole(let whole), .leaf(let whole, _):
                    whole
                }
            }
        }

        private enum DeadlineExpiration {
            case leaf
            case whole
            case leafAndWhole

            var includesWhole: Bool {
                switch self {
                case .leaf:
                    false
                case .whole, .leafAndWhole:
                    true
                }
            }
        }

        private struct DeadlineTimerID: Equatable {
            let sequence: UInt64
        }

        private enum DeadlineState {
            case unscheduled(DeadlineTargets)
            case armed(
                DeadlineTargets,
                timerID: DeadlineTimerID,
                task: Task<Void, Never>
            )
            case expiredAwaitingInteraction(DeadlineTargets, DeadlineExpiration)
            case collectingTerminalEvidence(DeadlineTargets, DeadlineExpiration)

            var targets: DeadlineTargets {
                switch self {
                case .unscheduled(let targets),
                     .armed(let targets, _, _),
                     .expiredAwaitingInteraction(let targets, _),
                     .collectingTerminalEvidence(let targets, _):
                    targets
                }
            }

            var expiration: DeadlineExpiration? {
                switch self {
                case .unscheduled, .armed:
                    nil
                case .expiredAwaitingInteraction(_, let expiration),
                     .collectingTerminalEvidence(_, let expiration):
                    expiration
                }
            }

            func cancelTimer() {
                guard case .armed(_, _, let task) = self else { return }
                task.cancel()
            }
        }

        private let brains: TheBrains
        private var phase = Phase.idle
        private var nextDeadlineTimerSequence: UInt64 = 0
        private var nextInteractionSequence: UInt64 = 0

        internal init(brains: TheBrains) {
            self.brains = brains
        }

        internal func execute(
            _ plan: HeistPlan,
            argument: HeistArgument = .none,
            timeout: HeistTimeout,
            actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default
        ) async throws -> Completion {
            let machine = try Machine(
                plan: plan,
                argument: argument,
                failureCaptureMode: brains.failureEvidencePolicy.captureMode,
                actionExpectationTimeoutPolicy: actionExpectationTimeoutPolicy
            )
            return try await execute(machine, timeout: timeout)
        }

        internal func execute(
            _ action: HeistActionCommand,
            timeout: HeistTimeout
        ) async throws -> Completion {
            let machine = Machine(
                action: action,
                failureCaptureMode: brains.failureEvidencePolicy.captureMode
            )
            return try await execute(machine, timeout: timeout)
        }

        private func execute(
            _ machine: Machine,
            timeout: HeistTimeout
        ) async throws -> Completion {
            guard case .idle = phase else {
                preconditionFailure("A heist host executes exactly one command")
            }

            let wholeDeadline = SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeout: .seconds(timeout.seconds)
            )

            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let stream = brains.vault.semanticObservationStream
                let historyIndex = stream.historyEndIndex()
                stream.protectHistory(from: historyIndex)
                let observationDemand = stream.beginActiveObservationDemand()
                let notificationScope = brains.vault.accessibilityNotifications
                    .beginHeistScope()
                let eventInstallation = stream.subscribe(
                    scope: .visible,
                    replayingAfter: historyIndex,
                    receive: { [weak self] event in
                        self?.receive(event)
                    }
                )

                let replay: [Observation.Event]
                do {
                    replay = try eventInstallation.replay.get()
                    try Task.checkCancellation()
                } catch {
                    eventInstallation.subscription.cancel()
                    observationDemand.cancel()
                    notificationScope.cancel()
                    stream.releaseHistory(from: historyIndex)
                    throw error
                }
                return try await withCheckedThrowingContinuation { continuation in
                    var session = Session(
                        machine: machine,
                        continuation: continuation,
                        protectedHistoryIndex: historyIndex,
                        eventSubscription: eventInstallation.subscription,
                        observationDemand: observationDemand,
                        notificationScope: notificationScope,
                        observation: .idle,
                        interaction: .idle,
                        deadlines: .unscheduled(.whole(wholeDeadline))
                    )
                    phase = .running(session)
                    armDeadline()

                    guard case .running(var current) = phase else { return }
                    let state = current.machine.start()
                    session = current
                    phase = .running(session)
                    interpret(state)
                    for event in replay {
                        receive(event)
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancel()
                }
            }
        }

        private func receive(_ event: Observation.Event) {
            switch phase {
            case .running(var session):
                switch session.observation {
                case .idle:
                    phase = .running(session)
                    advance(.event(event))
                case .establishing:
                    phase = .running(session)
                case .active(var observation):
                    if event.changesInterface {
                        observation.lastTreeChangeAt = RuntimeElapsed.now
                        session.observation = .active(observation)
                    }
                    phase = .running(session)
                    advance(.event(event))
                }
            case .idle, .cleaning, .finished:
                break
            }
        }

        private func advance(_ input: Input) {
            guard case .running(var session) = phase else { return }
            let decision = session.machine.advance(input)
            phase = .running(session)
            returnToDeadlineScope(decision)
        }

        private func returnToDeadlineScope(_ decision: Decision) {
            guard case .running(let session) = phase else { return }
            if let expiration = session.deadlines.expiration {
                if case .complete(let completion) = decision {
                    resolve(.success(completion))
                    return
                }
                if case .perform(let request) = decision,
                   request.completesAfterDeadline {
                    performRequest(request, afterDeadline: true)
                    return
                }
                guard case .idle = session.interaction else { return }
                collectTerminalEvidence(expiration)
                return
            }
            interpret(decision)
        }

        private func interpret(_ decision: Decision) {
            guard case .running(var session) = phase else { return }
            switch decision {
            case .complete(let completion):
                resolve(.success(completion))

            case .wait:
                phase = .running(session)
                armDeadline()

            case .perform(let request):
                switch session.interaction {
                case .idle:
                    phase = .running(session)
                    armDeadline()
                    performRequest(request)
                case .running(let id, let task, _, let completesAfterDeadline):
                    session.interaction = .running(
                        id,
                        task: task,
                        deferred: request,
                        completesAfterDeadline: completesAfterDeadline
                    )
                    phase = .running(session)
                    armDeadline()
                }
            }
        }

        private func performRequest(
            _ request: MainActorRequest,
            afterDeadline: Bool = false
        ) {
            guard case .running(var session) = phase,
                  afterDeadline || session.deadlines.expiration == nil else {
                return
            }
            let interactionID = nextInteractionID()
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.perform(request, interactionID: interactionID)
                self.interactionFinished(interactionID)
            }
            session.interaction = .running(
                interactionID,
                task: task,
                deferred: nil,
                completesAfterDeadline: request.completesAfterDeadline
            )
            phase = .running(session)
        }

        private func perform(
            _ request: MainActorRequest,
            interactionID: InteractionID
        ) async {
            switch request {
            case .currentSnapshot(let id, let scope):
                let snapshot = await brains.captureHeistCurrentState(scope: scope)?
                    .snapshot
                complete(interactionID, input: .currentSnapshot(id, snapshot))

            case .beginObservation(let id, let request):
                await beginObservation(
                    id: id,
                    request: request,
                    interactionID: interactionID
                )

            case .dispatch(let id, let command):
                guard let deadline = activeLeafDeadline(id: id) else {
                    complete(
                        interactionID,
                        input: .dispatchCompleted(
                            id,
                            .failure(
                                command.actionResultPayload,
                                message: "action dispatch has no active leaf deadline",
                                failureKind: .actionFailed
                            )
                        )
                    )
                    return
                }
                let result = await brains.dispatchRuntimeAction(
                    command,
                    deadline: deadline
                )
                complete(interactionID, input: .dispatchCompleted(id, result))

            case .explore(let id, let predicate):
                let deadline = activeLeafDeadline(id: id)
                let outcome: Navigation.ViewportExit.Outcome
                if let deadline {
                    outcome = await brains.navigation.exploreForWait(
                        target: predicate.resolved.watchTarget,
                        deadline: deadline,
                        stopWhen: { [weak self] in
                            self?.shouldStopExploration(interactionID) == true
                        }
                    )
                } else {
                    outcome = .failed(.originUnavailable)
                }
                guard case .running(var session) = phase,
                      case .active(var observation) = session.observation,
                      observation.id == id else {
                    return
                }
                observation.viewportStatus.record(outcome)
                session.observation = .active(observation)
                phase = .running(session)
                complete(interactionID, input: .viewportExited(id, outcome))

            case .finishObservation(
                let requestID,
                let observationID,
                let exitPosition
            ):
                await finishObservation(
                    requestID: requestID,
                    observationID: observationID,
                    exitPosition: exitPosition,
                    interactionID: interactionID
                )

            case .captureFailureScreenshot(
                let id,
                let failedPath,
                let mode
            ):
                let result = await failureScreenshot(
                    failedPath: failedPath,
                    mode: mode
                )
                complete(
                    interactionID,
                    input: .failureScreenshotCaptured(id, result)
                )
            }
        }

        private func beginObservation(
            id: RequestID,
            request: ObservationRequest,
            interactionID: InteractionID
        ) async {
            guard case .running(var initialSession) = phase,
                  case .running(let current, _, _, _) = initialSession.interaction,
                  current == interactionID else {
                return
            }
            guard case .idle = initialSession.observation else {
                preconditionFailure("Only one observation boundary may be active")
            }
            initialSession.observation = .establishing
            phase = .running(initialSession)

            let stream = brains.vault.semanticObservationStream
            let scope = stream.subscribe(scope: request.scope)
            let leafDeadline = SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeout: request.timeout
            )
            guard case .running(let armedSession) = phase,
                  case .running(let current, _, _, _) = armedSession.interaction,
                  current == interactionID else {
                scope.cancel()
                return
            }
            phase = .running(armedSession)

            let viewportOutcome: Navigation.ViewportExit.Outcome?
            switch request.scope {
            case .visible:
                let current = await brains.captureHeistCurrentState(
                    scope: .visible
                )
                viewportOutcome = current == nil ? nil : .retained
            case .discovery:
                let exploration = await brains.navigation.fullGraph(
                    deadline: leafDeadline
                )
                viewportOutcome = exploration?.viewportExit
            }
            let capturedBoundary = stream.observationBoundary(
                scope: request.scope
            )

            guard case .running(var capturedSession) = phase,
                  case .running(let capturedInteractionID, _, _, _) = capturedSession.interaction,
                  capturedInteractionID == interactionID,
                  case .establishing = capturedSession.observation else {
                scope.cancel()
                return
            }
            let notificationWindow = brains.vault.accessibilityNotifications
                .beginActionWindow()
            var viewportStatus = ViewportStatus.available
            viewportStatus.record(viewportOutcome)
            capturedSession.observation = .active(ActiveObservation(
                id: id,
                boundary: capturedBoundary,
                scopeSubscription: scope,
                notificationWindow: notificationWindow,
                deadline: leafDeadline,
                lastTreeChangeAt: nil,
                viewportStatus: viewportStatus
            ))
            capturedSession.deadlines.cancelTimer()
            capturedSession.deadlines = .unscheduled(.leaf(
                whole: capturedSession.deadlines.targets.whole,
                leaf: leafDeadline
            ))
            phase = .running(capturedSession)
            complete(
                interactionID,
                input: .observationBegan(
                    id,
                    baseline: capturedBoundary.baseline
                )
            )
        }

        private func finishObservation(
            requestID: RequestID,
            observationID: RequestID,
            exitPosition: Navigation.ViewportExitPosition,
            interactionID: InteractionID
        ) async {
            guard case .running(let initialSession) = phase,
                  case .active(let observation) = initialSession.observation,
                  observation.id == observationID else {
                return
            }

            let result = await closeObservation(
                observation,
                exitPosition: exitPosition,
                capture: .coverage,
                source: .request(requestID)
            )
            await admitObservationCloseResult(
                interactionID: interactionID,
                observationID: observationID,
                source: .request(requestID),
                result: result
            )
        }

        private func complete(_ interactionID: InteractionID, input: Input) {
            guard case .running(var session) = phase,
                  case .running(let current, _, let deferred, _) = session.interaction,
                  current == interactionID else {
                return
            }
            session.interaction = .idle
            let state = session.machine.advance(input)
            phase = .running(session)

            guard case .running(let currentSession) = phase else { return }
            if currentSession.deadlines.expiration != nil {
                returnToDeadlineScope(state)
                return
            }

            interpret(state)
            guard case .running(let nextSession) = phase,
                  case .idle = nextSession.interaction,
                  let deferred else {
                return
            }
            performRequest(deferred)
        }

        private func shouldStopExploration(_ interactionID: InteractionID) -> Bool {
            guard case .running(let session) = phase,
                  case .running(let current, _, let deferred, _) = session.interaction,
                  current == interactionID else {
                return true
            }
            return deferred != nil || session.deadlines.expiration != nil
        }

        private func interactionFinished(_ interactionID: InteractionID) {
            guard case .running(var session) = phase,
                  case .running(let current, _, let deferred, _) = session.interaction,
                  current == interactionID else {
                return
            }
            session.interaction = .idle
            let expiration = session.deadlines.expiration
            phase = .running(session)
            if let expiration {
                collectTerminalEvidence(expiration)
            } else if let deferred {
                performRequest(deferred)
            }
        }

        private func activeLeafDeadline(
            id: RequestID
        ) -> SemanticObservationDeadline? {
            guard case .running(let session) = phase,
                  session.observation.active?.id == id,
                  case .leaf(_, let leaf) = session.deadlines.targets else {
                return nil
            }
            return leaf
        }

        private func nextInteractionID() -> InteractionID {
            defer { nextInteractionSequence &+= 1 }
            return InteractionID(sequence: nextInteractionSequence)
        }

        private func armDeadline() {
            guard case .running(var session) = phase,
                  session.deadlines.expiration == nil else {
                return
            }
            session.deadlines.cancelTimer()
            let targets = session.deadlines.targets
            let now = RuntimeElapsed.now
            let delay: Duration
            switch targets {
            case .whole(let whole):
                delay = whole.remainingDuration(at: now)
            case .leaf(let whole, let leaf):
                delay = min(
                    whole.remainingDuration(at: now),
                    leaf.remainingDuration(at: now)
                )
            }
            let timerID = DeadlineTimerID(sequence: nextDeadlineTimerSequence)
            nextDeadlineTimerSequence &+= 1
            let task = Task { @MainActor [weak self] in
                guard await Task.cancellableSleep(for: delay) else { return }
                self?.deadlineExpired(timerID)
            }
            session.deadlines = .armed(
                targets,
                timerID: timerID,
                task: task
            )
            phase = .running(session)
        }

        private func deadlineExpired(_ timerID: DeadlineTimerID) {
            guard case .running(var session) = phase,
                  case .armed(let targets, let currentTimerID, _) = session.deadlines,
                  currentTimerID == timerID else {
                return
            }
            let now = RuntimeElapsed.now
            let expiration: DeadlineExpiration
            switch targets {
            case .whole:
                expiration = .whole
            case .leaf(let whole, let leaf):
                let wholeExpired = !whole.hasTimeRemaining(at: now)
                let leafExpired = !leaf.hasTimeRemaining(at: now)
                switch (leafExpired, wholeExpired) {
                case (true, true):
                    expiration = .leafAndWhole
                case (false, true):
                    expiration = .whole
                case (true, false):
                    expiration = .leaf
                case (false, false):
                    phase = .running(session)
                    armDeadline()
                    return
                }
            }
            session.deadlines = .expiredAwaitingInteraction(
                targets,
                expiration
            )
            switch session.interaction {
            case .idle:
                phase = .running(session)
                collectTerminalEvidence(expiration)
            case .running(_, let task, _, let completesAfterDeadline):
                phase = .running(session)
                if !completesAfterDeadline {
                    task.cancel()
                }
            }
        }

        private func collectTerminalEvidence(_ expiration: DeadlineExpiration) {
            guard case .running(var session) = phase,
                  case .idle = session.interaction else {
                return
            }
            guard let observation = session.observation.active else {
                let state = session.machine.finishAfterHeistTimeout()
                phase = .running(session)
                returnToDeadlineScope(state)
                return
            }

            session.deadlines = .collectingTerminalEvidence(
                session.deadlines.targets,
                expiration
            )
            let interactionID = nextInteractionID()
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.closeObservation(
                    observation,
                    exitPosition: .current,
                    capture: .singleCycle,
                    source: .deadline
                )
                await self.admitObservationCloseResult(
                    interactionID: interactionID,
                    observationID: observation.id,
                    source: .deadline,
                    result: result
                )
                self.interactionFinished(interactionID)
            }
            session.interaction = .running(
                interactionID,
                task: task,
                deferred: nil,
                completesAfterDeadline: true
            )
            phase = .running(session)
        }

        private func admitObservationCloseResult(
            interactionID: InteractionID,
            observationID: RequestID,
            source: ObservationFinishSource,
            result: ObservationCloseResult
        ) async {
            guard case .running(var session) = phase,
                  case .running(let current, _, _, _) = session.interaction,
                  current == interactionID,
                  case .active(let observation) = session.observation,
                  observation.id == observationID else {
                return
            }
            if case .request(let requestID) = source,
               session.machine.activeLeaf?.finishingObservationRequestID != requestID {
                return
            }
            release(observation)
            session.observation = .idle
            let expiration = session.deadlines.expiration
            session.deadlines.cancelTimer()
            if expiration?.includesWhole != true {
                session.deadlines = .unscheduled(.whole(
                    session.deadlines.targets.whole
                ))
            }
            let expectationSatisfied = session.machine.activeLeaf.map {
                $0.id == observation.id
                    && $0.expectationIsProven(by: result.evidence)
            } ?? false
            let outcome: LeafOutcome
            if case .available = result.viewportStatus,
               expectationSatisfied {
                outcome = .completed
            } else {
                outcome = observationOutcome(
                    viewportStatus: result.viewportStatus,
                    expiration: expiration,
                    hasObservedState: result.evidence.baseline != nil
                        || result.evidence.current != nil
                )
            }
            let nextProtectedHistoryIndex = brains.vault
                .semanticObservationStream.historyEndIndex()
            brains.vault.semanticObservationStream
                .advanceHistoryProtection(
                    from: session.protectedHistoryIndex,
                    to: nextProtectedHistoryIndex
                )
            session.protectedHistoryIndex = nextProtectedHistoryIndex
            phase = .running(session)
            complete(interactionID, input: .observationFinished(
                source: source,
                observationID: observation.id,
                evidence: result.evidence,
                outcome: outcome,
                timing: result.timing
            ))
        }

        private func observationOutcome(
            viewportStatus: ViewportStatus,
            expiration: DeadlineExpiration?,
            hasObservedState: Bool
        ) -> LeafOutcome {
            switch viewportStatus {
            case .failed(let failure):
                return .viewportExitFailed(failure)
            case .unavailable where !hasObservedState:
                return .unavailable
            case .unavailable:
                if let expiration {
                    return expiration.includesWhole ? .heistTimedOut : .timedOut
                }
                return .unavailable
            case .available:
                if let expiration {
                    return expiration.includesWhole ? .heistTimedOut : .timedOut
                }
                return .completed
            }
        }

        private func release(_ observation: ActiveObservation) {
            observation.scopeSubscription.cancel()
            observation.notificationWindow.cancel()
        }

        private func evidence(
            for observation: ActiveObservation,
            terminalCaptureAvailable: Bool
        ) -> Observation.Evidence {
            let evidence = brains.vault.semanticObservationStream
                .evidence(after: observation.boundary)
            guard terminalCaptureAvailable || evidence.coverage != .complete else {
                return Observation.Evidence(
                    baseline: evidence.baseline,
                    events: evidence.events,
                    current: evidence.current,
                    coverage: .incomplete(.captureUnavailable)
                )
            }
            return evidence
        }

        private func closeObservation(
            _ observation: ActiveObservation,
            exitPosition: Navigation.ViewportExitPosition,
            capture: ObservationCloseCapture,
            source: ObservationFinishSource
        ) async -> ObservationCloseResult {
            let existingEvidence = brains.vault.semanticObservationStream
                .evidence(after: observation.boundary)
            let expectationProven = {
                guard case .running(let session) = phase else { return false }
                return session.machine.activeLeaf.map {
                    $0.id == observation.id
                        && $0.expectationIsProven(by: existingEvidence)
                } ?? false
            }()
            var viewportStatus = observation.viewportStatus
            switch exitPosition {
            case .current:
                break
            case .origin:
                let exploration = await brains.navigation.fullGraph(
                    deadline: activeLeafDeadline(id: observation.id)
                )
                viewportStatus.record(exploration?.viewportExit)
            }
            let coverageAdmitted = await observation.notificationWindow
                .admitCausallyCovered { [self] coverage -> Bool? in
                    let stream = brains.vault.semanticObservationStream
                    if case .coverage = capture,
                       expectationProven,
                       stream.hasCommittedObservation(covering: coverage) {
                        return observationCloseIsCurrent(
                            observationID: observation.id,
                            source: source
                        ) ? true : nil
                    }
                    let current = switch capture {
                    case .coverage:
                        await stream.visibleObservation(covering: coverage)
                    case .singleCycle:
                        await stream.visibleObservationAfterNextCycle(
                            covering: coverage
                        )
                    }
                    guard current != nil,
                          observationCloseIsCurrent(
                              observationID: observation.id,
                              source: source
                          )
                    else { return nil }
                    return true
                }
            if coverageAdmitted == nil {
                viewportStatus.record(nil)
            } else {
                viewportStatus.record(.retained)
            }
            return ObservationCloseResult(
                evidence: evidence(
                    for: observation,
                    terminalCaptureAvailable: coverageAdmitted != nil
                ),
                timing: expectationTiming(for: observation),
                viewportStatus: viewportStatus
            )
        }

        private func observationCloseIsCurrent(
            observationID: RequestID,
            source: ObservationFinishSource
        ) -> Bool {
            guard case .running(let session) = phase,
                  session.observation.active?.id == observationID,
                  let activeLeaf = session.machine.activeLeaf,
                  activeLeaf.id == observationID
            else { return false }
            return activeLeaf.admits(source)
        }

        private func expectationTiming(
            for observation: ActiveObservation,
            endedAt: RuntimeElapsed.Instant = RuntimeElapsed.now
        ) -> HeistExpectationTiming {
            HeistExpectationTiming(
                budgetMs: RuntimeElapsed.admit(
                    milliseconds: observation.deadline.budgetMilliseconds
                ),
                elapsedMs: RuntimeElapsed.milliseconds(
                    since: observation.deadline.start,
                    endedAt: endedAt
                ),
                lastTreeChangeElapsedMs: observation.lastTreeChangeAt.map {
                    RuntimeElapsed.milliseconds(
                        since: observation.deadline.start,
                        endedAt: $0
                    )
                }
            )
        }

        private func failureScreenshot(
            failedPath _: HeistExecutionPath,
            mode: ScreenCaptureMode
        ) async -> HeistFailureCapture {
            switch await brains.captureScreenPayload(
                mode: mode,
                observationBoundary: .observationCycle
            ) {
            case .success(let payload):
                return .captured(payload)
            case .failure(let failure):
                return .unavailable(
                    kind: failure.actionFailureKind,
                    message: failure.message
                )
            }
        }

        private func cancel() {
            guard case .running = phase else { return }
            resolve(.failure(CancellationError()))
        }

        private func resolve(
            _ resolution: Result<Completion, CancellationError>
        ) {
            guard case .running(let session) = phase else { return }
            phase = .cleaning
            session.deadlines.cancelTimer()
            session.eventSubscription.cancel()
            switch session.interaction {
            case .idle:
                break
            case .running(_, let task, _, _):
                task.cancel()
            }
            if let observation = session.observation.active {
                observation.scopeSubscription.cancel()
                observation.notificationWindow.cancel()
            }
            if case .failure = resolution {
                session.notificationScope.cancel()
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .running(_, let task, _, _) = session.interaction {
                    _ = await task.value
                }
                let terminalFailure: HeistExecution.Failure?
                switch resolution {
                case .success:
                    terminalFailure = await self.admitTerminalNotifications(
                        session.notificationScope
                    )
                        ? nil
                        : .accessibilityTreeUnavailable
                case .failure:
                    terminalFailure = nil
                }
                session.observationDemand.cancel()
                self.brains.vault.semanticObservationStream
                    .releaseHistory(from: session.protectedHistoryIndex)
                self.phase = .finished
                if let terminalFailure {
                    session.continuation.resume(throwing: terminalFailure)
                    return
                }
                switch resolution {
                case .success(let completion):
                    session.continuation.resume(returning: completion)
                case .failure(let error):
                    session.continuation.resume(throwing: error)
                }
            }
        }

        private func admitTerminalNotifications(
            _ scope: AccessibilityNotificationScopeLease
        ) async -> Bool {
            guard await scope.admitCausallyCovered({ [self] coverage in
                guard coverage.requiresObservation else {
                    return true
                }
                return await brains.vault.semanticObservationStream
                    .visibleObservationThroughCausalCycles(
                        covering: coverage
                    ) != nil
            }) != nil else {
                scope.cancel()
                return false
            }
            return true
        }

    }
}

private extension HeistExecution.MainActorRequest {
    var completesAfterDeadline: Bool {
        guard case .captureFailureScreenshot = self else { return false }
        return true
    }

}

@MainActor
private extension TheBrains {
    func captureHeistCurrentState(
        scope: SemanticObservationScope
    ) async -> TheVault.State.Current? {
        switch scope {
        case .visible:
            guard case .committed(let current) =
                    await vault.semanticObservationStream
                        .refreshedVisibleObservation(boundary: .cancellation) else {
                return nil
            }
            return current
        case .discovery:
            return await navigation.fullGraph()?.current
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
