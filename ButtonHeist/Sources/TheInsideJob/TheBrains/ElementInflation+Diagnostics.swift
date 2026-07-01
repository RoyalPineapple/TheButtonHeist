#if canImport(UIKit) && DEBUG
import UIKit

import TheScore

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
        let description = Self.semanticTargetDescription(entry)
        switch failure {
        case .missingScrollMembership:
            return "known target \(description) has no scroll membership"
        case .noLiveScrollableAncestor:
            let scrollContainer: String
            if let path = entry.scrollMembership?.containerPath {
                scrollContainer = " expectedScrollContainerPath=\(path.indices)"
            } else {
                scrollContainer = ""
            }
            return "known target \(description) has no live scrollable ancestor in the current semantic graph;"
                + scrollContainer
                + " \(stash.liveScrollContainerDiagnostics())"
        case .scanDidNotRevealTarget:
            return "known target \(description) was not visible after scroll scan"
        }
    }

    private static func semanticTargetDescription(_ entry: Screen.ScreenElement) -> String {
        let primaryDescription = Navigation.ScrollTargetDescription(entry).description
        let element = entry.element
        let summary = ElementDiagnosticSummary(
            label: element.label,
            identifier: element.identifier,
            value: element.value,
            traits: element.traits.heistTraits,
            availability: .offscreen(isReachable: entry.scrollMembership != nil)
        ).rendered(using: .compactStash)
        guard !summary.isEmpty else { return primaryDescription }
        return "\(primaryDescription) [\(summary)]"
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
