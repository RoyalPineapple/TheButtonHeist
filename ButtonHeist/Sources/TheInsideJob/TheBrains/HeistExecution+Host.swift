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
            case installing(Installation)
            case running(Session)
            case cleaning
            case finished
        }

        private struct Installation {
            var machine: Machine
            let wholeDeadline: SemanticObservationDeadline
            let protectedHistoryIndex: Int
            let observationDemand: SemanticObservationDemand
            let notificationScope: AccessibilityNotificationScopeLease
            var bufferedEvents: [Observation.Event]
            var historyError: Observation.History.ReadError?
        }

        private struct Session {
            var machine: Machine
            let continuation: CheckedContinuation<Completion, any Error>
            let protectedHistoryIndex: Int
            let eventSubscription: SemanticObservationSubscription
            let observationDemand: SemanticObservationDemand
            let notificationScope: AccessibilityNotificationScopeLease
            var activeObservation: ActiveObservation?
            var bufferedObservationEvents: [Observation.Event]?
            var interaction: Interaction
            var deadlines: DeadlineState
        }

        private struct ActiveObservation {
            let id: RequestID
            let request: ObservationRequest
            let boundary: TheVault.State.HistoryBoundary
            let scopeSubscription: SemanticObservationSubscription
            let notificationWindow: AccessibilityNotificationScopeLease
            var viewportStatus: ViewportStatus
        }

        private enum ViewportStatus {
            case available
            case unavailable
            case failed(Navigation.ViewportExit.Failure)

            mutating func record(_ outcome: Navigation.ViewportExit.Outcome?) {
                guard case .available = self else { return }
                switch outcome {
                case .restored?, .retained?, .superseded?:
                    break
                case .failed(let failure)?:
                    self = .failed(failure)
                case nil:
                    self = .unavailable
                }
            }
        }

        private enum Interaction {
            case idle
            case running(
                RequestToken,
                task: Task<Void, Never>,
                deferred: [MainActorRequest]
            )
        }

        private struct RequestToken: Equatable {
            enum Kind {
                case currentSnapshot
                case beginObservation
                case dispatch
                case explore
                case finishObservation
                case failureScreenshot
                case terminalEvidence

                var completesAfterDeadline: Bool {
                    switch self {
                    case .failureScreenshot, .terminalEvidence:
                        true
                    case .currentSnapshot,
                         .beginObservation,
                         .dispatch,
                         .explore,
                         .finishObservation:
                        false
                    }
                }
            }

            let id: RequestID
            let kind: Kind

            init(id: RequestID, kind: Kind) {
                self.id = id
                self.kind = kind
            }

            init(_ request: MainActorRequest) {
                switch request {
                case .currentSnapshot(let id, _):
                    self.init(id: id, kind: .currentSnapshot)
                case .beginObservation(let id, _):
                    self.init(id: id, kind: .beginObservation)
                case .dispatch(let id, _):
                    self.init(id: id, kind: .dispatch)
                case .explore(let id, _):
                    self.init(id: id, kind: .explore)
                case .finishObservation(let id, _):
                    self.init(id: id, kind: .finishObservation)
                case .captureFailureScreenshot(let id, _, _):
                    self.init(id: id, kind: .failureScreenshot)
                }
            }
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

        private enum BoundaryError: Error {
            case observationHistoryUnavailable
        }

        private unowned let brains: TheBrains
        private var phase = Phase.idle
        private var nextDeadlineTimerSequence: UInt64 = 0

        internal init(brains: TheBrains) {
            self.brains = brains
        }

        internal func execute(
            _ plan: HeistPlan,
            argument: HeistArgument = .none,
            timeout: HeistTimeout
        ) async throws -> Completion {
            guard case .idle = phase else {
                preconditionFailure("A heist host executes exactly one complete plan")
            }

            let machine = try Machine(
                plan: plan,
                argument: argument,
                failureCaptureMode: brains.failureEvidencePolicy.captureMode
            )
            let wholeDeadline = SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeout: .seconds(timeout.seconds)
            )

            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let stream = brains.vault.semanticObservationStream
                let historyIndex = await stream.stateOwner.historyEndIndex()
                await stream.stateOwner.protectHistory(from: historyIndex)

                phase = .installing(Installation(
                    machine: machine,
                    wholeDeadline: wholeDeadline,
                    protectedHistoryIndex: historyIndex,
                    observationDemand: stream.beginActiveObservationDemand(),
                    notificationScope: brains.vault.accessibilityNotifications
                        .beginHeistScope(),
                    bufferedEvents: [],
                    historyError: nil
                ))

                let subscription = await stream.subscribe(
                    scope: .visible,
                    replayingAfter: historyIndex,
                    receive: { [weak self] event in
                        self?.receive(event)
                    },
                    historyUnavailable: { [weak self] error in
                        self?.recordHistoryError(error)
                    }
                )

                do {
                    try Task.checkCancellation()
                    guard case .installing(let installation) = phase else {
                        subscription.cancel()
                        throw CancellationError()
                    }
                    if installation.historyError != nil {
                        subscription.cancel()
                        await clean(installation)
                        throw BoundaryError.observationHistoryUnavailable
                    }

                    return try await withCheckedThrowingContinuation { continuation in
                        var session = Session(
                            machine: installation.machine,
                            continuation: continuation,
                            protectedHistoryIndex: installation.protectedHistoryIndex,
                            eventSubscription: subscription,
                            observationDemand: installation.observationDemand,
                            notificationScope: installation.notificationScope,
                            activeObservation: nil,
                            bufferedObservationEvents: nil,
                            interaction: .idle,
                            deadlines: .unscheduled(.whole(
                                installation.wholeDeadline
                            ))
                        )
                        phase = .running(session)
                        armDeadline()

                        guard case .running(var current) = phase else { return }
                        let state = current.machine.start()
                        session = current
                        phase = .running(session)
                        interpret(state)
                        for event in installation.bufferedEvents {
                            receive(event)
                        }
                    }
                } catch {
                    if case .installing(let installation) = phase {
                        subscription.cancel()
                        await clean(installation)
                    }
                    throw error
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancel()
                }
            }
        }

        private func receive(_ event: Observation.Event) {
            switch phase {
            case .installing(var installation):
                installation.bufferedEvents.append(event)
                phase = .installing(installation)
            case .running(var session):
                guard var bufferedEvents = session.bufferedObservationEvents else {
                    advance(.event(event))
                    return
                }
                bufferedEvents.append(event)
                session.bufferedObservationEvents = bufferedEvents
                phase = .running(session)
            case .idle, .cleaning, .finished:
                break
            }
        }

        private func recordHistoryError(_ error: Observation.History.ReadError) {
            guard case .installing(var installation) = phase else { return }
            installation.historyError = error
            phase = .installing(installation)
        }

        private func advance(_ input: Input) {
            guard case .running(var session) = phase else { return }
            let state = session.machine.advance(input)
            phase = .running(session)
            returnToDeadlineScope(state)
        }

        private func returnToDeadlineScope(_ state: State) {
            guard case .running(let session) = phase else { return }
            if let expiration = session.deadlines.expiration {
                if case .complete(let completion) = state {
                    resolve(.success(completion))
                    return
                }
                if case .pending(.perform(let requests)) = state,
                   requests.allSatisfy(\.isTerminalEvidenceRequest) {
                    performNext(requests, afterDeadline: true)
                    return
                }
                guard case .idle = session.interaction else { return }
                collectTerminalEvidence(expiration)
                return
            }
            interpret(state)
        }

        private func interpret(_ state: State) {
            guard case .running(var session) = phase else { return }
            switch state {
            case .complete(let completion):
                resolve(.success(completion))

            case .pending(.wait):
                phase = .running(session)
                armDeadline()

            case .pending(.perform(let requests)):
                switch session.interaction {
                case .idle:
                    phase = .running(session)
                    armDeadline()
                    performNext(requests)
                case .running(let token, let task, _):
                    session.interaction = .running(
                        token,
                        task: task,
                        deferred: requests
                    )
                    phase = .running(session)
                    armDeadline()
                }
            }
        }

        private func performNext(
            _ requests: [MainActorRequest],
            afterDeadline: Bool = false
        ) {
            guard let request = requests.first,
                  case .running(var session) = phase,
                  afterDeadline || session.deadlines.expiration == nil else {
                return
            }
            let remaining = Array(requests.dropFirst())
            let token = RequestToken(request)
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.perform(request, token: token)
                self.interactionFinished(token)
            }
            session.interaction = .running(
                token,
                task: task,
                deferred: remaining
            )
            phase = .running(session)
        }

        private func perform(
            _ request: MainActorRequest,
            token: RequestToken
        ) async {
            switch request {
            case .currentSnapshot(let id, let scope):
                let snapshot = await brains.captureHeistCurrentState(scope: scope)?
                    .snapshot
                complete(token, input: .currentSnapshot(id, snapshot))

            case .beginObservation(let id, let request):
                await beginObservation(id: id, request: request, token: token)

            case .dispatch(let id, let command):
                let result = await brains.dispatchRuntimeAction(command)
                complete(token, input: .dispatchCompleted(id, result))

            case .explore(let id, let predicate):
                let deadline = activeLeafDeadline(id: id)
                let outcome: Navigation.ViewportExit.Outcome
                if let deadline {
                    outcome = await brains.navigation.exploreForWait(
                        target: predicate.resolved.singularTarget,
                        deadline: deadline,
                        stopWhen: { [weak self] in
                            self?.shouldStopExploration(token) == true
                        }
                    )
                } else {
                    outcome = .failed(.originUnavailable)
                }
                guard case .running(var session) = phase,
                      var observation = session.activeObservation,
                      observation.id == id else {
                    return
                }
                observation.viewportStatus.record(outcome)
                session.activeObservation = observation
                phase = .running(session)
                complete(token, input: .viewportExited(id, outcome))

            case .finishObservation(let id, let exitPosition):
                await finishObservation(
                    id: id,
                    exitPosition: exitPosition,
                    token: token
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
                    token,
                    input: .failureScreenshotCaptured(id, result)
                )
            }
        }

        private func beginObservation(
            id: RequestID,
            request: ObservationRequest,
            token: RequestToken
        ) async {
            guard case .running(var initialSession) = phase,
                  case .running(let current, _, _) = initialSession.interaction,
                  current == token else {
                return
            }
            precondition(
                initialSession.activeObservation == nil,
                "Only one leaf may observe at a time"
            )
            precondition(
                initialSession.bufferedObservationEvents == nil,
                "Only one observation boundary may be established at a time"
            )
            initialSession.bufferedObservationEvents = []
            phase = .running(initialSession)

            let stream = brains.vault.semanticObservationStream
            let scope = stream.subscribe(scope: request.scope)
            let notificationWindow = brains.vault.accessibilityNotifications
                .beginActionWindow()
            let leafDeadline = SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeout: request.timeout
            )
            guard case .running(let armedSession) = phase,
                  case .running(let current, _, _) = armedSession.interaction,
                  current == token else {
                scope.cancel()
                notificationWindow.cancel()
                return
            }
            phase = .running(armedSession)

            let boundary = await stream.stateOwner.observationBoundary(
                scope: request.scope
            )
            guard case .running(var session) = phase,
                  case .running(let current, _, _) = session.interaction,
                  current == token else {
                scope.cancel()
                notificationWindow.cancel()
                return
            }
            session.activeObservation = ActiveObservation(
                id: id,
                request: request,
                boundary: boundary,
                scopeSubscription: scope,
                notificationWindow: notificationWindow,
                viewportStatus: .available
            )
            session.deadlines.cancelTimer()
            session.deadlines = .unscheduled(.leaf(
                whole: session.deadlines.targets.whole,
                leaf: leafDeadline
            ))
            phase = .running(session)
            armDeadline()

            let viewportOutcome: Navigation.ViewportExit.Outcome?
            switch request.scope {
            case .visible:
                viewportOutcome = await brains.captureHeistCurrentState(
                    scope: .visible
                ) == nil ? nil : .retained
            case .discovery:
                viewportOutcome = await brains.navigation.fullGraph(
                    deadline: activeLeafDeadline(id: id)
                )?.viewportExit
            }

            guard case .running(var capturedSession) = phase,
                  case .running(let capturedToken, _, _) = capturedSession.interaction,
                  capturedToken == token,
                  var observation = capturedSession.activeObservation,
                  observation.id == id,
                  let bufferedEvents = capturedSession.bufferedObservationEvents else {
                scope.cancel()
                notificationWindow.cancel()
                return
            }
            observation.viewportStatus.record(viewportOutcome)
            capturedSession.activeObservation = observation
            capturedSession.bufferedObservationEvents = nil
            phase = .running(capturedSession)
            complete(token, input: .observationBegan(id, boundary))
            for event in bufferedEvents {
                receive(event)
            }
        }

        private func finishObservation(
            id: RequestID,
            exitPosition: Navigation.ViewportExitPosition,
            token: RequestToken
        ) async {
            guard case .running(let initialSession) = phase,
                  let observation = initialSession.activeObservation,
                  observation.id == id else {
                return
            }

            var viewportStatus = observation.viewportStatus
            switch exitPosition {
            case .current:
                break
            case .origin:
                let exploration = await brains.navigation.fullGraph(
                    deadline: activeLeafDeadline(id: id)
                )
                viewportStatus.record(exploration?.viewportExit)
            }
            if await captureVisibleObservation(
                window: observation.notificationWindow
            ) == nil {
                viewportStatus.record(nil)
            }
            let evidence = await evidence(for: observation)
            guard case .running(let session) = phase,
                  session.activeObservation?.id == id,
                  session.machine.activeLeaf?.isFinishingObservation == true else {
                return
            }
            let outcome: LeafOutcome
            if Task.isCancelled {
                outcome = .cancelled
            } else {
                outcome = observationOutcome(
                    viewportStatus: viewportStatus,
                    expiration: session.deadlines.expiration
                )
                if outcome == .heistTimedOut,
                   let expiration = session.deadlines.expiration {
                    markTerminalCollection(expiration)
                }
            }
            releaseActiveObservation(
                preservingDeadline: outcome == .heistTimedOut
            )
            complete(
                token,
                input: .observationFinished(id, evidence, outcome)
            )
        }

        private func complete(_ token: RequestToken, input: Input) {
            guard case .running(var session) = phase,
                  case .running(let current, _, let deferred) = session.interaction,
                  current == token else {
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
                  !deferred.isEmpty else {
                return
            }
            performNext(deferred)
        }

        private func shouldStopExploration(_ token: RequestToken) -> Bool {
            guard case .running(let session) = phase,
                  case .running(let current, _, let deferred) = session.interaction,
                  current == token else {
                return true
            }
            return !deferred.isEmpty || session.deadlines.expiration != nil
        }

        private func interactionFinished(_ token: RequestToken) {
            guard case .running(var session) = phase,
                  case .running(let current, _, _) = session.interaction,
                  current == token else {
                return
            }
            session.interaction = .idle
            let expiration = session.deadlines.expiration
            phase = .running(session)
            if let expiration {
                collectTerminalEvidence(expiration)
            }
        }

        private func activeLeafDeadline(
            id: RequestID
        ) -> SemanticObservationDeadline? {
            guard case .running(let session) = phase,
                  session.activeObservation?.id == id,
                  case .leaf(_, let leaf) = session.deadlines.targets else {
                return nil
            }
            return leaf
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
            case .running(let token, let task, _):
                phase = .running(session)
                if !token.kind.completesAfterDeadline {
                    task.cancel()
                }
            }
        }

        private func collectTerminalEvidence(_ expiration: DeadlineExpiration) {
            guard case .running(var session) = phase,
                  case .idle = session.interaction else {
                return
            }
            guard let observation = session.activeObservation else {
                let state = session.machine.finishAfterHeistTimeout()
                phase = .running(session)
                returnToDeadlineScope(state)
                return
            }

            session.deadlines = .collectingTerminalEvidence(
                session.deadlines.targets,
                expiration
            )
            let token = RequestToken(id: observation.id, kind: .terminalEvidence)
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                var viewportStatus = observation.viewportStatus
                let exploration = await self.brains.navigation.fullGraph()
                viewportStatus.record(exploration?.viewportExit)
                if await self.captureVisibleObservation(
                    window: observation.notificationWindow
                ) == nil {
                    viewportStatus.record(nil)
                }
                let evidence = await self.evidence(for: observation)
                self.finishTerminalEvidence(
                    token: token,
                    evidence: evidence,
                    viewportStatus: viewportStatus,
                    expiration: expiration
                )
                self.interactionFinished(token)
            }
            session.interaction = .running(token, task: task, deferred: [])
            phase = .running(session)
        }

        private func finishTerminalEvidence(
            token: RequestToken,
            evidence: Observation.Evidence,
            viewportStatus: ViewportStatus,
            expiration: DeadlineExpiration
        ) {
            guard case .running(var session) = phase,
                  case .running(let current, _, _) = session.interaction,
                  current == token,
                  let observation = session.activeObservation,
                  observation.id == token.id else {
                return
            }
            session.interaction = .idle
            release(observation)
            session.activeObservation = nil
            if !expiration.includesWhole {
                session.deadlines = .unscheduled(.whole(
                    session.deadlines.targets.whole
                ))
            }
            let finalObservationSatisfied = session.machine.activeLeaf.map {
                $0.id == observation.id && $0.expectationIsSatisfied
            } ?? false
            let outcome: LeafOutcome
            if case .available = viewportStatus,
               finalObservationSatisfied {
                outcome = .completed
            } else {
                outcome = observationOutcome(
                    viewportStatus: viewportStatus,
                    expiration: expiration
                )
            }
            let state = session.machine.advance(.observationFinished(
                observation.id,
                evidence,
                outcome
            ))

            if expiration.includesWhole {
                let terminalState: State
                if case .complete = state {
                    terminalState = state
                } else if case .pending(.perform(let requests)) = state,
                          requests.allSatisfy(\.isTerminalEvidenceRequest) {
                    terminalState = state
                } else {
                    terminalState = session.machine.finishAfterHeistTimeout()
                }
                phase = .running(session)
                returnToDeadlineScope(terminalState)
            } else {
                phase = .running(session)
                interpret(state)
            }
        }

        private func observationOutcome(
            viewportStatus: ViewportStatus,
            expiration: DeadlineExpiration?
        ) -> LeafOutcome {
            switch (viewportStatus, expiration) {
            case (.failed(let failure), _):
                .viewportExitFailed(failure)
            case (.unavailable, _):
                .unavailable
            case (.available, .some(let expiration)):
                expiration.includesWhole ? .heistTimedOut : .timedOut
            case (.available, nil):
                .completed
            }
        }

        private func markTerminalCollection(_ expiration: DeadlineExpiration) {
            guard case .running(var session) = phase else { return }
            session.deadlines = .collectingTerminalEvidence(
                session.deadlines.targets,
                expiration
            )
            phase = .running(session)
        }

        private func releaseActiveObservation(
            preservingDeadline: Bool = false
        ) {
            guard case .running(var session) = phase,
                  let observation = session.activeObservation else {
                return
            }
            release(observation)
            session.activeObservation = nil
            if !preservingDeadline {
                session.deadlines.cancelTimer()
                session.deadlines = .unscheduled(.whole(
                    session.deadlines.targets.whole
                ))
            }
            phase = .running(session)
            if !preservingDeadline {
                armDeadline()
            }
        }

        private func release(_ observation: ActiveObservation) {
            observation.scopeSubscription.cancel()
            observation.notificationWindow.consume()
        }

        private func evidence(
            for observation: ActiveObservation
        ) async -> Observation.Evidence {
            await brains.vault.semanticObservationStream.stateOwner
                .evidence(after: observation.boundary)
        }

        private func captureVisibleObservation(
            window: AccessibilityNotificationScopeLease
        ) async -> TheVault.State.Current? {
            guard let observation = brains.vault.captureVisibleObservation() else {
                return nil
            }
            brains.vault.observeInterface(observation)
            let admitted = CommittableInterfaceObservation.admitCaptured(
                observation,
                tripwireSignal: brains.vault.semanticObservationStream
                    .currentTripwireSignal(),
                lineage: .resting
            )
            return await brains.vault.semanticObservationStream
                .commitVisibleObservation(
                    admitted,
                    notificationBatch: window.capture()
                )
                .current
        }

        private func failureScreenshot(
            failedPath: HeistExecutionPath,
            mode: ScreenCaptureMode
        ) async -> HeistExecutionStepResult? {
            let result: ActionResult
            switch await brains.captureScreenPayload(mode: mode) {
            case .success(let payload):
                result = .success(
                    payload: .screenshot(payload),
                    message: "Captured screenshot "
                        + "\(Int(payload.width))x\(Int(payload.height))"
                )
            case .failure(let failure):
                result = .failure(
                    payload: .screenshot(nil),
                    failureKind: failure.actionFailureKind,
                    message: failure.message
                )
            }

            let command = HeistActionCommand.takeScreenshot
            let evidence = HeistActionEvidence.completed(
                result: result,
                expectation: nil
            )
            let execution: HeistActionExecution
            switch result.outcome {
            case .success:
                execution = .passed(
                    command: command,
                    evidence: .init(admitted: evidence)
                )
            case .failure:
                execution = .failed(
                    command: command,
                    evidence: .init(admitted: evidence),
                    failure: HeistFailureDetail(
                        category: .action,
                        contract: "failure screenshot action captures visible screen",
                        observed: result.message ?? "screenshot action failed",
                        expected: HeistActionCommandType.takeScreenshot.rawValue
                    )
                )
            }
            return .action(
                path: failedPath.failureAction(at: 0),
                execution: execution
            )
        }

        private func cancel() {
            guard case .running = phase else { return }
            resolve(.failure(CancellationError()))
        }

        private func resolve(_ resolution: Result<Completion, any Error>) {
            guard case .running(let session) = phase else { return }
            phase = .cleaning
            session.deadlines.cancelTimer()
            session.eventSubscription.cancel()
            session.observationDemand.cancel()
            switch session.interaction {
            case .idle:
                break
            case .running(_, let task, _):
                task.cancel()
            }
            switch resolution {
            case .success:
                if let observation = session.activeObservation {
                    release(observation)
                }
                session.notificationScope.consume()
            case .failure:
                if let observation = session.activeObservation {
                    observation.scopeSubscription.cancel()
                    observation.notificationWindow.cancel()
                }
                session.notificationScope.cancel()
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .running(_, let task, _) = session.interaction {
                    _ = await task.value
                }
                await self.brains.vault.semanticObservationStream.stateOwner
                    .releaseHistory(from: session.protectedHistoryIndex)
                self.phase = .finished
                switch resolution {
                case .success(let completion):
                    session.continuation.resume(returning: completion)
                case .failure(let error):
                    session.continuation.resume(throwing: error)
                }
            }
        }

        private func clean(_ installation: Installation) async {
            phase = .cleaning
            installation.observationDemand.cancel()
            installation.notificationScope.cancel()
            await brains.vault.semanticObservationStream.stateOwner
                .releaseHistory(from: installation.protectedHistoryIndex)
            phase = .finished
        }
    }
}

private extension HeistExecution.MainActorRequest {
    var isTerminalEvidenceRequest: Bool {
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
                        .refreshVisibleObservation() else {
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
