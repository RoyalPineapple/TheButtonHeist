#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

/// TheSafecracker scroll primitives — pure UIScrollView manipulation.
/// Takes a scroll view and movement parameters, produces offset changes.
/// No element awareness, no TheBagman reference. TheBagman finds the
/// scroll view from the accessibility hierarchy and passes it here.
extension TheSafecracker {

    /// Points of overlap retained between page scrolls so users keep context.
    static let pageOverlap: CGFloat = 44

    /// Scroll by one page in the given direction with a 44pt overlap.
    /// Returns false if already at the edge (no movement possible).
    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) -> Bool {
        let overlap = Self.pageOverlap
        let size = scrollView.frame.size
        let offset = scrollView.contentOffset
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
            return false
        }

        if newOffset.x == offset.x && newOffset.y == offset.y { return false }
        scrollView.setContentOffset(newOffset, animated: animated)
        return true
    }

    /// Scroll the minimum distance needed to make a frame visible.
    /// Frame is in screen coordinates; converted to scroll view content space internally.
    /// Returns true if already visible or if scroll was triggered.
    func scrollToMakeVisible(_ targetFrame: CGRect, in scrollView: UIScrollView, animated: Bool = true) -> Bool {
        let targetInScrollView = scrollView.convert(targetFrame, from: nil)

        let visibleRect = CGRect(
            x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
            y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top,
            width: scrollView.frame.width - scrollView.adjustedContentInset.left - scrollView.adjustedContentInset.right,
            height: scrollView.frame.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom
        )

        if visibleRect.contains(targetInScrollView) { return true }

        var newOffset = scrollView.contentOffset

        if targetInScrollView.minX < visibleRect.minX {
            newOffset.x -= visibleRect.minX - targetInScrollView.minX
        } else if targetInScrollView.maxX > visibleRect.maxX {
            newOffset.x += targetInScrollView.maxX - visibleRect.maxX
        }

        if targetInScrollView.minY < visibleRect.minY {
            newOffset.y -= visibleRect.minY - targetInScrollView.minY
        } else if targetInScrollView.maxY > visibleRect.maxY {
            newOffset.y += targetInScrollView.maxY - visibleRect.maxY
        }

        let insets = scrollView.adjustedContentInset
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        newOffset.x = max(-insets.left, min(newOffset.x, maxX))
        newOffset.y = max(-insets.top, min(newOffset.y, maxY))

        if newOffset.x == scrollView.contentOffset.x && newOffset.y == scrollView.contentOffset.y {
            return true
        }

        scrollView.setContentOffset(newOffset, animated: animated)
        return true
    }

    /// Scroll to an absolute edge.
    func scrollToEdge(_ scrollView: UIScrollView, edge: ScrollEdge) -> Bool {
        let insets = scrollView.adjustedContentInset
        var newOffset = scrollView.contentOffset

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

        if newOffset.x == scrollView.contentOffset.x && newOffset.y == scrollView.contentOffset.y {
            return true
        }
        scrollView.setContentOffset(newOffset, animated: true)
        return true
    }

    /// Jump to the opposite edge of the scroll view (for bidirectional search).
    func scrollToOppositeEdge(
        _ scrollView: UIScrollView,
        from direction: ScrollSearchDirection
    ) {
        let insets = scrollView.adjustedContentInset

        switch direction {
        case .down:
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -insets.top), animated: false)
        case .up:
            let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: maxY), animated: false)
        case .right:
            scrollView.setContentOffset(CGPoint(x: -insets.left, y: scrollView.contentOffset.y), animated: false)
        case .left:
            let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
            scrollView.setContentOffset(CGPoint(x: maxX, y: scrollView.contentOffset.y), animated: false)
        }
    }

    /// Scroll a region by one page using a synthetic swipe gesture.
    /// Used for scrollable containers that aren't UIScrollViews (e.g. SwiftUI's
    /// HostingScrollView.PlatformContainer). The swipe covers 75% of the frame
    /// in the given direction, slow enough for iOS to recognize as a scroll.
    func scrollBySwipe(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection,
        duration: TimeInterval = 0.25
    ) async -> Bool {
        let travel: CGFloat = 0.75
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let start: CGPoint
        let end: CGPoint

        switch direction {
        case .down:
            start = CGPoint(x: center.x, y: center.y + frame.height * travel / 2)
            end = CGPoint(x: center.x, y: center.y - frame.height * travel / 2)
        case .up:
            start = CGPoint(x: center.x, y: center.y - frame.height * travel / 2)
            end = CGPoint(x: center.x, y: center.y + frame.height * travel / 2)
        case .right:
            start = CGPoint(x: center.x + frame.width * travel / 2, y: center.y)
            end = CGPoint(x: center.x - frame.width * travel / 2, y: center.y)
        case .left:
            start = CGPoint(x: center.x - frame.width * travel / 2, y: center.y)
            end = CGPoint(x: center.x + frame.width * travel / 2, y: center.y)
        case .next:
            start = CGPoint(x: center.x, y: center.y + frame.height * travel / 2)
            end = CGPoint(x: center.x, y: center.y - frame.height * travel / 2)
        case .previous:
            start = CGPoint(x: center.x, y: center.y - frame.height * travel / 2)
            end = CGPoint(x: center.x, y: center.y + frame.height * travel / 2)
        @unknown default:
            return false
        }

        return await swipe(from: start, to: end, duration: duration)
    }

    /// Total items in a UITableView or UICollectionView (for exhaustive search).
    func queryCollectionTotalItems(_ scrollView: UIScrollView) -> Int? {
        if let collectionView = scrollView as? UICollectionView {
            var total = 0
            for section in 0..<collectionView.numberOfSections {
                total += collectionView.numberOfItems(inSection: section)
            }
            return total
        }
        if let tableView = scrollView as? UITableView {
            var total = 0
            for section in 0..<tableView.numberOfSections {
                total += tableView.numberOfRows(inSection: section)
            }
            return total
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
