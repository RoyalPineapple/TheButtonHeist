#if canImport(UIKit) && DEBUG
import AccessibilitySnapshotModel
import ThePlans
import UIKit

extension ElementInflation {

    enum SemanticRevealFailure: Equatable, Sendable {
        case missingScrollMembership
        case noLiveScrollableAncestor
        case scanDidNotRevealTarget
    }

    enum SemanticTargetResolutionFailure: Error, Equatable, Sendable {
        case notFound(String)
        case ambiguous(String)
        case containerTarget
        case selectedElementMismatch

        var inflationFailure: ElementInflationFailure {
            switch self {
            case .notFound(let message):
                return .notFound(message)
            case .selectedElementMismatch:
                return .notFound("the selected target no longer matches its admitted semantic identity")
            case .ambiguous(let message):
                return .ambiguous(message)
            case .containerTarget:
                return .targetResolution(.containerTarget)
            }
        }
    }

    enum SemanticTargetScanResult {
        case revealed(InterfaceTree.Element, Navigation.InterfaceExplorationResult)
        case failed(SemanticTargetResolutionFailure)
        case unavailable
    }

    enum SemanticRevealResult: Sendable {
        case alreadyVisible(InterfaceTree.Element)
        case revealed(InterfaceTree.Element)
        case targetResolutionFailed(SemanticTargetResolutionFailure)
        case failed(SemanticRevealFailure)
        case cancelled
        case timedOut

        var didReveal: Bool {
            if case .revealed = self { return true }
            return false
        }
    }

    private enum ScrollContainerRevealResult {
        case resolved(UIScrollView)
        case targetResolutionFailed(SemanticTargetResolutionFailure)
        case unavailable
    }

    private enum SemanticViewportMoveResult {
        case resolved(InterfaceTree.Element)
        case targetResolutionFailed(SemanticTargetResolutionFailure)
        case unavailable
    }

    @discardableResult
    func revealSemanticTarget(
        _ treeElement: InterfaceTree.Element,
        deadline: SemanticObservationDeadline,
    ) async -> SemanticRevealResult {
        guard let selectedElement = vault.interfaceElement(heistId: treeElement.heistId),
              let authoredTarget = vault.minimumUniqueTarget(for: selectedElement),
              let sourceTarget = try? authoredTarget.resolve(in: .empty)
        else {
            return .targetResolutionFailed(.notFound(
                "the selected target has no portable semantic identity"
            ))
        }
        switch admittedSemanticTarget(sourceTarget, selectedElement: selectedElement) {
        case .success(let admittedTarget):
            return await revealSemanticTarget(
                admittedTarget,
                deadline: deadline
            )
        case .failure(let failure):
            return .targetResolutionFailed(failure)
        }
    }

    @discardableResult
    func revealSemanticTarget(
        _ target: AdmittedSemanticTarget,
        deadline: SemanticObservationDeadline,
    ) async -> SemanticRevealResult {
        let transaction = RevealTransaction(vault: vault)
        transaction.captureScrollableHierarchy()
        let result = await revealSemanticTarget(
            target,
            deadline: deadline,
            transaction: transaction
        )
        switch result {
        case .alreadyVisible, .revealed:
            transaction.commit()
        case .targetResolutionFailed, .failed, .cancelled, .timedOut:
            await transaction.rollBack(
                using: exploration.moveViewport,
                deadline: deadline
            )
        }
        return result
    }

