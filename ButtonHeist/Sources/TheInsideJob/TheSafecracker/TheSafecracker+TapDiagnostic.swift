#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheSafecracker {

    // MARK: - Tap Receiver Diagnostic

    /// Observation-only snapshot of what UIKit's hit-test sees at a given screen
    /// point. Used to enrich activate/tap failure messages without claiming
    /// any AX-element-to-UIView mapping (there is none — AX elements are
    /// frequently synthetic NSObjects with no corresponding UIView).
    ///
    /// All fields describe the *receiver UIView*, not an accessibility element.
    struct TapReceiverDiagnostic: Sendable, Equatable {
        let receiverClass: String
        let receiverAxLabel: String?
        let receiverAxIdentifier: String?
        /// True if any view in the receiver→window superview chain has
        /// `isUserInteractionEnabled == false`. UIKit absorbs the touch
        /// silently when this happens.
        let interactionDisabledInChain: Bool
        /// True if any view in the chain has `isHidden == true` or `alpha == 0`.
        let hiddenInChain: Bool
        /// `windowLevel` of the host window, captured for context.
        let windowLevel: CGFloat
        /// True when the receiver is a SwiftUI gesture-routing container
        /// (`UIKitGestureContainer` on iOS 18+, or a SwiftUI-internal mangled
        /// equivalent). When true, the receiver's own AX properties are
        /// expected to be empty — SwiftUI exposes accessibility through
        /// synthetic elements on a hosting ancestor, not on the gesture view.
        let isSwiftUIGestureContainer: Bool
    }

    /// Capture an observation-only diagnostic for the receiver at `point`.
    ///
    /// Walks the same window list as `windowForPoint`, runs the standard
    /// UIKit `hitTest`, and reads off-the-shelf properties from the result.
    /// Returns `nil` when no window contains the point — the same condition
    /// that causes `tap(at:)` to return `false`.
    ///
    /// This is a side-effect-free probe; calling it does not deliver a touch.
    func tapReceiverDiagnostic(at point: CGPoint) -> TapReceiverDiagnostic? {
        for window in TheTripwire.orderedVisibleWindows() {
            let windowPoint = window.convert(point, from: nil)
            guard let receiver = window.hitTest(windowPoint, with: nil) else { continue }

            let className = String(describing: type(of: receiver))
            let isSwiftUI = Self.isSwiftUIGestureContainerName(className)
                || Self.chainContainsHostingView(receiver)

            var interactionDisabled = false
            var hidden = false
            var node: UIView? = receiver
            while let view = node {
                if !view.isUserInteractionEnabled { interactionDisabled = true }
                if view.isHidden || view.alpha == 0 { hidden = true }
                node = view.superview
            }

            return TapReceiverDiagnostic(
                receiverClass: className,
                receiverAxLabel: receiver.accessibilityLabel,
                receiverAxIdentifier: receiver.accessibilityIdentifier,
                interactionDisabledInChain: interactionDisabled,
                hiddenInChain: hidden,
                windowLevel: window.windowLevel.rawValue,
                isSwiftUIGestureContainer: isSwiftUI
            )
        }
        return nil
    }

    // MARK: - Private Helpers

    /// Heuristic: SwiftUI's gesture-routing UIView types contain "GestureContainer"
    /// or are SwiftUI-internal mangled types. We detect by class-name substring,
    /// which is fragile across iOS versions but acceptable for an observation-only
    /// label — a wrong "isSwiftUI" hint just changes how a human reads the
    /// diagnostic, not whether the tap was attempted.
    private static func isSwiftUIGestureContainerName(_ name: String) -> Bool {
        if name.contains("GestureContainer") { return true }
        if name.hasPrefix("_TtC7SwiftUI") { return true }
        if name.hasPrefix("SwiftUI.") { return true }
        return false
    }

    private static func chainContainsHostingView(_ leaf: UIView) -> Bool {
        var node: UIView? = leaf
        while let view = node {
            let name = String(describing: type(of: view))
            if name.contains("HostingView") { return true }
            node = view.superview
        }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
