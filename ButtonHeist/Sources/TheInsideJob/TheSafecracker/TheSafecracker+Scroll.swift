#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

/// TheSafecracker scroll primitives — pure UIScrollView manipulation.
/// Takes a scroll view and movement parameters, produces offset changes.
/// No element awareness, no TheStash reference. TheStash finds the
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
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return false }

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

    /// Scroll the minimum distance needed to make a frame visible within a comfort zone.
    /// Frame is in screen coordinates; converted to scroll view content space internally.
    /// `comfortMarginFraction` insets the visible rect by that fraction on each side
    /// (e.g. 1/6 targets the middle 2/3). Each axis uses the comfort zone when
    /// the target fits on that axis and the full visible rect when it does not.
    /// Returns true if the target is already visible or the resulting offset can make it visible.
    func scrollToMakeVisible(
        _ targetFrame: CGRect,
        in scrollView: UIScrollView,
        animated: Bool = true,
        comfortMarginFraction: CGFloat = 0
    ) -> Bool {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return false }

        let targetInScrollView = scrollView.convert(targetFrame, from: nil)

        let fullVisibleRect = visibleRect(in: scrollView, at: scrollView.contentOffset)

        let comfortRect = makeComfortRect(
            in: fullVisibleRect,
            comfortMarginFraction: comfortMarginFraction
        )
        let targetVisibleRect = preferredVisibleRect(
            for: targetInScrollView,
            comfortRect: comfortRect,
            fullVisibleRect: fullVisibleRect
        )

        if targetVisibleRect.contains(targetInScrollView) { return true }

        var newOffset = scrollView.contentOffset

        if targetInScrollView.minX < targetVisibleRect.minX {
            newOffset.x -= targetVisibleRect.minX - targetInScrollView.minX
        } else if targetInScrollView.maxX > targetVisibleRect.maxX {
            newOffset.x += targetInScrollView.maxX - targetVisibleRect.maxX
        }

        if targetInScrollView.minY < targetVisibleRect.minY {
            newOffset.y -= targetVisibleRect.minY - targetInScrollView.minY
        } else if targetInScrollView.maxY > targetVisibleRect.maxY {
            newOffset.y += targetInScrollView.maxY - targetVisibleRect.maxY
        }

        let insets = scrollView.adjustedContentInset
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        newOffset.x = max(-insets.left, min(newOffset.x, maxX))
        newOffset.y = max(-insets.top, min(newOffset.y, maxY))

        let clampedVisibleRect = visibleRect(in: scrollView, at: newOffset)
        let clampedComfortRect = makeComfortRect(
            in: clampedVisibleRect,
            comfortMarginFraction: comfortMarginFraction
        )
        let clampedTargetVisibleRect = preferredVisibleRect(
            for: targetInScrollView,
            comfortRect: clampedComfortRect,
            fullVisibleRect: clampedVisibleRect
        )
        guard revealSucceeded(
            target: targetInScrollView,
            preferredVisibleRect: clampedTargetVisibleRect,
            fullVisibleRect: clampedVisibleRect
        ) else { return false }

        if newOffset.x == scrollView.contentOffset.x && newOffset.y == scrollView.contentOffset.y { return true }

        scrollView.setContentOffset(newOffset, animated: animated)
        return true
    }

    /// Scrolls so a live accessibility activation point lands in the preferred
    /// screen rect when possible, otherwise at least inside the minimum screen rect.
    func scrollToMakeActivationPointVisible(
        _ activationPoint: CGPoint,
        in scrollView: UIScrollView,
        animated: Bool = true,
        preferredScreenRect: CGRect,
        minimumScreenRect: CGRect
    ) -> Bool {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return false }

        let pointInContent = scrollView.convert(activationPoint, from: nil)
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

        if preferredVisibleRect.contains(pointInContent) { return true }

        let targetRect = preferredVisibleRect.isUsableForPoint ? preferredVisibleRect : minimumVisibleRect
        guard targetRect.isUsableForPoint else { return false }

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
        else { return false }

        if newOffset.x == currentOffset.x && newOffset.y == currentOffset.y { return true }

        scrollView.setContentOffset(newOffset, animated: animated)
        return true
    }

    private func usableVisibleRect(
        screenRect: CGRect,
        fullVisibleRect: CGRect,
        in scrollView: UIScrollView
    ) -> CGRect {
        let contentRect = scrollView.convert(screenRect, from: nil)
        return fullVisibleRect.intersection(contentRect)
    }

    private func makeComfortRect(
        in fullVisibleRect: CGRect,
        comfortMarginFraction: CGFloat
    ) -> CGRect {
        fullVisibleRect.insetBy(
            dx: fullVisibleRect.width * comfortMarginFraction,
            dy: fullVisibleRect.height * comfortMarginFraction
        )
    }

    private func preferredVisibleRect(
        for target: CGRect,
        comfortRect: CGRect,
        fullVisibleRect: CGRect
    ) -> CGRect {
        let usesComfortX = comfortRect.width >= target.width
        let usesComfortY = comfortRect.height >= target.height
        return CGRect(
            x: usesComfortX ? comfortRect.minX : fullVisibleRect.minX,
            y: usesComfortY ? comfortRect.minY : fullVisibleRect.minY,
            width: usesComfortX ? comfortRect.width : fullVisibleRect.width,
            height: usesComfortY ? comfortRect.height : fullVisibleRect.height
        )
    }

    private func revealSucceeded(
        target: CGRect,
        preferredVisibleRect: CGRect,
        fullVisibleRect: CGRect
    ) -> Bool {
        axisRevealSucceeded(
            targetMin: target.minX,
            targetMax: target.maxX,
            preferredMin: preferredVisibleRect.minX,
            preferredMax: preferredVisibleRect.maxX,
            fullMin: fullVisibleRect.minX,
            fullMax: fullVisibleRect.maxX
        ) && axisRevealSucceeded(
            targetMin: target.minY,
            targetMax: target.maxY,
            preferredMin: preferredVisibleRect.minY,
            preferredMax: preferredVisibleRect.maxY,
            fullMin: fullVisibleRect.minY,
            fullMax: fullVisibleRect.maxY
        )
    }

    private func axisRevealSucceeded(
        targetMin: CGFloat,
        targetMax: CGFloat,
        preferredMin: CGFloat,
        preferredMax: CGFloat,
        fullMin: CGFloat,
        fullMax: CGFloat
    ) -> Bool {
        let targetLength = targetMax - targetMin
        let preferredLength = preferredMax - preferredMin
        let fullLength = fullMax - fullMin
        if targetLength <= preferredLength {
            return (targetMin >= preferredMin && targetMax <= preferredMax)
                || (targetMin >= fullMin && targetMax <= fullMax)
        }
        if targetLength <= fullLength {
            return targetMin >= fullMin && targetMax <= fullMax
        }
        return targetMax > fullMin && targetMin < fullMax
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
    func scrollToEdge(_ scrollView: UIScrollView, edge: ScrollEdge, animated: Bool = true) -> Bool {
        guard !scrollView.bhIsUnsafeForProgrammaticScrolling else { return false }

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
            return false
        }
        scrollView.setContentOffset(newOffset, animated: animated)
        return true
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
        guard let path = Self.scrollFingerPath(frame: frame, direction: direction, travel: 0.75) else { return false }
        return await swipe(from: path.start, to: path.end, duration: duration)
    }

    // MARK: - Scroll Fingerprint Animation

    /// Animate a fingerprint sweep across a frame in the given scroll direction.
    /// The finger moves opposite to content — scrolling "down" (content moves up)
    /// shows a finger sweeping from bottom to top, matching a real swipe gesture.
    /// Duration matches UIScrollView's animated setContentOffset (~300ms).
    func animateScrollFingerprint(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection,
        duration: TimeInterval = 0.3
    ) async {
        guard let path = Self.scrollFingerPath(frame: frame, direction: direction, travel: 0.5) else { return }

        let steps = 15
        let stepDelay = duration / Double(steps)

        fingerprints.beginTrackingFingerprints(at: [path.start])
        defer { fingerprints.endTrackingFingerprints() }
        for point in Self.linearPath(from: path.start, to: path.end, steps: steps) {
            fingerprints.updateTrackingFingerprints(to: [point])
            do {
                try await Task.sleep(for: .milliseconds(Int(stepDelay * 1000)))
            } catch {
                break
            }
        }
    }

    private static func scrollFingerPath(
        frame: CGRect,
        direction: UIAccessibilityScrollDirection,
        travel: CGFloat
    ) -> (start: CGPoint, end: CGPoint)? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        switch direction {
        case .down, .next:
            return (
                CGPoint(x: center.x, y: center.y + frame.height * travel / 2),
                CGPoint(x: center.x, y: center.y - frame.height * travel / 2)
            )
        case .up, .previous:
            return (
                CGPoint(x: center.x, y: center.y - frame.height * travel / 2),
                CGPoint(x: center.x, y: center.y + frame.height * travel / 2)
            )
        case .right:
            return (
                CGPoint(x: center.x + frame.width * travel / 2, y: center.y),
                CGPoint(x: center.x - frame.width * travel / 2, y: center.y)
            )
        case .left:
            return (
                CGPoint(x: center.x - frame.width * travel / 2, y: center.y),
                CGPoint(x: center.x + frame.width * travel / 2, y: center.y)
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
