#if canImport(UIKit)
#if DEBUG
import UIKit

// MARK: - Target Inflation

extension TheStash {

    enum KnownTargetInflationFailure: Equatable {
        case missingContentOrigin
        case noLiveScrollableAncestor
        case unsafeProgrammaticScroll
    }

    enum KnownTargetInflationResolution {
        case resolved(UIScrollView)
        case failed(KnownTargetInflationFailure)
    }

    enum TargetInflationResolution {
        case alreadyInflated
        case inflated(UIScrollView)
        case failed(KnownTargetInflationFailure)

        var didScroll: Bool {
            if case .inflated = self { return true }
            return false
        }
    }

    /// Make a known target live by scrolling the live parent proven by the
    /// current graph. Known-only semantic elements intentionally carry no
    /// executable scroll authority unless the parser retained their live
    /// scroll ancestor.
    /// Inflation is an internal positioning step, so the default is a
    /// non-animated jump that lets the next parse observe settled geometry.
    @discardableResult
    func inflateTarget(_ screenElement: ScreenElement) -> TargetInflationResolution {
        if visibleIds.contains(screenElement.heistId) {
            return .alreadyInflated
        }
        return KnownTargetInflator.inflate(
            screenElement,
            liveScrollView: liveScrollView(for: screenElement)
        )
    }

    func resolveInflationScrollView(for screenElement: ScreenElement) -> KnownTargetInflationResolution {
        KnownTargetInflator.resolveScrollView(
            for: screenElement,
            liveScrollView: liveScrollView(for: screenElement)
        )
    }

    static func scrollTargetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        KnownTargetInflator.scrollTargetOffset(for: contentOrigin, in: scrollView)
    }
}

private enum KnownTargetInflator {

    @MainActor
    static func inflate(
        _ screenElement: TheStash.ScreenElement,
        liveScrollView: UIScrollView?
    ) -> TheStash.TargetInflationResolution {
        switch resolveScrollView(
            for: screenElement,
            liveScrollView: liveScrollView
        ) {
        case .resolved(let scrollView):
            guard let origin = screenElement.contentSpaceOrigin else {
                return .failed(.missingContentOrigin)
            }
            let targetOffset = scrollTargetOffset(for: origin, in: scrollView)
            scrollView.setContentOffset(targetOffset, animated: false)
            return .inflated(scrollView)
        case .failed(let failure):
            return .failed(failure)
        }
    }

    @MainActor
    static func resolveScrollView(
        for screenElement: TheStash.ScreenElement,
        liveScrollView: UIScrollView?
    ) -> TheStash.KnownTargetInflationResolution {
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
    static func scrollTargetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
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
