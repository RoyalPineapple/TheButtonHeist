#if canImport(UIKit) && DEBUG
import UIKit

extension ElementInflation {

    static func liveGeometrySummary(_ liveTarget: TheStash.LiveActionTarget) -> String {
        "liveFrame=\(formatRect(liveTarget.frame)) "
            + "activationPoint=\(formatPoint(liveTarget.activationPoint)) "
            + "screenBounds=\(formatRect(ScreenMetrics.current.bounds))"
    }

    func semanticRevealFailureMessage(
        _ failure: SemanticRevealFailure,
        entry: Screen.ScreenElement
    ) -> String {
        let description = Navigation.ScrollTargetDescription(entry).description
        switch failure {
        case .missingContentOrigin:
            return "known target \(description) has no content-space position"
        case .noLiveScrollableAncestor:
            let scrollContainer: String
            if let containerName = entry.scrollContentLocation?.scrollContainer {
                scrollContainer = " expectedScrollContainer=\(containerName)"
            } else {
                scrollContainer = ""
            }
            return "known target \(description) has no live scrollable ancestor in the current semantic graph;"
                + scrollContainer
                + " \(stash.liveScrollContainerDiagnostics())"
        case .unsafeProgrammaticScroll:
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
