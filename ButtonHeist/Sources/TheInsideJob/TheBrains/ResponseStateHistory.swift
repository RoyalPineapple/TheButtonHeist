#if canImport(UIKit)
#if DEBUG

/// Tracks the semantic state represented by the last response sent to a driver.
@MainActor
final class ResponseStateHistory {

    /// State captured after each response sent to the driver.
    struct SentState {
        let beforeState: TheBrains.BeforeState

        var interfaceHash: String {
            beforeState.interfaceHash
        }

        var captureHash: String {
            beforeState.capture.hash
        }

        var screenId: String? {
            beforeState.screenId
        }
    }

    private enum History {
        case fresh
        case sent(SentState)
    }

    private var history: History = .fresh

    var lastSentState: SentState? {
        guard case .sent(let state) = history else { return nil }
        return state
    }

    var lastSentScreenId: String? {
        lastSentState?.screenId
    }

    var waitForChangeBaseline: TheBrains.BeforeState? {
        guard let state = lastSentState, !state.captureHash.isEmpty else { return nil }
        return state.beforeState
    }

    func record(_ beforeState: TheBrains.BeforeState) {
        history = .sent(SentState(beforeState: beforeState))
    }

    func reset() {
        history = .fresh
    }

    func screenChangedSinceLastSent(currentScreen: Screen) -> Bool {
        guard let state = lastSentState else { return false }
        return ScreenClassifier.classify(
            before: state.beforeState.screenSnapshot,
            after: ScreenClassifier.snapshot(of: currentScreen)
        ).isScreenChange
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
