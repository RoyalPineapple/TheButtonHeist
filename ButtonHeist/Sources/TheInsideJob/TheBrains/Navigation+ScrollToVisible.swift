#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

// MARK: - Scroll To Visible

extension Navigation {

    /// `scroll_to_visible` is the explicit viewport command wrapper over the
    /// product element inflation path. It does not own separate reveal or geometry
    /// behavior.
    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> TheSafecracker.ActionDispatchOutcome {
        await executeScrollToVisible(target: target.target)
    }

    func executeScrollToVisible(
        target: AccessibilityTarget?
    ) async -> TheSafecracker.ActionDispatchOutcome {
        guard let target else {
            return .failure(
                .scrollToVisible,
                message: "Element target required for scroll_to_visible",
                failureKind: .inputValidation
            )
        }

        switch await elementInflation.inflate(
            for: target,
            method: .scrollToVisible,
            deallocatedBoundary: "scroll_to_visible dispatch"
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
