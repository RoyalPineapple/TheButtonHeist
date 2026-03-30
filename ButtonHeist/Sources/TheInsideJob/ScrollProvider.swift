#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

/// Scroll primitives abstraction. TheBagman delegates all scrolling here.
/// UIScrollViews get direct setContentOffset. Non-UIScrollView containers
/// (SwiftUI's PlatformContainer) get synthetic swipe via TheSafecracker.
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

#endif // DEBUG
#endif // canImport(UIKit)
