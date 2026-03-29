#if canImport(UIKit)
#if DEBUG
import UIKit

/// Scroll primitives abstraction. TheBagman delegates all scrolling to a
/// ScrollProvider — this lets us swap between implementations:
///
///   - `ContentOffsetScrollProvider` — setContentOffset (current, precise)
///   - `AccessibilitySPIScrollProvider` — accessibilityScrollDownPage etc.
///     (animated, cooperative with the system, natural deceleration)
///
/// Both providers handle UIScrollViews. For non-UIScrollView containers
/// (SwiftUI's PlatformContainer), both fall back to synthetic swipe via
/// TheSafecracker.
@MainActor protocol ScrollProvider {

    /// Scroll a UIScrollView by one page in the given direction.
    /// Returns false if already at the edge (no movement possible).
    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool

    /// Scroll the minimum distance to make a target frame visible in a scroll view.
    /// Frame is in screen coordinates. Returns true if already visible or scroll triggered.
    func scrollToMakeVisible(
        _ targetFrame: CGRect,
        in scrollView: UIScrollView
    ) async -> Bool

    /// Scroll a non-UIScrollView region by one page using synthetic swipe.
    /// Always returns true (the gesture completes; stagnation detected by caller).
    func scrollBySwipe(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool
}

// MARK: - ContentOffset Provider (current implementation)

/// Scrolls by directly setting contentOffset on UIScrollViews.
/// Fast, precise, predictable page size (frame - 44pt overlap).
/// Fights SwiftUI's layout engine on some containers.
@MainActor final class ContentOffsetScrollProvider: ScrollProvider {

    private let safecracker: TheSafecracker

    init(safecracker: TheSafecracker) {
        self.safecracker = safecracker
    }

    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        safecracker.scrollByPage(scrollView, direction: direction, animated: false)
    }

    func scrollToMakeVisible(
        _ targetFrame: CGRect,
        in scrollView: UIScrollView
    ) async -> Bool {
        safecracker.scrollToMakeVisible(targetFrame, in: scrollView)
    }

    func scrollBySwipe(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        await safecracker.scrollBySwipe(frame: frame, direction: direction)
    }
}

// MARK: - Accessibility SPI Provider

/// Scrolls using private accessibility SPI methods:
///   - accessibilityScrollDownPage / UpPage / LeftPage / RightPage
///   - _accessibilityScrollToVisible
///
/// Animated, cooperative with the system, natural deceleration near edges.
/// Edge detection via contentOffset comparison before/after.
/// Requires run loop to be active (~5 frames for offset to settle).
@MainActor final class AccessibilitySPIScrollProvider: ScrollProvider {

    private let safecracker: TheSafecracker
    private let yieldFrames: (Int) async -> Void

    init(safecracker: TheSafecracker, yieldFrames: @escaping (Int) async -> Void) {
        self.safecracker = safecracker
        self.yieldFrames = yieldFrames
    }

    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        let before = scrollView.contentOffset
        performSPIScroll(scrollView, direction: direction)
        // SPI scroll is animated — needs the run loop to process.
        // Research showed ~5 frames, use 10 for safety.
        await yieldFrames(10)
        let after = scrollView.contentOffset
        return before != after
    }

    func scrollToMakeVisible(
        _ targetFrame: CGRect,
        in scrollView: UIScrollView
    ) async -> Bool {
        // Convert target frame to find the element at that position
        let targetInScrollView = scrollView.convert(targetFrame, from: nil)
        let visibleRect = CGRect(
            x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
            y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top,
            width: scrollView.frame.width - scrollView.adjustedContentInset.left - scrollView.adjustedContentInset.right,
            height: scrollView.frame.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom
        )
        if visibleRect.contains(targetInScrollView) { return true }

        // Fall back to setContentOffset — _accessibilityScrollToVisible needs
        // the element object, not a frame. The frame-based path uses the same
        // logic as ContentOffsetScrollProvider.
        return safecracker.scrollToMakeVisible(targetFrame, in: scrollView)
    }

    func scrollBySwipe(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        await safecracker.scrollBySwipe(frame: frame, direction: direction)
    }

    // MARK: - Private SPI dispatch

    private func performSPIScroll(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) {
        let sel: Selector
        switch direction {
        case .down, .next:
            sel = NSSelectorFromString("accessibilityScrollDownPage")
        case .up, .previous:
            sel = NSSelectorFromString("accessibilityScrollUpPage")
        case .right:
            sel = NSSelectorFromString("accessibilityScrollRightPage")
        case .left:
            sel = NSSelectorFromString("accessibilityScrollLeftPage")
        @unknown default:
            return
        }
        _ = scrollView.perform(sel)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
