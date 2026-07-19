#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

extension Navigation {

    func executeScrollToVisible(
        target: ResolvedAccessibilityTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        switch await elementInflation.inflate(
            for: target,
            method: .scrollToVisible,
        ) {
        case .inflated:
            return .success(payload: .scrollToVisible)
        case .failed(let failure):
            return failure.actionDispatchResult(payload: .scrollToVisible)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
