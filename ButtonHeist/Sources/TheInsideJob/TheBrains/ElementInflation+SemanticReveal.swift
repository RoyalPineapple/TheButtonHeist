#if canImport(UIKit) && DEBUG
import UIKit

extension ElementInflation {

    static let maxNestedRevealDepth = 8

    enum SemanticRevealFailure: Equatable {
        case missingContentOrigin
        case noLiveScrollableAncestor
        case unsafeProgrammaticScroll
    }

    enum SemanticRevealResult {
        case alreadyVisible
        case revealed(UIScrollView)
        case failed(SemanticRevealFailure)

        var didReveal: Bool {
            if case .revealed = self { return true }
            return false
        }
    }

    /// Reveal a known target from the current graph. Known-only semantic
    /// elements carry no executable scroll authority unless the parser
    /// retained a live scroll ancestor.
    @discardableResult
    func revealSemanticTarget(_ screenElement: TheStash.ScreenElement) async -> SemanticRevealResult {
        if stash.visibleIds.contains(screenElement.heistId) {
            return .alreadyVisible
        }

        guard let location = screenElement.scrollContentLocation else {
            return .failed(.missingContentOrigin)
        }
        return await revealSemanticLocation(location, depth: 0)
    }

    private func revealSemanticContainer(
        _ container: SemanticScreen.Container,
        depth: Int
    ) async -> SemanticRevealResult {
        if let containerName = container.containerName,
           stash.capturedLiveScrollView(forContainerName: containerName) != nil {
            return .alreadyVisible
        }
        guard let location = container.scrollContentLocation else {
            return .failed(.noLiveScrollableAncestor)
        }
        return await revealSemanticLocation(location, depth: depth)
    }

    private func revealSemanticLocation(
        _ location: SemanticScreen.ScrollContentLocation,
        depth: Int
    ) async -> SemanticRevealResult {
        guard depth < Self.maxNestedRevealDepth else {
            return .failed(.noLiveScrollableAncestor)
        }

        if let scrollView = stash.capturedLiveScrollView(forContainerName: location.scrollContainer) {
            return await revealContentOrigin(location.origin, in: scrollView)
        }

        guard let scrollContainer = stash.uniqueSemanticContainer(named: location.scrollContainer) else {
            return .failed(.noLiveScrollableAncestor)
        }
        if scrollContainer.scrollContentLocation != nil {
            let containerReveal = await revealSemanticContainer(scrollContainer, depth: depth + 1)
            if case .failed = containerReveal {
                return containerReveal
            }
        }

        guard let scrollView = stash.liveScrollView(forContainerName: location.scrollContainer) else {
            return .failed(.noLiveScrollableAncestor)
        }
        return await revealContentOrigin(location.origin, in: scrollView)
    }

    private func revealContentOrigin(
        _ origin: CGPoint,
        in scrollView: UIScrollView
    ) async -> SemanticRevealResult {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else {
            return .failed(.unsafeProgrammaticScroll)
        }

        scrollView.setContentOffset(Self.semanticRevealTargetOffset(for: origin, in: scrollView), animated: false)
        await tripwire.yieldFrames(Self.postScrollLayoutFrames)
        stash.refreshTreeAfterViewportMove()
        return .revealed(scrollView)
    }

    static func semanticRevealTargetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        let insets = scrollView.adjustedContentInset
        let visibleSize = CGSize(
            width: max(0, scrollView.bounds.width - insets.left - insets.right),
            height: max(0, scrollView.bounds.height - insets.top - insets.bottom)
        )
        let contentSize = scrollView.contentSize
        let maxX = max(contentSize.width + insets.right - scrollView.bounds.width, -insets.left)
        let maxY = max(contentSize.height + insets.bottom - scrollView.bounds.height, -insets.top)
        let targetX = min(max(contentOrigin.x - insets.left - visibleSize.width / 2, -insets.left), maxX)
        let targetY = min(max(contentOrigin.y - insets.top - visibleSize.height / 2, -insets.top), maxY)
        return CGPoint(x: targetX, y: targetY)
    }
}

#endif // canImport(UIKit) && DEBUG
