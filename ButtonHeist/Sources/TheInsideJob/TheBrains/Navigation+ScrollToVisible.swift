#if canImport(UIKit)
#if DEBUG
import TheScore

// MARK: - Scroll To Visible

extension Navigation {

    /// `scroll_to_visible` is the explicit viewport command wrapper over the
    /// product actionability path. It does not own separate reveal or geometry
    /// behavior.
    func executeScrollToVisible(
        _ target: ScrollToVisibleTarget,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        await actionability.executeScrollToVisible(target, recordedScreen: recordedScreen)
    }

    func executeScrollToVisible(
        elementTarget: (any SemanticElementTarget)?,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        await actionability.executeScrollToVisible(
            elementTarget: elementTarget,
            recordedScreen: recordedScreen
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
