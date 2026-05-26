#if canImport(UIKit)
#if DEBUG
import UIKit

// MARK: - Semantic Reveal Plan

extension TheStash {

    enum SemanticRevealPlanFailure: Equatable {
        case missingContentOrigin
        case noLiveScrollableAncestor
        case unsafeProgrammaticScroll
    }

    enum SemanticRevealScrollViewResolution {
        case resolved(UIScrollView)
        case failed(SemanticRevealPlanFailure)
    }

    enum SemanticRevealPlan {
        case alreadyVisible
        case scroll(scrollView: UIScrollView, targetOffset: CGPoint)
        case failed(SemanticRevealPlanFailure)
    }

    enum SemanticRevealPlanExecution {
        case alreadyVisible
        case revealed(UIScrollView)
        case failed(SemanticRevealPlanFailure)

        var didReveal: Bool {
            if case .revealed = self { return true }
            return false
        }
    }

    /// Build the semantic reveal plan for a known target from the current
    /// graph. Known-only semantic elements carry no executable scroll authority
    /// unless the parser retained a live scroll ancestor.
    func semanticRevealPlan(for screenElement: ScreenElement) -> SemanticRevealPlan {
        if visibleIds.contains(screenElement.heistId) {
            return .alreadyVisible
        }
        return SemanticRevealPlanner.plan(
            screenElement,
            liveScrollView: liveScrollView(for: screenElement)
        )
    }

    /// Execute the semantic reveal plan for a known target. Reveal is an
    /// internal product path, so the default is a non-animated jump that lets
    /// the next parse observe settled geometry.
    @discardableResult
    func executeSemanticRevealPlan(for screenElement: ScreenElement) -> SemanticRevealPlanExecution {
        SemanticRevealPlanner.execute(semanticRevealPlan(for: screenElement))
    }

    func resolveSemanticRevealScrollView(for screenElement: ScreenElement) -> SemanticRevealScrollViewResolution {
        SemanticRevealPlanner.resolveScrollView(
            for: screenElement,
            liveScrollView: liveScrollView(for: screenElement)
        )
    }

    static func semanticRevealTargetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        SemanticRevealPlanner.targetOffset(for: contentOrigin, in: scrollView)
    }
}

private enum SemanticRevealPlanner {

    @MainActor
    static func plan(
        _ screenElement: TheStash.ScreenElement,
        liveScrollView: UIScrollView?
    ) -> TheStash.SemanticRevealPlan {
        switch resolveScrollView(
            for: screenElement,
            liveScrollView: liveScrollView
        ) {
        case .resolved(let scrollView):
            guard let origin = screenElement.contentSpaceOrigin else {
                return .failed(.missingContentOrigin)
            }
            return .scroll(
                scrollView: scrollView,
                targetOffset: targetOffset(for: origin, in: scrollView)
            )
        case .failed(let failure):
            return .failed(failure)
        }
    }

    @MainActor
    static func execute(_ plan: TheStash.SemanticRevealPlan) -> TheStash.SemanticRevealPlanExecution {
        switch plan {
        case .alreadyVisible:
            return .alreadyVisible
        case .scroll(let scrollView, let targetOffset):
            scrollView.setContentOffset(targetOffset, animated: false)
            return .revealed(scrollView)
        case .failed(let failure):
            return .failed(failure)
        }
    }

    @MainActor
    static func resolveScrollView(
        for screenElement: TheStash.ScreenElement,
        liveScrollView: UIScrollView?
    ) -> TheStash.SemanticRevealScrollViewResolution {
        guard screenElement.contentSpaceOrigin != nil else {
            return .failed(.missingContentOrigin)
        }

        if let liveScrollView {
            guard !liveScrollView.bhIsUnsafeForProgrammaticScrolling else {
                return .failed(.unsafeProgrammaticScroll)
            }
            return .resolved(liveScrollView)
        }

        return .failed(.noLiveScrollableAncestor)
    }

    @MainActor
    static func targetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        let visibleSize = scrollView.bounds.size
        let insets = scrollView.adjustedContentInset
        let contentSize = scrollView.contentSize
        let maxX = max(contentSize.width + insets.right - visibleSize.width, -insets.left)
        let maxY = max(contentSize.height + insets.bottom - visibleSize.height, -insets.top)
        let targetX = min(max(contentOrigin.x - visibleSize.width / 2, -insets.left), maxX)
        let targetY = min(max(contentOrigin.y - visibleSize.height / 2, -insets.top), maxY)
        return CGPoint(x: targetX, y: targetY)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
