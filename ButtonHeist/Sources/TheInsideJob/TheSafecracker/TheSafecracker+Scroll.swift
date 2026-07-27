#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore
import ThePlans

extension TheSafecracker {

    enum ScrollPrimitiveOutcome: Equatable, Sendable {
        case moved
        case alreadyInPosition
        case unavailable
    }

    private struct ScrollFingerPath {
        let start: CGPoint
        let end: CGPoint
    }

    private enum ContentOffsetPolicy {
        case movement
        case restoration
    }

    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) -> ScrollPrimitiveOutcome {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return .unavailable }

        let overlap = CGFloat(ScrollContainerMetrics.pageOverlap)
        let size = scrollView.bounds.size
        guard let offset = admittedContentOffset(
            scrollView.contentOffset,
            in: scrollView,
            policy: .restoration
        ) else { return .unavailable }

        var newOffset = offset

        switch direction {
        case .up:
            newOffset.y = offset.y - (size.height - overlap)
        case .down:
            newOffset.y = offset.y + size.height - overlap
        case .left:
            newOffset.x = offset.x - (size.width - overlap)
        case .right:
            newOffset.x = offset.x + size.width - overlap
        case .next:
            newOffset.y = offset.y + size.height - overlap
        case .previous:
            newOffset.y = offset.y - (size.height - overlap)
        @unknown default:
            return .unavailable
        }

        guard let admittedOffset = admittedContentOffset(
            newOffset,
            in: scrollView,
            policy: .movement
        ) else { return .unavailable }
        if contentOffsetsEqual(admittedOffset, offset) { return .alreadyInPosition }
        dispatchContentOffset(admittedOffset, in: scrollView, animated: animated)
        return .moved
    }

    func scrollToMakeScreenPointVisible(
        _ screenPoint: CGPoint,
        in scrollView: UIScrollView,
        animated: Bool = true,
        preferredScreenRect: CGRect,
        minimumScreenRect: CGRect
    ) -> ScrollPrimitiveOutcome {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return .unavailable }

        let pointInContent = scrollView.convert(screenPoint, from: nil)
        let currentOffset = scrollView.contentOffset
        let fullVisibleRect = visibleRect(in: scrollView, at: currentOffset)
        let preferredVisibleRect = usableVisibleRect(
            screenRect: preferredScreenRect,
            fullVisibleRect: fullVisibleRect,
            in: scrollView
        )
        let minimumVisibleRect = usableVisibleRect(
            screenRect: minimumScreenRect,
            fullVisibleRect: fullVisibleRect,
            in: scrollView
        )

        if preferredVisibleRect.contains(pointInContent) { return .alreadyInPosition }

        let targetRect = preferredVisibleRect.isUsableForPoint ? preferredVisibleRect : minimumVisibleRect
        guard targetRect.isUsableForPoint else { return .unavailable }

        var newOffset = currentOffset
        if pointInContent.x < targetRect.minX || pointInContent.x >= targetRect.maxX {
            newOffset.x += pointInContent.x - targetRect.midX
        }
        if pointInContent.y < targetRect.minY || pointInContent.y >= targetRect.maxY {
            newOffset.y += pointInContent.y - targetRect.midY
        }

        guard let admittedOffset = admittedContentOffset(
            newOffset,
            in: scrollView,
            policy: .movement
        ) else { return .unavailable }

        let offsetDelta = CGPoint(
            x: admittedOffset.x - currentOffset.x,
            y: admittedOffset.y - currentOffset.y
        )
        let futurePreferredRect = preferredVisibleRect.offsetBy(dx: offsetDelta.x, dy: offsetDelta.y)
        let futureMinimumRect = minimumVisibleRect.offsetBy(dx: offsetDelta.x, dy: offsetDelta.y)
        guard futurePreferredRect.contains(pointInContent)
            || futureMinimumRect.contains(pointInContent)
        else { return .unavailable }

        if admittedOffset.x == currentOffset.x && admittedOffset.y == currentOffset.y {
            return .alreadyInPosition
        }

        dispatchContentOffset(admittedOffset, in: scrollView, animated: animated)
        return .moved
    }

    func revealContentPoint(
        _ contentPoint: ScrollContentPoint,
        in scrollView: UIScrollView
    ) -> ScrollPrimitiveOutcome {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return .unavailable }

        let point = contentPoint.cgPoint
        let insets = scrollView.adjustedContentInset
        let visibleWidth = max(1, scrollView.bounds.width - insets.left - insets.right)
        let visibleHeight = max(1, scrollView.bounds.height - insets.top - insets.bottom)
        let proposedOffset = CGPoint(
            x: point.x - visibleWidth / 2 - insets.left,
            y: point.y - visibleHeight / 2 - insets.top
        )
        guard let targetOffset = admittedContentOffset(
            proposedOffset,
            in: scrollView,
            policy: .movement
        ), let currentOffset = admittedContentOffset(
            scrollView.contentOffset,
            in: scrollView,
            policy: .restoration
        ) else { return .unavailable }
        guard !contentOffsetsEqual(targetOffset, currentOffset) else {
            return .alreadyInPosition
        }

        dispatchContentOffset(targetOffset, in: scrollView, animated: false)
        return .moved
    }

    private func usableVisibleRect(
        screenRect: CGRect,
        fullVisibleRect: CGRect,
        in scrollView: UIScrollView
    ) -> CGRect {
        let contentRect = scrollView.convert(screenRect, from: nil)
        return fullVisibleRect.intersection(contentRect)
    }

    private func visibleRect(in scrollView: UIScrollView, at offset: CGPoint) -> CGRect {
        let inset = scrollView.adjustedContentInset
        return CGRect(
            x: offset.x + inset.left,
            y: offset.y + inset.top,
            width: scrollView.frame.width - inset.left - inset.right,
            height: scrollView.frame.height - inset.top - inset.bottom
        )
    }

    func scrollToEdge(
        _ scrollView: UIScrollView,
        edge: ScrollEdge,
        animated: Bool = true
    ) -> ScrollPrimitiveOutcome {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return .unavailable }

        let insets = scrollView.adjustedContentInset
        guard let currentOffset = admittedContentOffset(
            scrollView.contentOffset,
            in: scrollView,
            policy: .restoration
        ) else { return .unavailable }
        var newOffset = currentOffset

        switch edge {
        case .top:
            newOffset.y = -insets.top
        case .bottom:
            newOffset.y = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        case .left:
            newOffset.x = -insets.left
        case .right:
            newOffset.x = scrollView.contentSize.width + insets.right - scrollView.frame.width
        }

        guard let admittedOffset = admittedContentOffset(
            newOffset,
            in: scrollView,
            policy: .movement
        ) else { return .unavailable }
        if contentOffsetsEqual(admittedOffset, currentOffset) {
            return .alreadyInPosition
        }
        dispatchContentOffset(admittedOffset, in: scrollView, animated: animated)
        return .moved
    }

    func restoreVisualOrigin(
        _ visualOrigin: CGPoint,
        in scrollView: UIScrollView
    ) -> ScrollPrimitiveOutcome {
        let insets = scrollView.adjustedContentInset
        let currentOrigin = CGPoint(
            x: scrollView.contentOffset.x + insets.left,
            y: scrollView.contentOffset.y + insets.top
        )
        guard currentOrigin != visualOrigin else { return .alreadyInPosition }

        let restoredOffset = CGPoint(
            x: visualOrigin.x - insets.left,
            y: visualOrigin.y - insets.top
        )
        guard let admittedOffset = admittedContentOffset(
            restoredOffset,
            in: scrollView,
            policy: .restoration
        ) else { return .unavailable }
        dispatchContentOffset(admittedOffset, in: scrollView, animated: false)
        return .moved
    }

    private func admittedContentOffset(
        _ proposedOffset: CGPoint,
        in scrollView: UIScrollView,
        policy: ContentOffsetPolicy
    ) -> CGPoint? {
        let insets = scrollView.adjustedContentInset
        let minimum = CGPoint(x: -insets.left, y: -insets.top)
        let maximum = CGPoint(
            x: max(minimum.x, scrollView.contentSize.width + insets.right - scrollView.bounds.width),
            y: max(minimum.y, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
        )
        guard proposedOffset.x.isFinite,
              proposedOffset.y.isFinite,
              minimum.x.isFinite,
              minimum.y.isFinite,
              maximum.x.isFinite,
              maximum.y.isFinite
        else { return nil }

        let clampedOffset = CGPoint(
            x: min(max(proposedOffset.x, minimum.x), maximum.x),
            y: min(max(proposedOffset.y, minimum.y), maximum.y)
        )
        guard case .movement = policy, scrollView.isPagingEnabled else {
            return clampedOffset
        }

        guard let x = admittedPagingOffset(
            clampedOffset.x,
            minimum: minimum.x,
            maximum: maximum.x,
            pageExtent: scrollView.bounds.width
        ), let y = admittedPagingOffset(
            clampedOffset.y,
            minimum: minimum.y,
            maximum: maximum.y,
            pageExtent: scrollView.bounds.height
        ) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func admittedPagingOffset(
        _ proposedOffset: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        pageExtent: CGFloat
    ) -> CGFloat? {
        guard maximum > minimum else { return minimum }
        guard pageExtent.isFinite, pageExtent > 0 else { return nil }

        let maximumPageIndex = floor((maximum - minimum) / pageExtent)
        let proposedPageIndex = ((proposedOffset - minimum) / pageExtent).rounded()
        guard maximumPageIndex.isFinite, proposedPageIndex.isFinite else { return nil }

        let pageIndex = min(max(proposedPageIndex, 0), maximumPageIndex)
        let pageOffset = minimum + pageIndex * pageExtent
        guard pageOffset.isFinite else { return nil }
        return abs(maximum - proposedOffset) < abs(pageOffset - proposedOffset)
            ? maximum
            : pageOffset
    }

    private func dispatchContentOffset(
        _ contentOffset: CGPoint,
        in scrollView: UIScrollView,
        animated: Bool
    ) {
        scrollView.setContentOffset(contentOffset, animated: animated)
        if !animated {
            // An unanimated offset is set by the time that call returns, and
            // the subviews it moves are laid out at the next layout pass. The
            // scroll has landed once they have moved, so this is where it lands.
            scrollView.layoutIfNeeded()
        }
    }

    private func contentOffsetsEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 0.5 && abs(lhs.y - rhs.y) <= 0.5
    }

    func prepareScrollBySwipe(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection,
        duration: GestureDuration = .scrollSwipeDefault
    ) -> PreparedTouchDispatch? {
        guard let path = Self.scrollFingerPath(frame: frame, direction: direction, travel: 0.75) else {
            return nil
        }
        return prepareSwipe(from: path.start, to: path.end, duration: duration)
    }

    private static func scrollFingerPath(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection,
        travel: CGFloat
    ) -> ScrollFingerPath? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        switch direction {
        case .down, .next:
            return ScrollFingerPath(
                start: CGPoint(x: center.x, y: center.y + frame.height * travel / 2),
                end: CGPoint(x: center.x, y: center.y - frame.height * travel / 2)
            )
        case .up, .previous:
            return ScrollFingerPath(
                start: CGPoint(x: center.x, y: center.y - frame.height * travel / 2),
                end: CGPoint(x: center.x, y: center.y + frame.height * travel / 2)
            )
        case .right:
            return ScrollFingerPath(
                start: CGPoint(x: center.x + frame.width * travel / 2, y: center.y),
                end: CGPoint(x: center.x - frame.width * travel / 2, y: center.y)
            )
        case .left:
            return ScrollFingerPath(
                start: CGPoint(x: center.x - frame.width * travel / 2, y: center.y),
                end: CGPoint(x: center.x + frame.width * travel / 2, y: center.y)
            )
        @unknown default:
            return nil
        }
    }

}

private extension CGRect {
    var isUsableForPoint: Bool {
        !isNull && !isEmpty && width.isFinite && height.isFinite
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
