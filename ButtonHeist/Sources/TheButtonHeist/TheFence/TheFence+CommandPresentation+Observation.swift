import Foundation

extension TheFence.Command {
    static func observationPresentationDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.ping.rawValue:
            return """
                Check Button Heist connection health. Returns cheap static app/server identity facts \
                without reading UI hierarchy or accessibility state.
                """

        case Self.getInterface.rawValue:
            return """
                Read the app accessibility hierarchy. Call once on a new screen, then track changes via \
                action deltas — re-fetch only when you need elements the delta didn't cover. \
                Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from \
                a selected leaf or container node.
                """

        case Self.getScreen.rawValue:
            return """
                Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path \
                by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true \
                to include the fresh visible accessibility tree.
                """

        case Self.waitForChange.rawValue:
            return """
                Wait for the UI to change. With no expect, returns on any tree change. With expect, \
                rides through intermediate states (spinners, loading) until the expectation is met. \
                Use after an action whose delta showed a transient state and the expectation wasn't met yet.
                """

        case Self.waitFor.rawValue:
            return """
                Wait for an element matching a predicate to appear, or to disappear with absent=true. \
                Polls on UI settle events. Returns the matched element or diagnostic info on timeout.
                """

        default:
            return nil
        }
    }
}
