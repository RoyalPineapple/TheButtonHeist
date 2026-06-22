#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

// MARK: - Scroll To Visible

extension Navigation {

    /// `scroll_to_visible` is the explicit viewport command wrapper over the
    /// product element inflation path. It does not own separate reveal or geometry
    /// behavior.
    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> TheSafecracker.InteractionResult {
        await executeScrollToVisible(elementTarget: target.elementTarget)
    }

    func executeScrollToVisible(
        elementTarget: ElementTarget?
    ) async -> TheSafecracker.InteractionResult {
        guard let elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for scroll_to_visible")
        }

        switch await elementInflation.inflate(
            for: elementTarget,
            method: .scrollToVisible,
            deallocatedBoundary: "scroll_to_visible dispatch"
        ) {
        case .inflated:
            return .success(method: .scrollToVisible)
        case .failed(let failure):
            return .failure(.scrollToVisible, message: failure.message)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
