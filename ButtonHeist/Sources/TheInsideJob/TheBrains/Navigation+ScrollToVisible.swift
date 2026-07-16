#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

extension Navigation {

    func executeScrollToVisible(
        target: ResolvedAccessibilityTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        switch await elementInflation.inflate(
            for: target,
            method: .scrollToVisible,
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
