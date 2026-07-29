#if canImport(UIKit)
#if DEBUG

/// Owns the observation stream's platform integration.
internal enum SemanticObservationLifecycle {
    case stopped
    case running

    internal var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    internal mutating func start() -> Bool {
        guard !isRunning else { return false }
        self = .running
        return true
    }

    internal mutating func stop() -> Bool {
        guard case .running = self else { return false }
        self = .stopped
        return true
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
