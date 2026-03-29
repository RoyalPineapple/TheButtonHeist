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
/// Both handle UIScrollViews directly. For non-UIScrollView scrollable
/// containers (SwiftUI's PlatformContainer), the SPI provider uses
/// accessibilityScrollDownPage etc., ContentOffset falls back to swipe.
@MainActor protocol ScrollProvider {

    /// Scroll a UIScrollView by one page in the given direction.
    /// Returns false if already at the edge (no movement possible).
    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool

    /// Scroll any view by one page using accessibility SPI or swipe fallback.
    /// For non-UIScrollView containers (e.g. SwiftUI PlatformContainer).
    func scrollViewByPage(
        _ view: UIView,
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
/// For non-UIScrollView containers, falls back to synthetic swipe.
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

    func scrollViewByPage(
        _ view: UIView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        let screenFrame = view.convert(view.bounds, to: nil)
        return await safecracker.scrollBySwipe(frame: screenFrame, direction: direction)
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
/// Works on ANY view the accessibility system considers scrollable — including
/// SwiftUI's PlatformContainer which is not a UIScrollView but responds to the
/// SPI scroll selectors.
///
/// Edge detection: for UIScrollViews, compares contentOffset before/after.
/// For non-UIScrollViews (no contentOffset), returns true optimistically and
/// lets the caller's stagnation check handle termination.
///
/// Caveats:
/// 1. Lazy containers start with contentSize < frame. A 1pt setContentOffset
///    bump materializes cells before the first SPI scroll.
/// 2. The SPI queues an animated scroll via CADisplayLink. Needs 3 real frames
///    (~48ms) to settle.
@MainActor final class AccessibilitySPIScrollProvider: ScrollProvider {

    private let safecracker: TheSafecracker
    private let tripwire: TheTripwire

    /// Number of real frames to wait for SPI scroll animation to settle.
    /// Testing showed 3 frames (48ms) is the minimum for offset detection.
    private let settleFrames = 3

    init(safecracker: TheSafecracker, tripwire: TheTripwire) {
        self.safecracker = safecracker
        self.tripwire = tripwire
    }

    func scrollByPage(
        _ scrollView: UIScrollView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        if needsBootstrap(scrollView, direction: direction) {
            let tiny = bootstrapOffset(scrollView, direction: direction)
            scrollView.setContentOffset(tiny, animated: false)
            await settle()
        }
        let before = scrollView.contentOffset
        performSPIScroll(scrollView, direction: direction)
        await settle()
        return scrollView.contentOffset != before
    }

    func scrollViewByPage(
        _ view: UIView,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        // PlatformContainer responds to accessibilityScrollDownPage etc.
        // No contentOffset to compare — return true and let caller detect stagnation.
        performSPIScroll(view, direction: direction)
        await settle()
        return true
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
        let before = scrollView.contentOffset
        switch edge {
        case .top:
            _ = scrollView.perform(NSSelectorFromString("_accessibilityScrollToTop"))
        case .bottom:
            _ = scrollView.perform(NSSelectorFromString("_accessibilityScrollToBottom"))
        case .left, .right:
            return safecracker.scrollToEdge(scrollView, edge: edge)
        }
        await settle()
        return scrollView.contentOffset != before
    }

    // MARK: - Private

    private func performSPIScroll(_ view: UIView, direction: UIAccessibilityScrollDirection) {
        let sel: Selector
        switch direction {
        case .down, .next:     sel = NSSelectorFromString("accessibilityScrollDownPage")
        case .up, .previous:   sel = NSSelectorFromString("accessibilityScrollUpPage")
        case .right:           sel = NSSelectorFromString("accessibilityScrollRightPage")
        case .left:            sel = NSSelectorFromString("accessibilityScrollLeftPage")
        @unknown default: return
        }
        guard view.responds(to: sel) else { return }
        _ = view.perform(sel)
    }

    private func settle() async {
        await tripwire.yieldRealFrames(settleFrames)
    }

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
