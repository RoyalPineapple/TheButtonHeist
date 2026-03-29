#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

/// Scroll primitives abstraction. TheBagman delegates all scrolling to a
/// ScrollProvider — this lets us swap between implementations:
///
///   - `ContentOffsetScrollProvider` — setContentOffset (fast, precise)
///   - `AccessibilitySPIScrollProvider` — private accessibility SPI
///     (animated, cooperative, natural deceleration)
///
/// Both handle UIScrollViews. For non-UIScrollView containers (SwiftUI's
/// PlatformContainer), both fall back to synthetic swipe via TheSafecracker.
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

    /// Jump to an absolute edge. Returns false if already there.
    func scrollToEdge(
        _ scrollView: UIScrollView,
        edge: TheScore.ScrollEdge
    ) async -> Bool
}

// MARK: - ContentOffset Provider

/// Scrolls by directly setting contentOffset on UIScrollViews.
/// Fast, precise, predictable page size (frame - 44pt overlap).
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

    func scrollToEdge(
        _ scrollView: UIScrollView,
        edge: TheScore.ScrollEdge
    ) async -> Bool {
        safecracker.scrollToEdge(scrollView, edge: edge)
    }
}

// MARK: - Accessibility SPI Provider

/// Scrolls using private accessibility SPI methods:
///   - accessibilityScrollDownPage / UpPage / LeftPage / RightPage
///   - _accessibilityScrollToTop / _accessibilityScrollToBottom
///
/// Animated, cooperative with the system, natural deceleration near edges.
/// Edge detection via contentOffset comparison before/after.
///
/// Two caveats discovered during research:
/// 1. Lazy containers (SwiftUI List) start with contentSize < frame.
///    The SPI refuses to scroll when content appears to fit. A small
///    setContentOffset bump materializes cells and grows contentSize.
/// 2. The SPI queues an animated scroll via CADisplayLink. Needs real
///    wall-clock time (~128ms) to settle, not just Task.yield().
@MainActor final class AccessibilitySPIScrollProvider: ScrollProvider {

    private let safecracker: TheSafecracker
    private let tripwire: TheTripwire

    /// Number of real frames to wait for SPI scroll animation to settle.
    /// Research showed ~5 frames needed, 8 for safety (~128ms at 60fps).
    private let settleFrames = 8

    init(safecracker: TheSafecracker, tripwire: TheTripwire) {
        self.safecracker = safecracker
        self.tripwire = tripwire
    }

    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        // Lazy contentSize bootstrap: if content fits in frame, the SPI
        // won't scroll. Bump contentOffset by 1pt to force cell materialization.
        if needsBootstrap(scrollView, direction: direction) {
            let tiny = bootstrapOffset(scrollView, direction: direction)
            scrollView.setContentOffset(tiny, animated: false)
            await settleAnimation()
        }

        let before = scrollView.contentOffset
        performSPIScroll(scrollView, direction: direction)
        await settleAnimation()
        return scrollView.contentOffset != before
    }

    func scrollToMakeVisible(
        _ targetFrame: CGRect,
        in scrollView: UIScrollView
    ) async -> Bool {
        // _accessibilityScrollToVisible requires the element object, not a frame.
        // Fall back to setContentOffset for the frame-based path.
        safecracker.scrollToMakeVisible(targetFrame, in: scrollView)
    }

    func scrollBySwipe(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        await safecracker.scrollBySwipe(frame: frame, direction: direction)
    }

    func scrollToEdge(
        _ scrollView: UIScrollView,
        edge: TheScore.ScrollEdge
    ) async -> Bool {
        let before = scrollView.contentOffset
        let sel: Selector
        switch edge {
        case .top:    sel = NSSelectorFromString("_accessibilityScrollToTop")
        case .bottom: sel = NSSelectorFromString("_accessibilityScrollToBottom")
        case .left, .right:
            // No SPI for left/right edge — fall back to setContentOffset
            return safecracker.scrollToEdge(scrollView, edge: edge)
        }
        _ = scrollView.perform(sel)
        await settleAnimation()
        return scrollView.contentOffset != before
    }

    // MARK: - Private

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

    /// The SPI queues an animated scroll via CADisplayLink. Need real wall-clock
    /// time for the animation to process — Task.yield() alone isn't enough.
    private func settleAnimation() async {
        await tripwire.yieldRealFrames(settleFrames)
    }

    /// Check if the scroll view needs a contentSize bootstrap.
    /// Lazy SwiftUI containers start with contentSize ≤ frame, causing the SPI
    /// to refuse scrolling. A 1pt offset bump materializes cells.
    private func needsBootstrap(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) -> Bool {
        switch direction {
        case .down, .next, .up, .previous:
            return scrollView.contentSize.height <= scrollView.frame.height
        case .right, .left:
            return scrollView.contentSize.width <= scrollView.frame.width
        @unknown default:
            return false
        }
    }

    /// A tiny offset bump to force lazy content materialization.
    private func bootstrapOffset(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) -> CGPoint {
        var offset = scrollView.contentOffset
        switch direction {
        case .down, .next: offset.y += 1
        case .up, .previous: offset.y = max(offset.y - 1, 0)
        case .right: offset.x += 1
        case .left: offset.x = max(offset.x - 1, 0)
        @unknown default: break
        }
        return offset
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
