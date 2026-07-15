#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore
import ThePlans

/// TheSafecracker scroll primitives — UIScrollView and screen-coordinate mechanics.
/// Takes a scroll view and movement parameters, produces offset changes.
/// Callers resolve any semantic target, container, or reveal policy before
/// entering this file.
extension TheSafecracker {

    enum ScrollPrimitiveResult: Equatable {
        case moved
        case alreadyInPosition
        case unavailable
    }

    private struct ScrollFingerPath {
        let start: CGPoint
        let end: CGPoint
    }

    /// Scroll by one page in the given direction with a 44pt overlap.
    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) -> ScrollPrimitiveResult {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return .unavailable }

        let overlap = CGFloat(ScrollContainerMetrics.pageOverlap)
        let size = scrollView.bounds.size
        let offset = clampedContentOffset(in: scrollView)
        let contentSize = scrollView.contentSize
        let insets = scrollView.adjustedContentInset

        var newOffset = offset

        switch direction {
        case .up:
            newOffset.y = max(offset.y - (size.height - overlap), -insets.top)
        case .down:
            newOffset.y = min(offset.y + size.height - overlap,
                             contentSize.height + insets.bottom - size.height)
        case .left:
            newOffset.x = max(offset.x - (size.width - overlap), -insets.left)
        case .right:
            newOffset.x = min(offset.x + size.width - overlap,
                             contentSize.width + insets.right - size.width)
        case .next:
            newOffset.y = min(offset.y + size.height - overlap,
                             contentSize.height + insets.bottom - size.height)
        case .previous:
            newOffset.y = max(offset.y - (size.height - overlap), -insets.top)
        @unknown default:
            return .unavailable
        }

        if contentOffsetsEqual(newOffset, offset) { return .alreadyInPosition }
        scrollView.setContentOffset(newOffset, animated: animated)
        return .moved
    }

    /// Scrolls so a live screen point lands in the preferred screen rect when
    /// possible, otherwise at least inside the minimum screen rect.
    func scrollToMakeScreenPointVisible(
        _ screenPoint: CGPoint,
        in scrollView: UIScrollView,
        animated: Bool = true,
        preferredScreenRect: CGRect,
        minimumScreenRect: CGRect
    ) -> ScrollPrimitiveResult {
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

        let insets = scrollView.adjustedContentInset
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        newOffset.x = max(-insets.left, min(newOffset.x, maxX))
        newOffset.y = max(-insets.top, min(newOffset.y, maxY))

        let offsetDelta = CGPoint(
            x: newOffset.x - currentOffset.x,
            y: newOffset.y - currentOffset.y
        )
        let futurePreferredRect = preferredVisibleRect.offsetBy(dx: offsetDelta.x, dy: offsetDelta.y)
        let futureMinimumRect = minimumVisibleRect.offsetBy(dx: offsetDelta.x, dy: offsetDelta.y)
        guard futurePreferredRect.contains(pointInContent)
            || futureMinimumRect.contains(pointInContent)
        else { return .unavailable }

        if newOffset.x == currentOffset.x && newOffset.y == currentOffset.y { return .alreadyInPosition }

        scrollView.setContentOffset(newOffset, animated: animated)
        return .moved
    }

    /// Centers a previously observed scroll-content point in the current viewport.
    func revealContentPoint(
        _ contentPoint: ScrollContentPoint,
        in scrollView: UIScrollView
    ) -> ScrollPrimitiveResult {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return .unavailable }

        let point = contentPoint.cgPoint
        let insets = scrollView.adjustedContentInset
        let visibleWidth = max(1, scrollView.bounds.width - insets.left - insets.right)
        let visibleHeight = max(1, scrollView.bounds.height - insets.top - insets.bottom)
        let minX = -insets.left
        let minY = -insets.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + insets.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        let targetOffset = CGPoint(
            x: min(max(point.x - visibleWidth / 2 - insets.left, minX), maxX),
            y: min(max(point.y - visibleHeight / 2 - insets.top, minY), maxY)
        )
        guard !contentOffsetsEqual(targetOffset, clampedContentOffset(in: scrollView)) else {
            return .alreadyInPosition
        }

        scrollView.setContentOffset(targetOffset, animated: false)
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

    /// Scroll to an absolute edge.
    func scrollToEdge(
        _ scrollView: UIScrollView,
        edge: ScrollEdge,
        animated: Bool = true
    ) -> ScrollPrimitiveResult {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return .unavailable }

        let insets = scrollView.adjustedContentInset
        let currentOffset = clampedContentOffset(in: scrollView)
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

        if contentOffsetsEqual(newOffset, currentOffset) {
            return .alreadyInPosition
        }
        scrollView.setContentOffset(newOffset, animated: animated)
        return .moved
    }

    /// Restore a scroll view to a previously captured visual content origin.
    func restoreVisualOrigin(
        _ visualOrigin: CGPoint,
        in scrollView: UIScrollView
    ) -> ScrollPrimitiveResult {
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
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        let clampedOffset = CGPoint(
            x: max(-insets.left, min(restoredOffset.x, maxX)),
            y: max(-insets.top, min(restoredOffset.y, maxY))
        )
        scrollView.setContentOffset(clampedOffset, animated: false)
        return .moved
    }

    private func clampedContentOffset(in scrollView: UIScrollView) -> CGPoint {
        let insets = scrollView.adjustedContentInset
        let minimum = CGPoint(x: -insets.left, y: -insets.top)
        let maximum = CGPoint(
            x: max(minimum.x, scrollView.contentSize.width + insets.right - scrollView.bounds.width),
            y: max(minimum.y, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
        )
        return CGPoint(
            x: min(max(scrollView.contentOffset.x, minimum.x), maximum.x),
            y: min(max(scrollView.contentOffset.y, minimum.y), maximum.y)
        )
    }

    private func contentOffsetsEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 0.5 && abs(lhs.y - rhs.y) <= 0.5
    }

    /// Scroll a region by one page using a synthetic swipe gesture.
    /// Used for scrollable containers that aren't UIScrollViews (e.g. SwiftUI's
    /// HostingScrollView.PlatformContainer). The swipe covers 75% of the frame
    /// in the given direction, slow enough for iOS to recognize as a scroll.
    func scrollBySwipe(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection,
        duration: GestureDuration = .scrollSwipeDefault
    ) async -> ScrollPrimitiveResult {
        guard let path = Self.scrollFingerPath(frame: frame, direction: direction, travel: 0.75) else {
            return .unavailable
        }
        return await swipe(from: path.start, to: path.end, duration: duration) ? .moved : .unavailable
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
