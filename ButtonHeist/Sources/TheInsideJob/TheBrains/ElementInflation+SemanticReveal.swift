#if canImport(UIKit) && DEBUG
import UIKit

extension ElementInflation {

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
    func revealSemanticTarget(_ screenElement: TheStash.ScreenElement) -> SemanticRevealResult {
        if stash.visibleIds.contains(screenElement.heistId) {
            return .alreadyVisible
        }

        guard let origin = screenElement.contentSpaceOrigin else {
            return .failed(.missingContentOrigin)
        }
        guard let scrollView = stash.liveScrollView(for: screenElement) else {
            return .failed(.noLiveScrollableAncestor)
        }
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else {
            return .failed(.unsafeProgrammaticScroll)
        }

        scrollView.setContentOffset(Self.semanticRevealTargetOffset(for: origin, in: scrollView), animated: false)
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
