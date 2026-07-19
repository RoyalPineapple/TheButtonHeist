#if canImport(UIKit)
#if DEBUG

/// Owns only the stream task lifecycle.
internal struct SemanticObservationLifecycle {
    // MARK: - Nested Types

    internal typealias DiscoveryObservation = @MainActor () async -> Navigation.InterfaceExplorationResult?

    internal struct RunningObservation {
        let task: Task<Void, Never>
        var discovery: DiscoveryObservation
    }

    internal enum Lifecycle {
        case stopped
        case running(RunningObservation)
    }

    // MARK: - Properties

    internal private(set) var lifecycle: Lifecycle = .stopped

    internal var isRunning: Bool {
        if case .running = lifecycle { true } else { false }
    }

    internal var discovery: DiscoveryObservation? {
        if case .running(let observation) = lifecycle { observation.discovery } else { nil }
    }

    // MARK: - Lifecycle

    internal mutating func start(task: Task<Void, Never>, discovery: @escaping DiscoveryObservation) {
        precondition(!isRunning, "semantic observation is already running")
        lifecycle = .running(RunningObservation(task: task, discovery: discovery))
    }

    internal mutating func replaceDiscoveryIfRunning(_ discovery: @escaping DiscoveryObservation) -> Bool {
        guard case .running(var observation) = lifecycle else { return false }
        observation.discovery = discovery
        lifecycle = .running(observation)
        return true
    }

    internal mutating func stop() -> Task<Void, Never>? {
        guard case .running(let observation) = lifecycle else { return nil }
        lifecycle = .stopped
        return observation.task
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
