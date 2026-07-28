#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension HeistExecution {
    private final class ExplorationStop {
        var isRequested = false
    }

    @MainActor
    internal final class Host {
        private unowned let brains: TheBrains
        private var machine: Machine?
        private var state: State?
        private var nextOperationID: UInt64 = 0
        private var resultContinuation: CheckedContinuation<Result, Never>?
        private var eventSubscription: SemanticObservationSubscription?
        private var scopeSubscription: SemanticObservationSubscription?
        private var observationDemand: SemanticObservationDemand?
        private var notificationWindow: AccessibilityNotificationScopeLease?
        private var protectedHistoryIndex: Int?
        private var deadlineTask: Task<Void, Never>?
        private var explorationTask: Task<Navigation.ViewportExit.Outcome, Never>?
        private var explorationStop: ExplorationStop?

        internal init(brains: TheBrains) {
            self.brains = brains
        }

        internal func start() async {
            guard eventSubscription == nil else { return }
            let stream = brains.vault.semanticObservationStream
            let historyIndex = await stream.stateOwner.historyEndIndex()
            await stream.stateOwner.protectHistory(from: historyIndex)
            protectedHistoryIndex = historyIndex
            observationDemand = stream.beginActiveObservationDemand()
            eventSubscription = await stream.subscribe(
                scope: .visible,
                replayingAfter: historyIndex,
                receive: { [weak self] event in
                    self?.accept(.event(event))
                },
                historyUnavailable: { _ in
                    // A host protects history before subscribing. An unavailable
                    // initial replay contains no active operation evidence.
                }
            )
        }

        internal func finish() async {
            if resultContinuation != nil {
                failPending(.cancelled)
            }
            deadlineTask?.cancel()
            explorationStop?.isRequested = true
            _ = await explorationTask?.value
            eventSubscription?.cancel()
            scopeSubscription?.cancel()
            observationDemand?.cancel()
            notificationWindow?.cancel()
            eventSubscription = nil
            scopeSubscription = nil
            observationDemand = nil
            notificationWindow = nil
            if let protectedHistoryIndex {
                await brains.vault.semanticObservationStream.stateOwner
                    .releaseHistory(from: protectedHistoryIndex)
                self.protectedHistoryIndex = nil
            }
        }

        internal func execute(_ command: Command) async -> Result {
            precondition(
                resultContinuation == nil && machine == nil,
                "One heist host may execute only one active command"
            )
            if eventSubscription == nil {
                await start()
            }

            let startedAt = RuntimeElapsed.now
            let current = await brains.captureCurrentState(
                scope: command.observationScope
            )
            if case .currentState = command {
                return .currentState(current?.snapshot)
            }

            let stream = brains.vault.semanticObservationStream
            let historyStartIndex = await stream.stateOwner.historyEndIndex()
            nextOperationID += 1
            let id = OperationID(rawValue: nextOperationID)
            scopeSubscription = stream.subscribe(scope: command.observationScope)
            notificationWindow = brains.vault.accessibilityNotifications
                .beginActionWindow()

            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    resultContinuation = continuation
                    var machine = Machine(.init(
                        id: id,
                        command: command,
                        baseline: current?.snapshot,
                        historyStartIndex: historyStartIndex,
                        startedAt: startedAt
                    ))
                    let state = machine.start()
                    self.machine = machine
                    interpret(state)
                    scheduleDeadline(
                        id: id,
                        timeout: command.timeout
                    )
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.failPending(.cancelled)
                }
            }
        }

        private func accept(_ input: Input) {
            guard var machine else { return }
            let state = machine.advance(input)
            self.machine = machine
            interpret(state)
        }

        private func interpret(_ state: State) {
            self.state = state
            switch state {
            case .pending(.wait):
                return
            case .pending(.perform(let requests)):
                for request in requests {
                    perform(request)
                }
            case .complete(let completion):
                complete(completion)
            }
        }

        private func perform(_ request: MainActorRequest) {
            switch request {
            case .dispatch(let id, let command):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let result = await brains.dispatchRuntimeAction(command)
                    accept(.dispatchCompleted(id, result))
                }
            case .explore(let id, let predicate, let deadline):
                let stop = ExplorationStop()
                explorationStop = stop
                explorationTask = Task { @MainActor [weak self] in
                    guard let self else { return .restored }
                    return await brains.navigation.exploreForWait(
                        target: predicate.resolved.singularTarget,
                        deadline: deadline,
                        stopWhen: {
                            stop.isRequested || self.machine?.operationID != id
                        }
                    )
                }
            case .finishExploration(let id):
                deadlineTask?.cancel()
                explorationStop?.isRequested = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let outcome = await explorationTask?.value ?? .restored
                    _ = await captureVisibleObservation()
                    accept(.viewportExited(id, outcome))
                }
            }
        }

        private func scheduleDeadline(
            id: OperationID,
            timeout: Duration?
        ) {
            guard let timeout else { return }
            deadlineTask?.cancel()
            deadlineTask = Task { @MainActor [weak self] in
                guard let self,
                      await Task.cancellableSleep(for: timeout) else {
                    return
                }
                explorationStop?.isRequested = true
                _ = await explorationTask?.value
                if machine?.requiresFinalDiscovery == true {
                    _ = await brains.navigation.fullGraph()
                }
                _ = await captureVisibleObservation()
                guard machine?.operationID == id,
                      let state,
                      case .pending = state else {
                    return
                }
                failPending(.timedOut)
            }
        }

        private func failPending(_ outcome: Outcome) {
            guard let state,
                  case .pending = state,
                  let completion = machine?.externalCompletion(outcome) else {
                return
            }
            complete(completion)
        }

        private func complete(_ completion: Completion) {
            guard let continuation = resultContinuation else { return }
            resultContinuation = nil
            machine = nil
            state = nil
            deadlineTask?.cancel()
            deadlineTask = nil
            explorationStop?.isRequested = true
            scopeSubscription?.cancel()
            scopeSubscription = nil
            notificationWindow?.consume()
            notificationWindow = nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                let stream = brains.vault.semanticObservationStream
                let historyEndIndex = await stream.stateOwner.historyEndIndex()
                let evidence = await stream.stateOwner.evidence(
                    in: completion.historyStartIndex..<historyEndIndex,
                    baseline: completion.baseline
                )
                let observation = ObservationResult(
                    predicate: completion.command.predicate,
                    evidence: evidence,
                    outcome: completion.outcome,
                    outstandingDescription: completion.outstandingDescription,
                    elapsed: RuntimeElapsed.milliseconds(
                        since: completion.startedAt
                    )
                )
                let result: Result
                switch completion.command {
                case .currentState:
                    result = .currentState(completion.baseline)
                case .wait:
                    result = .wait(observation)
                case .action(let action):
                    result = .action(.init(
                        action: action,
                        dispatch: completion.dispatch,
                        observation: observation
                    ))
                }

                continuation.resume(returning: result)
            }
        }

        private func captureVisibleObservation() async -> TheVault.State.Current? {
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
                .commitSettledVisibleObservation(
                    admitted,
                    notificationBatch: notificationWindow?.capture(),
                    notificationIdentityObservation: observation
                )
                .current
        }
    }
}

@MainActor
extension TheBrains {
    internal func executeHeistOperation(
        _ command: HeistExecution.Command
    ) async -> HeistExecution.Result {
        let host = HeistExecution.Host(brains: self)
        await host.start()
        let result = await host.execute(command)
        await host.finish()
        return result
    }

    fileprivate func captureCurrentState(
        scope: SemanticObservationScope
    ) async -> TheVault.State.Current? {
        switch scope {
        case .visible:
            guard case .committed(let current) =
                    await vault.semanticObservationStream.refreshVisibleObservation()
            else { return nil }
            return current
        case .discovery:
            return await navigation.fullGraph()?.current
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
