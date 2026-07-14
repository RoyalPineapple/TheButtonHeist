#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

// MARK: - Scroll To Visible

extension Navigation {

    /// `scroll_to_visible` is the explicit viewport command wrapper over the
    /// product element inflation path. It does not own separate reveal or geometry
    /// behavior.
    func executeScrollToVisible(
        target: ResolvedAccessibilityTarget
    ) async -> TheSafecracker.ActionDispatchOutcome {
        switch await elementInflation.inflate(
            for: target,
            method: .scrollToVisible
        ) {
        case .inflated:
            return .success(method: .scrollToVisible)
        case .failed(let failure):
            return failure.actionDispatchOutcome(commandMethod: .scrollToVisible)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
