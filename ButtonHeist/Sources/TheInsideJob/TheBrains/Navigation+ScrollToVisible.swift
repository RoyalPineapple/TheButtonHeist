#if canImport(UIKit)
#if DEBUG
import TheScore

// MARK: - Scroll To Visible

extension Navigation {

    /// `scroll_to_visible` is the explicit viewport command wrapper over the
    /// product actionability path. It does not own separate reveal or geometry
    /// behavior.
    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> TheSafecracker.InteractionResult {
        await actionability.executeScrollToVisible(target)
    }

    func executeScrollToVisible(
        elementTarget: (any SemanticElementTarget)?
    ) async -> TheSafecracker.InteractionResult {
        await actionability.executeScrollToVisible(elementTarget: elementTarget)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
