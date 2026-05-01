#if canImport(UIKit)
#if DEBUG
import UIKit

extension UIScrollView {

    /// UIKit-private scroll views that are not safe to drive with arbitrary
    /// `setContentOffset` calls.
    ///
    /// `_UIQueuingScrollView` is the internal scroll container observed inside
    /// `UIPageViewController` on iOS 26.5. UIKitCore disassembly shows that it
    /// maintains a queued transition state machine (`_completionStates`,
    /// `qDelegate`, `qDataSource`) and asserts in
    /// `_didScrollWithAnimation:force:` when a scroll-completion callback has
    /// no matching queued transition to complete.
    ///
    /// Calling public `UIScrollView.setContentOffset(_:animated:)` on this
    /// private subclass can still flow through `_stopScrollDecelerationNotify`
    /// and `_scrollViewDidEndDecelerating`, even with `animated: false`, so the
    /// crash is not avoidable by disabling animation. Synthetic swipes are not
    /// a good exploration fallback either: they enter the page-transition path
    /// and can change the app's current page instead of passively revealing
    /// off-screen content.
    @MainActor
    var bhIsUnsafeForProgrammaticScrolling: Bool {
        guard let queuingScrollViewClass = NSClassFromString("_UIQueuingScrollView") else {
            return false
        }
        return isKind(of: queuingScrollViewClass)
    }
}

#endif
#endif