    func revealSemanticTarget(
        _ target: AdmittedSemanticTarget,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> SemanticRevealResult {
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        let currentElement: InterfaceTree.Element
        switch resolveAdmittedSemanticTarget(target) {
        case .success(let resolved):
            currentElement = resolved
        case .failure(let failure):
            return .targetResolutionFailed(failure)
        }
        if vault.visibleLiveElementAliasing(currentElement) != nil {
            return .alreadyVisible(currentElement)
        }
        guard let rememberedScrollContainerPath = target.scrollContainerPath else {
            return .failed(.missingScrollMembership)
        }
        let revealRootScrollViewID = vault.liveScrollViewIDForRevealing(heistId: currentElement.heistId)
        switch await revealScrollAncestors(
            for: target,
            deadline: deadline,
            transaction: transaction
        ) {
        case .resolved(let scrollView):
            if currentElement.geometry.view.activationPoint != nil {
                switch await moveToObservedContentPoint(
                    currentElement.geometry.view,
                    rememberedOwnerPath: rememberedScrollContainerPath,
                    in: scrollView,
                    target: target,
                    deadline: deadline,
                    transaction: transaction
                ) {
                case .resolved(let resolved):
                    if vault.visibleLiveElementAliasing(resolved) != nil {
                        return .revealed(resolved)
                    }
                case .targetResolutionFailed(let failure):
                    return .targetResolutionFailed(failure)
                case .unavailable:
                    break
                }
            }
        case .targetResolutionFailed(let failure):
            return .targetResolutionFailed(failure)
        case .unavailable:
            break
        }
        if let interruption = semanticRevealInterruption(deadline: deadline) {
            return interruption
        }
        transaction.captureScrollableHierarchy()
        guard let revealRootScrollViewID else {
            return .failed(.noLiveScrollableAncestor)
        }
        guard let scan = await exploration.revealKnownTarget(.init(
            target: target,
            revealRootScrollViewID: revealRootScrollViewID,
            deadline: deadline
        )) else {
            return semanticRevealInterruption(deadline: deadline)
                ?? .failed(.noLiveScrollableAncestor)
        }
        switch scan {
        case .revealed(let resolved, _):
            return .revealed(resolved)
        case .failed(let failure):
            return .targetResolutionFailed(failure)
        case .unavailable:
            return semanticRevealInterruption(deadline: deadline)
                ?? .failed(.scanDidNotRevealTarget)
        }
    }

    func admittedSemanticTarget(
        _ sourceTarget: ResolvedAccessibilityTarget,
        selectedElement: InterfaceTree.Element
    ) -> Result<AdmittedSemanticTarget, SemanticTargetResolutionFailure> {
        switch admitSemanticTarget(sourceTarget, selectedElement: selectedElement) {
        case .admitted(let target):
            return .success(target)
        case .rejected(.ordinalDependent(let facts)), .rejected(.ambiguous(let facts)):
            return .failure(.ambiguous(
                TargetResolutionDiagnostics.message(for: .ambiguous(facts))
            ))
        case .rejected(.notFound(let facts)):
            return .failure(.notFound(
                TargetResolutionDiagnostics.message(for: .notFound(facts))
            ))
        case .rejected(.selectedElementMismatch):
            return .failure(.selectedElementMismatch)
        case .rejected(.containerTarget):
            return .failure(.containerTarget)
        }
    }

    func resolveAdmittedSemanticTarget(
        _ target: AdmittedSemanticTarget
    ) -> Result<InterfaceTree.Element, SemanticTargetResolutionFailure> {
        semanticTargetResolution(vault.resolveTarget(target.target))
    }

    private func semanticTargetResolution(
        _ resolution: TheVault.TargetResolution
    ) -> Result<InterfaceTree.Element, SemanticTargetResolutionFailure> {
        switch resolution {
        case .resolved(.element(let element)):
            return .success(element)
        case .resolved(.container):
            return .failure(.containerTarget)
        case .notFound(let facts):
            return .failure(.notFound(
                TargetResolutionDiagnostics.message(for: .notFound(facts))
            ))
        case .ambiguous(let facts):
            return .failure(.ambiguous(
                TargetResolutionDiagnostics.message(for: .ambiguous(facts))
            ))
        }
    }

    private func revealScrollAncestors(
        for target: AdmittedSemanticTarget,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> ScrollContainerRevealResult {
        guard let path = target.scrollContainerPath else { return .unavailable }
        return await revealScrollContainer(
            at: path,
            target: target,
            visited: [],
            deadline: deadline,
            transaction: transaction
        )
    }

    private func revealScrollContainer(
        at path: TreePath,
        target: AdmittedSemanticTarget,
        visited: Set<TreePath>,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> ScrollContainerRevealResult {
        guard semanticRevealInterruption(deadline: deadline) == nil else { return .unavailable }
        var visited = visited
        guard visited.insert(path).inserted,
              let container = vault.interfaceTree.containers[path]
        else { return .unavailable }
        guard let membership = container.scrollMembership else {
            return vault.liveScrollView(reacquiring: container).map(ScrollContainerRevealResult.resolved)
                ?? .unavailable
        }
        let parent: UIScrollView
        switch await revealScrollContainer(
            at: membership.containerPath,
            target: target,
            visited: visited,
            deadline: deadline,
            transaction: transaction
        ) {
        case .resolved(let resolved):
            parent = resolved
        case .targetResolutionFailed(let failure):
            return .targetResolutionFailed(failure)
        case .unavailable:
            return .unavailable
        }
        guard container.viewSpace.activationPoint != nil else {
            return .unavailable
        }
        switch await moveToObservedContentPoint(
            container.viewSpace,
            rememberedOwnerPath: membership.containerPath,
            in: parent,
            target: target,
            deadline: deadline,
            transaction: transaction
        ) {
        case .resolved:
            break
        case .targetResolutionFailed(let failure):
            return .targetResolutionFailed(failure)
        case .unavailable:
            return .unavailable
        }

        transaction.captureScrollableHierarchy()
        return vault.liveScrollView(reacquiring: container, directChildOf: parent)
            .map(ScrollContainerRevealResult.resolved) ?? .unavailable
    }

    private func moveToObservedContentPoint(
        _ viewSpace: HeistElement.Geometry.ViewSpace,
        rememberedOwnerPath: TreePath,
        in scrollView: UIScrollView,
        target: AdmittedSemanticTarget,
        deadline: SemanticObservationDeadline,
        transaction: RevealTransaction
    ) async -> SemanticViewportMoveResult {
        guard semanticRevealInterruption(deadline: deadline) == nil else { return .unavailable }
        guard let scrollTarget = Navigation.ScrollableTarget.programmatic(scrollView, in: vault) else {
            return .unavailable
        }
        // Parent-space geometry survives viewport movement, but its path does not.
        // The caller reacquires the same semantic owner in the current viewport.
        // This proof binds the point to the remembered owner.
        guard let point = viewSpace.activationPoint(ownedBy: rememberedOwnerPath) else {
            return .unavailable
        }
        transaction.record(scrollView)
        let transition = await exploration.moveViewport(
            .revealViewPoint(point, in: scrollTarget),
            deadline
        )
        guard semanticRevealInterruption(deadline: deadline) == nil else { return .unavailable }
        switch transition.outcome {
        case .unavailable:
            return .unavailable
        case .unchanged:
            break
        case .moved:
            guard let current = transition.current,
                  !current.continuity.isReplacement else { return .unavailable }
        }
        switch resolveAdmittedSemanticTarget(target) {
        case .success(let element):
            return .resolved(element)
        case .failure(let failure):
            return .targetResolutionFailed(failure)
        }
    }

    private func semanticRevealInterruption(
        deadline: SemanticObservationDeadline
    ) -> SemanticRevealResult? {
        if Task.isCancelled { return .cancelled }
        return deadline.hasTimeRemaining(at: RuntimeElapsed.now) ? nil : .timedOut
    }
}

#endif // canImport(UIKit) && DEBUG
