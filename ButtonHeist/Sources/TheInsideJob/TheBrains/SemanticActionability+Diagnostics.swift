#if canImport(UIKit) && DEBUG
import UIKit

extension SemanticActionability {

    static func liveGeometrySummary(_ liveTarget: TheStash.LiveActionTarget) -> String {
        "liveFrame=\(formatRect(liveTarget.frame)) "
            + "activationPoint=\(formatPoint(liveTarget.activationPoint)) "
            + "screenBounds=\(formatRect(ScreenMetrics.current.bounds))"
    }

    func semanticRevealPlanFailureMessage(_ entry: Screen.ScreenElement) -> String {
        let description = Navigation.describeScrollTarget(entry)
        switch stash.resolveSemanticRevealScrollView(for: entry) {
        case .resolved:
            return "semantic reveal plan for known target \(description) could not be executed"
        case .failed(.missingContentOrigin):
            return "known target \(description) has no content-space position"
        case .failed(.noLiveScrollableAncestor):
            return "known target \(description) has no live scrollable ancestor in the current semantic graph"
        case .failed(.unsafeProgrammaticScroll):
            return "known target \(description) is inside a scroll view that is unsafe for programmatic semantic reveal"
        }
    }

    private static func formatRect(_ rect: CGRect) -> String {
        "(x:\(format(rect.origin.x)), y:\(format(rect.origin.y)), "
            + "w:\(format(rect.size.width)), h:\(format(rect.size.height)))"
    }

    private static func formatPoint(_ point: CGPoint) -> String {
        "(x:\(format(point.x)), y:\(format(point.y)))"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

#endif // canImport(UIKit) && DEBUG
