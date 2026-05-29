#if canImport(UIKit)
#if DEBUG

/// Tracks the semantic state represented by the last response sent to a driver.
@MainActor
final class ResponseStateHistory {

    private enum History {
        case fresh
        case sent(TheBrains.BeforeState)
    }

    private var history: History = .fresh

    var lastSentBeforeState: TheBrains.BeforeState? {
        guard case .sent(let beforeState) = history else { return nil }
        return beforeState
    }

    var waitForChangeBaseline: TheBrains.BeforeState? {
        guard let beforeState = lastSentBeforeState, !beforeState.capture.hash.isEmpty else { return nil }
        return beforeState
    }

    func record(_ beforeState: TheBrains.BeforeState) {
        history = .sent(beforeState)
    }

    func reset() {
        history = .fresh
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
