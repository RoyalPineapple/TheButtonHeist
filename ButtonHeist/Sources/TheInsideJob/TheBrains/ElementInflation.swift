#if canImport(UIKit) && DEBUG
import UIKit

import ButtonHeistSupport
import TheScore
import ThePlans

@MainActor
internal final class ElementInflation {

    private struct PortableSemanticTarget {
        let target: ResolvedAccessibilityTarget
        let removedTerminalOrdinal: Bool
    }

    internal struct AdmittedSemanticTarget: Sendable {
        internal let target: ResolvedAccessibilityTarget
        internal let scrollContainerPath: TreePath?

        private init(
            target: ResolvedAccessibilityTarget,
            scrollContainerPath: TreePath?
        ) {
            self.target = target
            self.scrollContainerPath = scrollContainerPath
        }

        internal static func admit(
            _ sourceTarget: ResolvedAccessibilityTarget,
            selectedElement: InterfaceTree.Element,
            resolve: (ResolvedAccessibilityTarget) -> TheVault.TargetResolution
        ) -> SemanticTargetAdmissionDecision {
            let portableTarget = portableTarget(from: sourceTarget)
            switch resolve(portableTarget.target) {
            case .resolved(.element(let match)) where match == selectedElement:
                return .admitted(AdmittedSemanticTarget(
                    target: portableTarget.target,
                    scrollContainerPath: selectedElement.scrollMembership?.containerPath
                ))
            case .resolved(.element):
                return .rejected(.selectedElementMismatch)
            case .resolved(.container):
                return .rejected(.containerTarget)
            case .notFound(let facts):
                return .rejected(.notFound(facts))
            case .ambiguous(let facts):
                return .rejected(portableTarget.removedTerminalOrdinal
                    ? .ordinalDependent(facts)
                    : .ambiguous(facts))
            }
        }

        private static func portableTarget(
            from sourceTarget: ResolvedAccessibilityTarget
        ) -> PortableSemanticTarget {
            switch sourceTarget {
            case .predicate(let predicate, let ordinal):
                return PortableSemanticTarget(
                    target: .predicate(predicate, ordinal: nil),
                    removedTerminalOrdinal: ordinal != nil
                )
            case .container(let predicate, let ordinal):
                return PortableSemanticTarget(
                    target: .container(predicate, ordinal: nil),
                    removedTerminalOrdinal: ordinal != nil
                )
            case .within(let container, let nestedTarget):
                let nestedPortableTarget = portableTarget(from: nestedTarget)
                return PortableSemanticTarget(
                    target: .within(container: container, target: nestedPortableTarget.target),
                    removedTerminalOrdinal: nestedPortableTarget.removedTerminalOrdinal
                )
            }
        }
    }

    internal enum SemanticTargetAdmissionDecision {
        case admitted(AdmittedSemanticTarget)
        case rejected(SemanticTargetAdmissionRejection)
    }

    internal enum SemanticTargetAdmissionRejection: Equatable {
        case ordinalDependent(TheVault.TargetAmbiguityFacts)
        case notFound(TheVault.TargetNotFoundFacts)
        case ambiguous(TheVault.TargetAmbiguityFacts)
        case selectedElementMismatch
        case containerTarget
    }

    internal struct SemanticTargetRevealRequest {
        internal let target: AdmittedSemanticTarget
        internal let revealRootScrollViewID: ObjectIdentifier
        internal let deadline: SemanticObservationDeadline
        internal let observedScrollContentActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint?

        internal init(
            target: AdmittedSemanticTarget,
            revealRootScrollViewID: ObjectIdentifier,
            deadline: SemanticObservationDeadline,
            observedScrollContentActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint? = nil
        ) {
            self.target = target
            self.revealRootScrollViewID = revealRootScrollViewID
            self.deadline = deadline
            self.observedScrollContentActivationPoint = observedScrollContentActivationPoint
        }
    }

