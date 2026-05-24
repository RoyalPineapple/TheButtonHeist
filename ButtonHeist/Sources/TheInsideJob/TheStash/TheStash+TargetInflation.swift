#if canImport(UIKit)
#if DEBUG
import UIKit

// MARK: - Target Inflation

extension TheStash {

    enum KnownTargetInflationFailure: Equatable {
        case missingContentOrigin
        case noLiveScrollableAncestor
        case ambiguousLiveScrollableAncestor
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

    /// Make a known target live by scrolling a live parent derived from the
    /// current graph. Known-only semantic elements intentionally carry no
    /// scroll path; until `Screen` retains semantic container ancestry, a
    /// known-only target can be inflated only when the current live graph
    /// exposes exactly one plausible scroll parent for its content origin.
    /// Inflation is an internal positioning step, so the default is a
    /// non-animated jump that lets the next parse observe settled geometry.
    @discardableResult
    func inflateTarget(_ screenElement: ScreenElement) -> TargetInflationResolution {
        if visibleIds.contains(screenElement.heistId) {
            return .alreadyInflated
        }
        return KnownTargetInflator.inflate(
            screenElement,
            liveScrollView: liveScrollView(for: screenElement),
            fallbackScrollViews: currentScreen.liveInterface.scrollableContainerViews.values.compactMap { $0.view as? UIScrollView }
        )
    }

    func resolveInflationScrollView(for screenElement: ScreenElement) -> KnownTargetInflationResolution {
        KnownTargetInflator.resolveScrollView(
            for: screenElement,
            liveScrollView: liveScrollView(for: screenElement),
            fallbackScrollViews: currentScreen.liveInterface.scrollableContainerViews.values.compactMap { $0.view as? UIScrollView }
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
        liveScrollView: UIScrollView?,
        fallbackScrollViews: [UIScrollView]
    ) -> TheStash.TargetInflationResolution {
        switch resolveScrollView(
            for: screenElement,
            liveScrollView: liveScrollView,
            fallbackScrollViews: fallbackScrollViews
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
        liveScrollView: UIScrollView?,
        fallbackScrollViews: [UIScrollView]
    ) -> TheStash.KnownTargetInflationResolution {
        guard let origin = screenElement.contentSpaceOrigin else {
            return .failed(.missingContentOrigin)
        }

        if let liveScrollView {
            guard !liveScrollView.bhIsUnsafeForProgrammaticScrolling else {
                return .failed(.unsafeProgrammaticScroll)
            }
            return .resolved(liveScrollView)
        }

        let scrollViews = deduplicated(fallbackScrollViews)
        let safeCandidates = scrollViews.filter {
            !$0.bhIsUnsafeForProgrammaticScrolling && contentOrigin(origin, fitsIn: $0)
        }
        switch safeCandidates.count {
        case 1:
            return .resolved(safeCandidates[0])
        case 0:
            if !scrollViews.isEmpty,
               scrollViews.allSatisfy(\.bhIsUnsafeForProgrammaticScrolling) {
                return .failed(.unsafeProgrammaticScroll)
            }
            return .failed(.noLiveScrollableAncestor)
        default:
            return .failed(.ambiguousLiveScrollableAncestor)
        }
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

    private static func deduplicated(_ scrollViews: [UIScrollView]) -> [UIScrollView] {
        var seenScrollViews = Set<ObjectIdentifier>()
        return scrollViews.filter {
            seenScrollViews.insert(ObjectIdentifier($0)).inserted
        }
    }

    @MainActor
    private static func contentOrigin(_ origin: CGPoint, fitsIn scrollView: UIScrollView) -> Bool {
        let insets = scrollView.adjustedContentInset
        let minX = -insets.left
        let minY = -insets.top
        let maxX = scrollView.contentSize.width + insets.right
        let maxY = scrollView.contentSize.height + insets.bottom
        return origin.x >= minX
            && origin.y >= minY
            && origin.x <= maxX
            && origin.y <= maxY
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