    internal typealias MoveViewport = @MainActor (
        Navigation.ViewportMovementIntent,
    ) async -> Navigation.ViewportTransition

    internal struct Exploration {
        internal var settleForDiscovery: @MainActor () async -> Void
        internal var discoverTarget: @MainActor (
            ResolvedAccessibilityTarget,
        ) async -> Navigation.InterfaceExplorationResult?
        internal var revealKnownTarget: @MainActor (
            SemanticTargetRevealRequest,
        ) async -> SemanticTargetScanResult?
        internal var moveViewport: MoveViewport
    }

    internal struct GeometryEnvironment {
        internal let now: @MainActor () -> RuntimeElapsed.Instant
        internal let awaitFrame: @MainActor (
            Duration
        ) async -> TheTripwire.HeartbeatWaitOutcome
    }

    internal struct CommittedElementTarget {
        private let identity: CrossCaptureTarget
        private let resolvedHeistId: HeistId
        private let resolution: ActionSubjectResolution

        internal init(_ inflatedTarget: InflatedElementTarget) {
            identity = inflatedTarget.identity
            resolvedHeistId = inflatedTarget.treeElement.heistId
            resolution = inflatedTarget.resolution
        }

        internal var target: ResolvedAccessibilityTarget { identity.sourceTarget }
        internal var crossCaptureTarget: CrossCaptureTarget { identity }
        internal var heistId: HeistId { resolvedHeistId }
        internal var subjectResolution: ActionSubjectResolution { resolution }
    }

    internal let vault: TheVault
    internal let safecracker: TheSafecracker
    internal let tripwire: TheTripwire
    internal var exploration: Exploration
    internal var geometryEnvironment: GeometryEnvironment

    internal static let comfortMarginFraction: CGFloat = 1.0 / 6.0
    internal init(
        vault: TheVault,
        safecracker: TheSafecracker,
        tripwire: TheTripwire,
        exploration: Exploration
    ) {
        self.vault = vault
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.exploration = exploration
        geometryEnvironment = GeometryEnvironment(
            now: { RuntimeElapsed.now },
            awaitFrame: { timeout in
                await tripwire.waitForNextHeartbeat(timeout: timeout, demand: .immediate)
            }
        )
    }

    internal func inflate(
        for target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy = .requireOnscreen,
        operationDeadline: SemanticObservationDeadline? = nil
    ) async -> ElementInflationResult {
        guard !Task.isCancelled else {
            return .failed(.cancelled("element inflation was cancelled before resolution"))
        }
        let validatedTarget: ResolvedAccessibilityTarget
        do {
            validatedTarget = try target.validatedForElementAction()
        } catch {
            return .failed(.targetResolution(error))
        }
        return await runInflation(
            for: validatedTarget,
            method: method,
            activationPointPolicy: activationPointPolicy,
            operationDeadline: operationDeadline
        )
    }

    private func runInflation(
        for target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy,
        operationDeadline: SemanticObservationDeadline? = nil,
        initialState: State = .resolving
    ) async -> ElementInflationResult {
        var state = initialState
        let revealTransaction = RevealTransaction(vault: vault)
        revealTransaction.captureScrollableHierarchy()

        while true {
            switch state {
            case .resolving:
                let nextState: State
                switch await findTargetInTree(target) {
                case .success(.visible(let treeElement, let resolution)):
                    nextState = .refreshing(
                        target: .captureLocal(target),
                        treeElement: treeElement,
                        deadline: operationDeadline ?? handoffDeadline(for: treeElement),
                        resolution: resolution
                    )
                case .success(.known(let treeElement, let resolution)):
                    nextState = .revealing(
                        target: .captureLocal(target),
                        treeElement: treeElement,
                        deadline: operationDeadline ?? handoffDeadline(for: treeElement),
                        resolution: resolution
                    )
                case .failure(let failure):
                    nextState = .failed(failure)
                }
                state = transition(from: state, to: nextState)

            case .revealing(let target, let treeElement, let deadline, let resolution):
                let nextState = await stateAfterReveal(
                    treeElement,
                    identity: target,
                    deadline: deadline,
                    resolution: resolution,
                    transaction: revealTransaction
                )
                state = transition(from: state, to: nextState)

            case .refreshing(let target, let treeElement, let deadline, let resolution):
                let nextState = await stateAfterRefresh(
                    identity: target,
                    treeElement: treeElement,
                    resolution: resolution,
                    method: method,
                    activationPointPolicy: activationPointPolicy,
                    deadline: deadline
                )
                state = transition(from: state, to: nextState)

            case .placing(let inflatedTarget):
                let nextState = await stateAfterPlacement(
                    inflatedTarget,
                    method: method,
                    transaction: revealTransaction
                )
                state = transition(from: state, to: nextState)

            case .inflated(let result):
                revealTransaction.commit()
                return .inflated(result)

            case .failed(let failure):
                await revealTransaction.rollBack(using: exploration.moveViewport)
                return .failed(failure)
            }
        }
    }

    internal func refreshCommittedTarget(
        _ target: CommittedElementTarget,
        method: ActionMethod,
    ) async -> ElementInflationResult {
        guard !Task.isCancelled else {
            return .failed(.cancelled("element inflation was cancelled before committed target refresh"))
        }
        let treeElement: InterfaceTree.Element
        switch target.crossCaptureTarget {
        case .captureLocal:
            guard let current = vault.interfaceElement(heistId: target.heistId) else {
                return .failed(.staleRefresh(
                    "committed target \(target.heistId) disappeared before \(method.rawValue) refresh",
                    failureKind: .targetUnavailable
                ))
            }
            treeElement = current
        case .admitted(_, let semanticTarget):
            switch resolveAdmittedSemanticTarget(
                semanticTarget,
                in: vault.latestObservation.tree
            ) {
            case .success(let current):
                treeElement = current
            case .failure(let failure):
                return .failed(failure.inflationFailure)
            }
        }
        let deadline = handoffDeadline(for: treeElement)
        let initialState: State = vault.liveContains(heistId: treeElement.heistId)
            ? .refreshing(
                target: target.crossCaptureTarget,
                treeElement: treeElement,
                deadline: deadline,
                resolution: target.subjectResolution
            )
            : .revealing(
                target: target.crossCaptureTarget,
                treeElement: treeElement,
                deadline: deadline,
                resolution: target.subjectResolution
            )
        return await runInflation(
            for: target.target,
            method: method,
            activationPointPolicy: .requireOnscreen,
            initialState: initialState
        )
    }

    internal static func handoffTickCount(
        for treeElement: InterfaceTree.Element,
        in tree: InterfaceTree
    ) -> Int {
        var visited = Set<TreePath>()
        var containerPath = treeElement.scrollMembership?.containerPath
        while let path = containerPath, visited.insert(path).inserted {
            containerPath = tree.containers[path]?.scrollMembership?.containerPath
        }
        return max(2, visited.count + 1)
    }

    internal func handoffDeadline(
        for treeElement: InterfaceTree.Element
    ) -> SemanticObservationDeadline {
        let tickCount = Self.handoffTickCount(for: treeElement, in: vault.interfaceTree)
        return SemanticObservationDeadline(
            start: geometryEnvironment.now(),
            timeoutSeconds: Double(tickCount) * SemanticObservationTiming.defaultTimeout
        )
    }

    private func transition(
        from state: State,
        to proposedState: State
    ) -> State {
        let nextState: State
        if proposedState.isCancellationFailure {
            nextState = proposedState
        } else if Task.isCancelled {
            nextState = .failed(.cancelled(
                "element inflation was cancelled while \(state)"
            ))
        } else {
            nextState = proposedState
        }
        return nextState
    }
}

extension ElementInflation.InflatedElementTarget {
    internal var committedTarget: ElementInflation.CommittedElementTarget {
        ElementInflation.CommittedElementTarget(self)
    }
}

#endif // canImport(UIKit) && DEBUG
